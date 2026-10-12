--!strict
--[[
	ServerNet : création et protection des remotes côté serveur.

	Chaque remote appelable par le client passe par :
	1. une limite de fréquence par joueur (Config/Network) ;
	2. une validation stricte des types (Shared/Util/Guard) ;
	3. un appel protégé (pcall) du gestionnaire.

	Les rejets sont journalisés ; au-delà d'un seuil par minute, le joueur
	est expulsé (client modifié ou script de triche).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Localization = require(Shared.Localization)
local RateLimiter = require(Shared.Util.RateLimiter)
local Remotes = require(Shared.Net.Remotes)
local try = require(Shared.Util.Try)

type Validator = (...any) -> (boolean, string?)

local ServerNet = {}

local folder: Folder
local instances: { [string]: RemoteEvent | RemoteFunction } = {}
local limiters: { [string]: RateLimiter.RateLimiter } = {}
local handled: { [string]: boolean } = {}
local rejections: { [Player]: { count: number, windowStart: number } } = {}

local REJECTION_WINDOW = 60

local function getInstance(name: string): any
	local instance = instances[name]
	assert(instance ~= nil, `remote inconnue : {name}`)
	return instance
end

local function kickForAbuse(player: Player)
	local lang: Localization.Language = Localization.resolve(nil, player.LocaleId)
	player:Kick(Localization.get(lang, "kick.suspiciousActivity"))
end

-- Enregistre un rejet ; retourne toujours false pour simplifier l'appelant.
local function reject(player: Player, remoteName: string, reason: string): boolean
	local now = os.clock()
	local entry = rejections[player]
	if entry == nil or now - entry.windowStart > REJECTION_WINDOW then
		entry = { count = 0, windowStart = now }
		rejections[player] = entry
	end
	entry.count += 1
	-- Journal limité : le premier rejet de chaque fenêtre, puis un sur 20.
	if entry.count == 1 or entry.count % 20 == 0 then
		warn(`[ServerNet] rejet {remoteName} de {player.Name} ({player.UserId}) : {reason} (x{entry.count})`)
	end
	if entry.count >= Config.Network.kickAfterRejectionsPerMinute then
		kickForAbuse(player)
	end
	return false
end

local function admit(player: Player, name: string, validator: Validator, ...: any): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return false
	end
	if not limiters[name]:consume(player) then
		return reject(player, name, "limite de fréquence")
	end
	local ok, reason = validator(...)
	if not ok then
		return reject(player, name, reason or "validation")
	end
	return true
end

function ServerNet.init()
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then
		existing:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "Remotes"

	for name, def in Remotes do
		local instance: any
		if def.kind == "event" then
			instance = Instance.new("RemoteEvent")
		elseif def.kind == "unreliable" then
			assert(not def.toServer, `UnreliableRemoteEvent {name} : réservé au serveur → client`)
			instance = Instance.new("UnreliableRemoteEvent")
		else
			assert(def.toServer, `RemoteFunction {name} : le serveur n'invoque jamais le client`)
			instance = Instance.new("RemoteFunction")
		end
		instance.Name = name
		instance.Parent = folder
		instances[name] = instance

		if def.toServer then
			local limit = Config.Network.limits[name]
			assert(limit ~= nil, `aucune limite de fréquence pour la remote {name} (Config/Network)`)
			limiters[name] = RateLimiter.new(limit.rate, limit.burst)
		end
	end

	folder.Parent = ReplicatedStorage

	Players.PlayerRemoving:Connect(function(player)
		rejections[player] = nil
		for _, limiter in limiters do
			limiter:reset(player)
		end
	end)
end

-- Vérifie au démarrage que toutes les remotes client → serveur ont un gestionnaire.
function ServerNet.assertAllHandled()
	for name, def in Remotes do
		if def.toServer and not handled[name] then
			warn(`[ServerNet] la remote {name} n'a pas de gestionnaire`)
		end
	end
end

function ServerNet.onEvent(name: string, validator: Validator, handler: (player: Player, ...any) -> ())
	local def = Remotes[name]
	assert(def and def.kind == "event" and def.toServer, `{name} n'est pas un RemoteEvent client → serveur`)
	assert(not handled[name], `gestionnaire déjà défini pour {name}`)
	handled[name] = true
	local remote = getInstance(name) :: RemoteEvent
	remote.OnServerEvent:Connect(function(player, ...)
		if not admit(player, name, validator, ...) then
			return
		end
		local ok, err = try(handler, player, ...)
		if not ok then
			warn(`[ServerNet] erreur dans {name} : {err}`)
		end
	end)
end

--[[
	Gestionnaire de RemoteFunction. En cas de rejet ou d'erreur, le client
	reçoit `nil` (jamais le message d'erreur interne).
]]
function ServerNet.onRequest(name: string, validator: Validator, handler: (player: Player, ...any) -> ...any)
	local def = Remotes[name]
	assert(def and def.kind == "function", `{name} n'est pas une RemoteFunction`)
	assert(not handled[name], `gestionnaire déjà défini pour {name}`)
	handled[name] = true
	local remote = getInstance(name) :: RemoteFunction
	remote.OnServerInvoke = function(player, ...)
		if not admit(player, name, validator, ...) then
			return nil
		end
		local results = table.pack(pcall(handler, player, ...))
		if not results[1] then
			warn(`[ServerNet] erreur dans {name} : {results[2]}`)
			return nil
		end
		return table.unpack(results, 2, results.n)
	end
end

function ServerNet.fire(name: string, player: Player, ...: any)
	local remote = getInstance(name) :: RemoteEvent
	remote:FireClient(player, ...)
end

function ServerNet.fireAll(name: string, ...: any)
	local remote = getInstance(name) :: RemoteEvent
	remote:FireAllClients(...)
end

-- Envoie à tous les joueurs sauf un (ex. : le tireur a déjà affiché son tir).
function ServerNet.fireAllExcept(name: string, except: Player?, ...: any)
	local remote = getInstance(name) :: RemoteEvent
	for _, player in Players:GetPlayers() do
		if player ~= except then
			remote:FireClient(player, ...)
		end
	end
end

--[[
	Signale une incohérence détectée par un service (tir impossible, coup
	hors de portée…). Compte comme un rejet : journalisé, et au-delà du
	seuil par minute, le joueur est expulsé.
]]
function ServerNet.flag(player: Player, remoteName: string, reason: string)
	reject(player, remoteName, reason)
end

-- Notification localisée : le client traduit la clé dans sa langue.
function ServerNet.notify(player: Player, key: string, params: { [string]: any }?)
	ServerNet.fire("Notify", player, key, params)
end

return ServerNet
