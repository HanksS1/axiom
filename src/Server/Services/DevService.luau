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
	- equipRifle / equipPistol : équipe le Fusil de Sentinelle / le pistolet
	                    maison (état Bon) avec des cellules, puis fait réapparaître
	- equipArmor      : équipe gilet et casque (état = amount, 4 par défaut)
	- respawn         : fait réapparaître le personnage
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

local COMMANDS = {
	"addCredits",
	"addXp",
	"giveKit",
	"giveRandom",
	"clearVault",
	"saveNow",
	"equipRifle",
	"equipPistol",
	"equipArmor",
	"respawn",
}

local random = Random.new()

local function randomItemId(): string
	local ids = {}
	for id in ItemCatalog.all() do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids[random:NextInteger(1, #ids)]
end

-- Équipe une arme à distance (Bon état) et ajoute des piles de cellules adaptées.
local function equipRanged(player: Player, itemId: string)
	local info = ItemCatalog.get(itemId)
	if info == nil then
		return
	end
	local updated = DataService.update(player, function(profile)
		profile.loadout.ranged = ItemFactory.create(itemId, { condition = Config.Conditions.GOOD })
		if profile.loadout.melee == nil then
			profile.loadout.melee = ItemFactory.create("shock_crowbar", { condition = Config.Conditions.GOOD })
		end
		for _ = 1, 3 do
			table.insert(profile.bag, ItemFactory.create(info.def.cell))
		end
	end)
	if updated then
		player:LoadCharacter()
	end
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
	equipRifle = function(player)
		equipRanged(player, "sentinel_rifle")
	end,
	equipPistol = function(player)
		equipRanged(player, "scrap_laser_pistol")
	end,
	equipArmor = function(player, amount)
		local condition = math.clamp(amount or Config.Conditions.GOOD, Config.Conditions.MIN, Config.Conditions.MAX)
		local updated = DataService.update(player, function(profile)
			profile.loadout.vest = ItemFactory.create("vest", { condition = condition })
			profile.loadout.helmet = ItemFactory.create("helmet", { condition = condition })
		end)
		if updated then
			player:LoadCharacter()
		end
	end,
	respawn = function(player)
		player:LoadCharacter()
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
