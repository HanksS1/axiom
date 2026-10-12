--!strict
--[[
	InventoryService : inventaire porté pendant une partie (section 8).

	- Synchronise le sac (emplacements + contenu + UP) avec son propriétaire.
	- Actions validées par le serveur : équiper depuis le sac, ranger un objet
	  équipé, jeter un objet au sol, utiliser un consommable.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Guard = require(Shared.Util.Guard)
local InventoryLogic = require(Shared.Items.InventoryLogic)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local Config = require(Shared.Config)
local Types = require(Shared.Types)

local Fighter = require(script.Parent.Parent.Combat.Fighter)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local CombatService = require(script.Parent.CombatService)
local LootService = require(script.Parent.LootService)

type Fighter = Fighter.Fighter

local InventoryService = {}

local queued: { [Fighter]: boolean } = {}

local SLOT_NAMES = { "ranged", "melee", "gadget1", "gadget2", "helmet", "vest", "backpack" }

local function snapshot(fighter: Fighter): { [string]: any }
	local bag = fighter.bag :: InventoryLogic.Inventory
	local equipped = {}
	for _, slot in ItemCatalog.slotNames do
		local item = (bag.equipped :: any)[slot] :: Types.ItemInstance?
		if item then
			equipped[slot] = table.clone(item)
		end
	end
	local items = {}
	for _, item in bag.bag do
		table.insert(items, table.clone(item))
	end
	return {
		equipped = equipped,
		bag = items,
		capacity = InventoryLogic.capacity(bag),
		used = InventoryLogic.used(bag),
		bonusUp = bag.bonusUp,
	}
end

function InventoryService.queueSync(fighter: Fighter)
	local player = fighter.player
	if player == nil or fighter.bag == nil or queued[fighter] then
		return
	end
	queued[fighter] = true
	task.defer(function()
		queued[fighter] = nil
		if player.Parent ~= nil and CombatService.getFighter(player) == fighter and fighter.bag then
			ServerNet.fire("InventorySync", player, snapshot(fighter))
		end
	end)
end

-- Rattache un sac de partie à un combattant (apparition, début de partie).
function InventoryService.attach(fighter: Fighter, bag: InventoryLogic.Inventory)
	fighter.bag = bag
	fighter.inventory = Fighter.bagInventory(fighter)
	fighter.onInventoryChanged = function()
		InventoryService.queueSync(fighter)
	end
	CombatService.equipmentChanged(fighter)
	InventoryService.queueSync(fighter)
end

local function actor(player: Player): (Fighter?, InventoryLogic.Inventory?)
	local fighter = CombatService.getFighter(player)
	if fighter == nil or fighter.bag == nil or not Fighter.isAlive(fighter) then
		return nil, nil
	end
	return fighter, fighter.bag
end

local function changed(fighter: Fighter)
	CombatService.equipmentChanged(fighter)
	InventoryService.queueSync(fighter)
end

local function notifyFailure(player: Player, failure: string?)
	ServerNet.notify(player, "inventory.failure." .. tostring(failure or "unknown"))
end

function InventoryService.init()
	ServerNet.onEvent(
		"EquipItem",
		Guard.tuple(Guard.uid(), Guard.enum(SLOT_NAMES)),
		function(player, uid: string, slot: Types.SlotName)
			local fighter, bag = actor(player)
			if fighter == nil or bag == nil then
				return
			end
			local ok, failure = InventoryLogic.equipFromBag(bag, uid, slot)
			if not ok then
				notifyFailure(player, failure)
				InventoryService.queueSync(fighter)
				return
			end
			changed(fighter)
		end
	)

	ServerNet.onEvent("UnequipItem", Guard.tuple(Guard.enum(SLOT_NAMES)), function(player, slot: Types.SlotName)
		local fighter, bag = actor(player)
		if fighter == nil or bag == nil then
			return
		end
		local ok, failure = InventoryLogic.unequip(bag, slot)
		if not ok then
			notifyFailure(player, failure)
			return
		end
		changed(fighter)
	end)

	ServerNet.onEvent("DropItem", Guard.tuple(Guard.uid()), function(player, uid: string)
		local fighter, bag = actor(player)
		if fighter == nil or bag == nil then
			return
		end
		local item, failure = InventoryLogic.take(bag, uid)
		if item == nil then
			notifyFailure(player, failure)
			InventoryService.queueSync(fighter)
			return
		end
		local look = fighter.root.CFrame.LookVector
		LootService.dropToGround(fighter.root.Position + Vector3.new(look.X, 0, look.Z) * 2.5, { item })
		changed(fighter)
	end)

	ServerNet.onEvent(
		"UseConsumable",
		Guard.tuple(Guard.keyOf(Config.Equipment.consumables)),
		function(player, itemId: string)
			local fighter = actor(player)
			if fighter == nil then
				return
			end
			local ok, reason = CombatService.useConsumable(fighter, itemId)
			if not ok and reason ~= "busy" then
				ServerNet.notify(player, "consumable.failure." .. tostring(reason))
			end
		end
	)
end

function InventoryService.start() end

return InventoryService
