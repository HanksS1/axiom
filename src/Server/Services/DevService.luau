--!strict
--[[
	DevService : commandes de test, actives UNIQUEMENT dans Roblox Studio.
	En production, la remote est ignorée (et tout appel est rejeté).

	Commandes (via le panneau DEV côté client) :
	- addCredits <n>  : ajoute (ou retire) des crédits
	- addXp <n>       : ajoute de l'XP (avec passage de niveaux)
	- giveKit         : équipe le kit de base si les emplacements sont vides
	- giveRandom      : ajoute un objet aléatoire au coffre (si la place le permet)
	- clearVault      : vide le coffre
	- saveNow         : force une sauvegarde
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Guard = require(Shared.Util.Guard)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local ItemRules = require(Shared.Items.ItemRules)
local Leveling = require(Shared.Progression.Leveling)

local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local ItemFactory = require(script.Parent.Parent.Inventory.ItemFactory)
local DataService = require(script.Parent.DataService)

local DevService = {}

local COMMANDS = { "addCredits", "addXp", "giveKit", "giveRandom", "clearVault", "saveNow" }

local random = Random.new()

local function randomItemId(): string
	local ids = {}
	for id in ItemCatalog.all() do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids[random:NextInteger(1, #ids)]
end

local handlers: { [string]: (player: Player, amount: number?) -> () } = {
	addCredits = function(player, amount)
		DataService.update(player, function(profile)
			profile.credits = math.clamp(profile.credits + (amount or 100), 0, Config.Economy.maxCredits)
		end)
	end,
	addXp = function(player, amount)
		DataService.update(player, function(profile)
			profile.level, profile.xp = Leveling.addXp(profile.level, profile.xp, amount or 500)
		end)
	end,
	giveKit = function(player)
		DataService.update(player, function(profile)
			local loadout, bag = ItemFactory.createBaseKit()
			for slot, item in loadout :: any do
				if (profile.loadout :: any)[slot] == nil then
					(profile.loadout :: any)[slot] = item
				end
			end
			if #profile.bag == 0 then
				profile.bag = bag
			end
		end)
	end,
	giveRandom = function(player)
		DataService.update(player, function(profile)
			local item = ItemFactory.create(randomItemId(), {
				condition = random:NextInteger(Config.Conditions.MIN, Config.Conditions.MAX),
			})
			local capacity = ItemRules.vaultCapacity(profile.hasVaultExtension)
			if ItemRules.totalUp(profile.vault) + ItemRules.up(item) > capacity then
				error("coffre plein")
			end
			table.insert(profile.vault, item)
		end)
	end,
	clearVault = function(player)
		DataService.update(player, function(profile)
			profile.vault = {}
		end)
	end,
	saveNow = function(player)
		DataService.saveNow(player)
	end,
}

function DevService.init()
	local enabled = RunService:IsStudio()
	ServerNet.onEvent(
		"DevCommand",
		Guard.tuple(Guard.enum(COMMANDS), Guard.optional(Guard.integer(-1_000_000, 1_000_000))),
		function(player, command: string, amount: number?)
			if not enabled then
				return
			end
			handlers[command](player, amount)
		end
	)
end

function DevService.start() end

return DevService
