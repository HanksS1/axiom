--!strict
--[[
	InventoryLogic : règles PURES de l'inventaire porté pendant une partie
	(sections 8.1 à 8.3, 9.3).

	Un inventaire = emplacements équipés + contenu du sac + bonus d'UP
	(Exo-harnais). Les objets équipés ne prennent pas de place dans le sac.
	Toutes les fonctions modifient la table passée en paramètre et
	retournent (succès, raison) : le serveur les applique, le client les
	utilise pour griser les actions impossibles.
]]

local Types = require(script.Parent.Parent.Types)
local ItemCatalog = require(script.Parent.ItemCatalog)
local ItemRules = require(script.Parent.ItemRules)

type ItemInstance = Types.ItemInstance
type SlotName = Types.SlotName

export type Inventory = {
	equipped: Types.Loadout,
	bag: { ItemInstance },
	bonusUp: number,
}

export type Failure = "bag_full" | "not_found" | "wrong_slot" | "slot_empty" | "too_small"

local InventoryLogic = {}

function InventoryLogic.new(equipped: Types.Loadout?, bag: { ItemInstance }?): Inventory
	return { equipped = equipped or {}, bag = bag or {}, bonusUp = 0 }
end

function InventoryLogic.capacity(inventory: Inventory): number
	return ItemRules.bagCapacity(inventory.equipped.backpack, inventory.bonusUp)
end

function InventoryLogic.used(inventory: Inventory): number
	return ItemRules.totalUp(inventory.bag)
end

function InventoryLogic.free(inventory: Inventory): number
	return InventoryLogic.capacity(inventory) - InventoryLogic.used(inventory)
end

-- Deux piles peuvent fusionner : même objet, même statut (kit / temporaire).
local function sameStackKind(a: ItemInstance, b: ItemInstance): boolean
	return a.itemId == b.itemId and (a.isKit == true) == (b.isKit == true) and a.tempGamesLeft == b.tempGamesLeft
end

-- Quantité d'une pile qui peut rejoindre des piles existantes non pleines.
local function mergeableAmount(inventory: Inventory, item: ItemInstance): number
	local info = ItemCatalog.get(item.itemId)
	if info == nil or info.stackSize == nil then
		return 0
	end
	local room = 0
	for _, other in inventory.bag do
		if sameStackKind(other, item) then
			room += info.stackSize - (other.stack or 0)
		end
	end
	return math.min(room, item.stack or 0)
end

function InventoryLogic.findInBag(inventory: Inventory, uid: string): (ItemInstance?, number?)
	for index, item in inventory.bag do
		if item.uid == uid then
			return item, index
		end
	end
	return nil, nil
end

-- Emplacement d'un objet équipé (nil s'il n'est pas équipé).
function InventoryLogic.findEquipped(inventory: Inventory, uid: string): SlotName?
	for _, slot in ItemCatalog.slotNames do
		local item = (inventory.equipped :: any)[slot] :: ItemInstance?
		if item and item.uid == uid then
			return (slot :: any) :: SlotName
		end
	end
	return nil
end

-- L'objet entre-t-il (entièrement) dans le sac ?
function InventoryLogic.canStore(inventory: Inventory, item: ItemInstance): boolean
	if mergeableAmount(inventory, item) >= (item.stack or math.huge) then
		return true
	end
	return InventoryLogic.free(inventory) >= ItemRules.up(item)
end

--[[
	Range un objet dans le sac. Les piles fusionnent d'abord avec les piles
	existantes ; s'il reste une partie sans place, elle est retournée
	(`leftover`, même uid) et l'appelant la laisse où elle était.
	Retourne (au moins une partie rangée, reste éventuel).
]]
function InventoryLogic.store(inventory: Inventory, item: ItemInstance): (boolean, ItemInstance?)
	local info = ItemCatalog.get(item.itemId)
	if info == nil then
		return false, item
	end
	if info.stackSize ~= nil then
		local original = item.stack or 0
		local remaining = original
		for _, other in inventory.bag do
			if remaining <= 0 then
				break
			end
			if sameStackKind(other, item) then
				local room = info.stackSize - (other.stack or 0)
				local moved = math.min(room, remaining)
				if moved > 0 then
					other.stack = (other.stack or 0) + moved
					remaining -= moved
				end
			end
		end
		if remaining <= 0 then
			return true, nil
		end
		item.stack = remaining
		if InventoryLogic.free(inventory) >= ItemRules.up(item) then
			table.insert(inventory.bag, item)
			return true, nil
		end
		-- Rangement partiel : le reste ne rentre pas.
		return remaining < original, item
	end
	if InventoryLogic.free(inventory) < ItemRules.up(item) then
		return false, item
	end
	table.insert(inventory.bag, item)
	return true, nil
