--!strict
--[[
	AdminService : outils réservés aux administrateurs (Config.Admin).

	- Qui est administrateur : décidé par le serveur à l'arrivée du joueur
	  (identifiant Roblox listé, rang dans un groupe, ou Roblox Studio si la
	  config le permet). L'attribut `IsAdmin` du joueur sert seulement à
	  afficher le panneau côté client : chaque demande est revérifiée ici.
	- Offrir des crédits à un joueur présent sur le serveur (plafonnés par envoi
	  et par le maximum de crédits d'un profil), journalisés de la même façon.
	- Offrir des caisses (giveaway) : caisse gratuite ou caisses du Holo-Bazar,
	  à un joueur présent sur le serveur. Elles s'ajoutent à son profil
	  (`crateTokens`) et s'ouvrent gratuitement au Holo-Bazar / au bouton de
	  la caisse gratuite. Chaque cadeau est journalisé (TransactionLog), chez
	  le joueur et chez l'administrateur.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Guard = require(Shared.Util.Guard)

local CrateGifts = require(script.Parent.Parent.Economy.CrateGifts)
local TransactionLog = require(script.Parent.Parent.Economy.TransactionLog)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)

local AdminService = {}

local admins: { [Player]: boolean } = {}

local function check(player: Player)
	local rank = 0
	if Config.Admin.groupId ~= 0 then
		local ok, value = pcall(function()
			return player:GetRankInGroup(Config.Admin.groupId)
		end)
		if ok and type(value) == "number" then
			rank = value
		end
	end
	local isAdmin = CrateGifts.isAdmin(player.UserId, rank, RunService:IsStudio())
	admins[player] = if isAdmin then true else nil
	player:SetAttribute("IsAdmin", isAdmin)
end

local function gift(admin: Player, targetUserId: number, kind: string, amount: number)
	if not admins[admin] then
		ServerNet.flag(admin, "AdminGiftCrates", "demande d'un non-administrateur")
		return
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if target == nil then
		ServerNet.notify(admin, "admin.failure.offline")
		return
	end
	local granted, reason, total = false, nil :: string?, 0
	DataService.update(target, function(profile)
		granted, reason, total = CrateGifts.grant(profile, kind, amount)
		return granted
	end)
	if not granted then
		ServerNet.notify(admin, "admin.failure." .. tostring(reason or "unknown"))
		return
	end
	-- Un cadeau ne doit pas se perdre : sauvegarde immédiate.
	task.spawn(DataService.saveNow, target)
	local detail = { admin = admin.UserId, target = target.UserId, crate = kind, amount = amount, total = total }
	TransactionLog.record(target, "admin.gift", detail)
	if admin ~= target then
		TransactionLog.record(admin, "admin.gift", detail)
	end
	ServerNet.notify(target, "gift.received." .. kind, { count = amount })
	ServerNet.notify(admin, "admin.given." .. kind, { count = amount, name = target.DisplayName })
end

local function giftCredits(admin: Player, targetUserId: number, amount: number)
	if not admins[admin] then
		ServerNet.flag(admin, "AdminGiftCredits", "demande d'un non-administrateur")
		return
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if target == nil then
		ServerNet.notify(admin, "admin.failure.offline")
		return
	end
	local granted, reason, added = false, nil :: string?, 0
	DataService.update(target, function(profile)
		granted, reason, added = CrateGifts.grantCredits(profile, amount)
		return granted
	end)
	if not granted then
		ServerNet.notify(admin, "admin.failure." .. tostring(reason or "unknown"))
		return
	end
	task.spawn(DataService.saveNow, target)
	local detail = { admin = admin.UserId, target = target.UserId, credits = added }
	TransactionLog.record(target, "admin.giftCredits", detail)
	if admin ~= target then
		TransactionLog.record(admin, "admin.giftCredits", detail)
	end
	ServerNet.notify(target, "gift.receivedCredits", { credits = added })
	ServerNet.notify(admin, "admin.givenCredits", { credits = added, name = target.DisplayName })
end

function AdminService.init()
	ServerNet.onEvent(
		"AdminGiftCredits",
		Guard.tuple(
			Guard.integer(), -- UserId (négatif pour les joueurs de test de Studio)
			Guard.integer(1, Config.Admin.maxCreditsPerGift)
		),
		giftCredits
	)
	ServerNet.onEvent(
		"AdminGiftCrates",
		Guard.tuple(
			Guard.integer(), -- UserId (négatif pour les joueurs de test de Studio)
			Guard.enum(Config.Admin.giftCrates :: { string }),
			Guard.integer(1, Config.Admin.maxPerGift)
		),
		gift
	)
end

function AdminService.start()
	Players.PlayerAdded:Connect(check)
	for _, player in Players:GetPlayers() do
		task.spawn(check, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		admins[player] = nil
	end)
end

return AdminService
