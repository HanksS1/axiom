--!strict
--[[
	MercenaryGear : équipement d'un mercenaire IA (section 11), dans la plage
	de SE du mode.

	On tire un équipement (armes à chargeur, armure, sac, cellules, soins),
	puis on l'ajuste tant que le SE est hors plage : états montés ou
	descendus d'un cran, puis, si cela ne suffit pas pour atteindre le
	minimum, armure ajoutée et arme remplacée par la plus précieuse du mode.

	Module pur (générateur aléatoire et fabrique d'objets injectés) : testé.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local ItemRules = require(Shared.Items.ItemRules)
local Types = require(Shared.Types)

local LootGenerator = require(script.Parent.Parent.Loot.LootGenerator)

type ItemInstance = Types.ItemInstance

local Merc = Config.Mercenaries
local Conditions = Config.Conditions

local MercenaryGear = {}

-- Plage de SE visée pour un mode (Difficile : minimum × 2 au plus).
function MercenaryGear.range(modeId: string): (number, number)
	local mode = Config.Modes.byId[modeId]
	local minScore = mode.minScore
	local maxScore = mode.maxScore or math.max(minScore, 1) * Merc.hardCeilingMultiplier
	return minScore, maxScore
end

local function weaponsFor(modeId: string): { string }
	return (Merc.weapons :: any)[modeId] or Merc.weapons.easy
end

-- Objets dont l'état peut monter / descendre.
local function conditionItems(loadout: Types.Loadout): { ItemInstance }
	local list = {}
	for _, slot in ItemCatalog.slotNames do
		local item = (loadout :: any)[slot] :: ItemInstance?
		if item and item.condition then
			table.insert(list, item)
		end
	end
	return list
end

local function mostValuable(ids: { string }): string
	local best, bestValue = ids[1], -1
	for _, id in ids do
		local info = ItemCatalog.get(id)
		if info and info.baseValue > bestValue then
			best, bestValue = id, info.baseValue
		end
	end
	return best
end

function MercenaryGear.build(
	modeId: string,
	rng: LootGenerator.Rng,
	create: LootGenerator.Create
): (Types.Loadout, { ItemInstance })
	local minScore, maxScore = MercenaryGear.range(modeId)
	local function pick(list: { string }): string
		return list[rng:NextInteger(1, #list)]
	end
	local function condition(): number
		return LootGenerator.rollCondition(modeId, rng)
	end
	local weapons = weaponsFor(modeId)
	local loadout: Types.Loadout = {
		ranged = create(pick(weapons), { condition = condition() }),
		melee = create(pick(Merc.melee), { condition = condition() }),
		backpack = create(pick(Merc.backpacks), { condition = condition() }),
	}
	if rng:NextNumber() < Merc.armorChance.helmet then
		loadout.helmet = create("helmet", { condition = condition() })
	end
	if rng:NextNumber() < Merc.armorChance.vest then
		loadout.vest = create("vest", { condition = condition() })
	end
	local bag: { ItemInstance } = {}
	local function addCells()
		local def = Config.Weapons.ranged[(loadout.ranged :: ItemInstance).itemId]
		local info = ItemCatalog.get(def.cell)
		for index = #bag, 1, -1 do
			local other = ItemCatalog.get(bag[index].itemId)
			if other and other.category == "cell" then
				table.remove(bag, index)
			end
		end
		for _ = 1, rng:NextInteger(Merc.cellStacks.min, Merc.cellStacks.max) do
			table.insert(bag, create(def.cell, { stack = if info and info.stackSize then info.stackSize else 10 }))
		end
	end
	addCells()
	for _ = 1, rng:NextInteger(Merc.consumableCount.min, Merc.consumableCount.max) do
		table.insert(bag, create(pick(Merc.consumables), { stack = 1 }))
	end

	local upgraded = false
	for _ = 1, Merc.gearAttempts do
		local score = ItemRules.equipmentScore(loadout, bag)
		if score >= minScore and score <= maxScore then
			break
		end
		local raise = score < minScore
		local candidates = {}
		for _, item in conditionItems(loadout) do
			local value = item.condition :: number
			if (raise and value < Conditions.PRISTINE) or (not raise and value > Conditions.WRECKED) then
				table.insert(candidates, item)
			end
		end
		if #candidates > 0 then
			local item = candidates[rng:NextInteger(1, #candidates)]
			item.condition = (item.condition :: number) + (if raise then 1 else -1)
		elseif raise and not upgraded then
			-- Tout est déjà Neuf : armure complète et meilleure arme du mode.
			upgraded = true
			local ranged = loadout.ranged :: ItemInstance
			loadout.ranged = create(mostValuable(weapons), { condition = ranged.condition })
			loadout.helmet = loadout.helmet or create("helmet", { condition = Conditions.PRISTINE })
			loadout.vest = loadout.vest or create("vest", { condition = Conditions.PRISTINE })
			addCells()
		else
			break
		end
	end
	return loadout, bag
end

return MercenaryGear
