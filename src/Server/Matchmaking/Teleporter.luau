--!strict
--[[
	Teleporter : téléportations avec nouvelles tentatives (section 16.3).

	TeleportAsync peut échouer immédiatement (erreur) ou plus tard
	(TeleportInitFailed). Dans les deux cas on réessaie, puis on appelle
	`onFailed` pour chaque joueur resté sur le serveur.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local Teleporter = {}

type Pending = {
	placeId: number,
	options: TeleportOptions?,
	attempts: number,
	onFailed: (player: Player) -> (),
}

local pending: { [Player]: Pending } = {}
local connected = false

local function fail(player: Player)
	local entry = pending[player]
	if entry == nil then
		return
	end
	pending[player] = nil
	if player.Parent == Players then
		task.spawn(entry.onFailed, player)
	end
end

local function attempt(players: { Player }, placeId: number, options: TeleportOptions?): boolean
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(placeId, players, options)
	end)
	if not ok then
		warn(`[Teleporter] échec de téléportation vers {placeId} : {err}`)
	end
	return ok
end

local function connect()
	if connected then
		return
	end
	connected = true
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		local entry = pending[player]
		if entry == nil then
			return
		end
		warn(`[Teleporter] {player.UserId} : {result} {message}`)
		entry.attempts += 1
		if entry.attempts >= Config.Matchmaking.teleport.retries then
			fail(player)
			return
		end
		task.wait(Config.Matchmaking.teleport.retryDelay)
		if pending[player] == entry and player.Parent == Players then
			if not attempt({ player }, entry.placeId, entry.options) then
				fail(player)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
	end)
end

--[[
	Téléporte un groupe (les duos restent ensemble). `onFailed` est appelé
	pour chaque joueur qui n'a pas pu partir après toutes les tentatives.
]]
function Teleporter.send(
	players: { Player },
	placeId: number,
	options: TeleportOptions?,
	onFailed: (player: Player) -> ()
)
	connect()
	for _, player in players do
		pending[player] = { placeId = placeId, options = options, attempts = 0, onFailed = onFailed }
	end
	task.spawn(function()
		for index = 1, Config.Matchmaking.teleport.retries do
			local present = {}
			for _, player in players do
				if pending[player] and player.Parent == Players then
					table.insert(present, player)
				end
			end
			if #present == 0 then
				return
			end
			if attempt(present, placeId, options) then
				return -- la suite (succès ou TeleportInitFailed) est asynchrone
			end
			if index < Config.Matchmaking.teleport.retries then
				task.wait(Config.Matchmaking.teleport.retryDelay)
			end
		end
		for _, player in players do
			fail(player)
		end
	end)
end

-- Renvoie un joueur au Terminus (fin de partie, joueur inattendu…).
function Teleporter.toHub(player: Player, onFailed: (player: Player) -> ())
	Teleporter.send({ player }, Config.Matchmaking.places.hub, nil, onFailed)
end

return Teleporter