end

--[[
	« Tout prendre » : range ce qui tient, le plus précieux d'abord. Un objet
	d'équipement va dans son emplacement s'il est vide ; sinon il doit tenir dans
	le sac. Ce qui ne tient pas est rendu dans `kept` (il reste dans le conteneur) :
	le sac n'est JAMAIS surchargé (une pile peut être prise en partie).
	Retourne (objets pris, objets laissés). Modifie `inventory`.
]]
function InventoryLogic.takeAll(inventory: Inventory, items: { ItemInstance }): ({ ItemInstance }, { ItemInstance })
	local sorted = table.clone(items)
	table.sort(sorted, function(a, b)
		return ItemRules.value(a) > ItemRules.value(b)
	end)
	local taken: { ItemInstance } = {}
	local kept: { ItemInstance } = {}
	for _, item in sorted do
		local info = ItemCatalog.get(item.itemId)
		local slot = InventoryLogic.slotFor(inventory, item.itemId)
		local done = false
		if info and info.hasCondition and slot ~= nil and (inventory.equipped :: any)[slot] == nil then
			done = InventoryLogic.equipFromOutside(inventory, item, slot) == true
		end
		if not done then
			local stored, leftover = InventoryLogic.store(inventory, item)
			done = stored and leftover == nil
		end
		table.insert(if done then taken else kept, item)
	end
	return taken, kept
end

function InventoryLogic.removeFromBag(inventory: Inventory, uid: string): ItemInstance?
	local item, index = InventoryLogic.findInBag(inventory, uid)
	if item and index then
		table.remove(inventory.bag, index)
	end
	return item
end

-- Emplacement naturel d'un objet : premier emplacement compatible libre,
-- sinon le premier compatible (échange).
function InventoryLogic.slotFor(inventory: Inventory, itemId: string): SlotName?
	local info = ItemCatalog.get(itemId)
	if info == nil then
		return nil
	end
	-- (typage relâché : le vieux solveur élargit les singletons en `string`)
	local categories = ItemCatalog.slotCategories :: any
	local candidates: { any } = {}
	for _, slot in ItemCatalog.slotNames :: { any } do
		if categories[slot] == info.category then
			table.insert(candidates, slot)
		end
	end
	for _, slot in candidates do
		if (inventory.equipped :: any)[slot] == nil then
			return slot
		end
	end
	return candidates[1]
end

--[[
	Équipe un objet venant de l'extérieur (sol, caisse) dans `slot`.
	L'objet précédemment équipé est retourné (l'appelant le dépose là d'où
	venait le nouvel objet : « l'arme équipée tombe au sol »).
	Pour un sac, le contenu actuel doit tenir dans la nouvelle capacité.
]]
function InventoryLogic.equipFromOutside(
	inventory: Inventory,
	item: ItemInstance,
	slot: SlotName
): (boolean, Failure?, ItemInstance?)
	local info = ItemCatalog.get(item.itemId)
	if info == nil or ItemCatalog.slotCategories[slot] ~= info.category then
		return false, "wrong_slot", nil
	end
	if slot == "backpack" then
		local newCapacity = ItemRules.bagCapacity(item, inventory.bonusUp)
		if InventoryLogic.used(inventory) > newCapacity then
			return false, "too_small", nil
		end
	end
	local previous = (inventory.equipped :: any)[slot] :: ItemInstance?
	(inventory.equipped :: any)[slot] = item
	return true, nil, previous
end

--[[
	Équipe un objet du sac. L'objet déjà équipé retourne dans le sac
	(il faut donc de la place une fois le nouvel objet sorti du sac).
]]
function InventoryLogic.equipFromBag(inventory: Inventory, uid: string, slot: SlotName): (boolean, Failure?)
	local item = InventoryLogic.findInBag(inventory, uid)
	if item == nil then
		return false, "not_found"
	end
	local info = ItemCatalog.get(item.itemId)
	if info == nil or ItemCatalog.slotCategories[slot] ~= info.category then
		return false, "wrong_slot"
	end
	local previous = (inventory.equipped :: any)[slot] :: ItemInstance?
	local usedAfter = InventoryLogic.used(inventory)
		- ItemRules.up(item)
		+ (if previous then ItemRules.up(previous) else 0)
	local capacityAfter = if slot == "backpack"
		then ItemRules.bagCapacity(item, inventory.bonusUp)
		else InventoryLogic.capacity(inventory)
	if usedAfter > capacityAfter then
		return false, if slot == "backpack" then "too_small" else "bag_full"
	end
	InventoryLogic.removeFromBag(inventory, uid);
	(inventory.equipped :: any)[slot] = item
	if previous then
		table.insert(inventory.bag, previous)
	end
	return true, nil
end

-- Range un objet équipé dans le sac.
function InventoryLogic.unequip(inventory: Inventory, slot: SlotName): (boolean, Failure?)
	local item = (inventory.equipped :: any)[slot] :: ItemInstance?
	if item == nil then
		return false, "slot_empty"
	end
	local capacityAfter = if slot == "backpack"
		then ItemRules.bagCapacity(nil, inventory.bonusUp)
		else InventoryLogic.capacity(inventory)
	if InventoryLogic.used(inventory) + ItemRules.up(item) > capacityAfter then
		return false, if slot == "backpack" then "too_small" else "bag_full"
	end
	(inventory.equipped :: any)[slot] = nil
	table.insert(inventory.bag, item)
	return true, nil
end

-- Retire un objet (sac ou emplacement) pour le jeter.
function InventoryLogic.take(inventory: Inventory, uid: string): (ItemInstance?, Failure?)
	local item = InventoryLogic.removeFromBag(inventory, uid)
	if item then
		return item, nil
	end
	local slot = InventoryLogic.findEquipped(inventory, uid)
	if slot == nil then
		return nil, "not_found"
	end
	local equippedItem = (inventory.equipped :: any)[slot] :: ItemInstance
	if slot == "backpack" and InventoryLogic.used(inventory) > ItemRules.bagCapacity(nil, inventory.bonusUp) then
		return nil, "too_small"
	end
	(inventory.equipped :: any)[slot] = nil
	return equippedItem, nil
end

function InventoryLogic.count(inventory: Inventory, itemId: string): number
	local total = 0
	for _, item in inventory.bag do
		if item.itemId == itemId then
			total += item.stack or 1
		end
	end
	return total
end

--[[
	Prélève `amount` unités d'un objet empilable (cellules, consommables).
	Les plus petites piles sont vidées en premier (libère des UP).
	Retourne la quantité réellement prélevée.
]]
function InventoryLogic.consume(inventory: Inventory, itemId: string, amount: number): number
	local stacks = {}
	for _, item in inventory.bag do
		if item.itemId == itemId then
			table.insert(stacks, item)
		end
	end
	table.sort(stacks, function(a, b)
		return (a.stack or 0) < (b.stack or 0)
	end)
	local remaining = math.max(0, math.floor(amount))
	for _, item in stacks do
		if remaining <= 0 then
			break
		end
		local taken = math.min(remaining, item.stack or 0)
		item.stack = (item.stack or 0) - taken
		remaining -= taken
		if (item.stack or 0) <= 0 then
			InventoryLogic.removeFromBag(inventory, item.uid)
		end
	end
	return math.floor(amount) - remaining
end

-- Tous les objets portés (pour le sac de dépouille), l'inventaire est vidé.
function InventoryLogic.drainAll(inventory: Inventory): { ItemInstance }
	local items = {}
	for _, slot in ItemCatalog.slotNames do
		local item = (inventory.equipped :: any)[slot] :: ItemInstance?
		if item then
			table.insert(items, item)
		end
	end
	for _, item in inventory.bag do
		table.insert(items, item)
	end
	inventory.equipped = {}
	inventory.bag = {}
	return items
end

return InventoryLogic
