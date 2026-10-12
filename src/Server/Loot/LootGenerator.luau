--!strict
--[[
	LootGenerator : contenu des caisses et loot des robots (sections 7.2, 9, 10.5).

	Fonctions pures : le générateur aléatoire (`rng`, compatible `Random`)
	et la fabrique d'objets (`create`) sont injectés, pour des tests
	déterministes.

	Caisses : budget de valeur (voir Config/Loot) — équipement éventuel,
	puis cellules, puis consommables jusqu'à atteindre le budget.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local ItemRules = require(Shared.Items.ItemRules)
local Pricing = require(Shared.Economy.Pricing)

type ItemInstance = Types.ItemInstance

export type Rng = {
	NextNumber: (self: any, min: number?, max: number?) -> number,
	NextInteger: (self: any, min: number, max: number) -> number,
}

export type CreateOptions = { condition: number?, stack: number? }
export type Create = (itemId: string, options: any?) -> ItemInstance

local LootGenerator = {}

local kitCost: number? = nil

-- Coût de référence du kit de base (calculé une fois depuis la config).
function LootGenerator.kitCost(): number
	if kitCost == nil then
		kitCost = Pricing.baseKitPurchaseCost()
	end
	return kitCost :: number
end

-- État tiré dans la table du mode, décalé de `shift` (élites), borné à Neuf.
function LootGenerator.rollCondition(modeId: string, rng: Rng, shift: number?, minimum: number?): number
	local rates = Config.Modes.byId[modeId].conditionDropRates
	local roll = rng:NextNumber(0, 100)
	local condition = #rates
	local cumulative = 0
	for index, rate in rates do
		cumulative += rate
		if roll < cumulative then
			condition = index
			break
		end
	end
	condition = math.min(Config.Conditions.MAX, condition + (shift or 0))
	return math.max(condition, minimum or Config.Conditions.MIN)
end

-- Tirage pondéré dans une famille (« equipment », « consumable », « cells »).
function LootGenerator.pick(poolName: string, rng: Rng): string
	local pool = Config.Loot.pools[poolName]
	assert(pool ~= nil, `famille de loot inconnue : {poolName}`)
	-- Ordre trié : tirage reproductible à graine égale.
	local ids = {}
	local total = 0
	for id, weight in pool do
		table.insert(ids, id)
		total += weight
	end
	table.sort(ids)
	local roll = rng:NextNumber(0, total)
	for _, id in ids do
		roll -= pool[id]
		if roll < 0 then
			return id
		end
	end
	return ids[#ids]
end

local function cellStack(rng: Rng, create: Create, cellId: string?, quantity: number?): ItemInstance
	local id = cellId or LootGenerator.pick("cells", rng)
	local range = Config.Loot.cellQuantity
	return create(id, { stack = quantity or rng:NextInteger(range.min, range.max) })
end

local function consumableStack(rng: Rng, create: Create, consumableId: string?, maxQuantity: number?): ItemInstance
	local id = consumableId or LootGenerator.pick("consumable", rng)
	local info = ItemCatalog.get(id) :: ItemCatalog.ItemInfo
	local limit = math.clamp(maxQuantity or (info.stackSize :: number), 1, info.stackSize :: number)
	return create(id, { stack = rng:NextInteger(1, limit) })
end

-- Budget de valeur d'une caisse (crédits).
function LootGenerator.crateBudget(crateId: string, modeId: string, rng: Rng): number
	local def = Config.Loot.crates[crateId]
	local mode = Config.Modes.byId[modeId]
	local swing = rng:NextNumber(1 - def.variance, 1 + def.variance)
	return LootGenerator.kitCost() * def.kitShare * mode.lootValueMultiplier * swing
end

function LootGenerator.crate(crateId: string, modeId: string, rng: Rng, create: Create): { ItemInstance }
	local def = Config.Loot.crates[crateId]
	assert(def ~= nil, `caisse inconnue : {crateId}`)
	local mode = Config.Modes.byId[modeId]
	assert(mode ~= nil, `mode inconnu : {modeId}`)

	local budget = LootGenerator.crateBudget(crateId, modeId, rng)
	local items: { ItemInstance } = {}
	local spent = 0
	local function add(item: ItemInstance)
		table.insert(items, item)
		spent += ItemRules.value(item)
	end

	-- 1. Équipement.
	if rng:NextNumber() < def.equipmentChance then
		local count = rng:NextInteger(def.equipment.min, def.equipment.max)
		for index = 1, count do
			local minimum = if index == 1 then def.minCondition else nil
			local itemId = LootGenerator.pick("equipment", rng)
			add(create(itemId, { condition = LootGenerator.rollCondition(modeId, rng, 0, minimum) }))
		end
	end
	-- Module de calibration : mode Difficile uniquement.
	if def.calibrationChanceHard and mode.calibrationAllowed and rng:NextNumber() < def.calibrationChanceHard then
		add(create("calibration_module"))
	end

	-- 2. Cellules.
	for _ = 1, rng:NextInteger(def.cellStacks.min, def.cellStacks.max) do
		if #items < def.maxItems then
			add(cellStack(rng, create))
		end
	end

	-- 3. Consommables jusqu'au budget.
	while budget - spent > Config.Loot.fillThreshold and #items < def.maxItems do
		local before = spent
		-- Quantité maximale cohérente avec le budget restant (au moins 1).
		local consumableId = LootGenerator.pick("consumable", rng)
		local info = ItemCatalog.get(consumableId) :: ItemCatalog.ItemInfo
		local unitValue = info.baseValue / (info.stackSize :: number)
		local maxQuantity = math.max(1, math.ceil((budget - spent) / unitValue))
		add(consumableStack(rng, create, consumableId, maxQuantity))
		if spent == before then
			break -- sécurité : aucune progression
		end
	end
	return items
end

--[[
	Loot d'un robot détruit (section 10.5). Élites : objets garantis avec un
	état décalé d'un cran vers le haut.
]]
function LootGenerator.robot(robotId: string, modeId: string, rng: Rng, create: Create): { ItemInstance }
	local def = Config.Robots.byId[robotId]
	assert(def ~= nil, `robot inconnu : {robotId}`)
	local mode = Config.Modes.byId[modeId]
	local items: { ItemInstance } = {}

	for _, entry in def.loot do
		if entry.hardModeOnly and not mode.calibrationAllowed then
			continue
		end
		if rng:NextNumber() >= entry.chance then
			continue
		end
		if entry.itemId then
			local info = ItemCatalog.get(entry.itemId) :: ItemCatalog.ItemInfo
			if info.hasCondition then
				table.insert(
					items,
					create(entry.itemId, {
						condition = LootGenerator.rollCondition(modeId, rng, def.conditionShift),
					})
				)
			elseif info.category == "cell" then
				table.insert(items, cellStack(rng, create, entry.itemId, entry.quantity))
			else
				table.insert(items, create(entry.itemId))
			end
		elseif entry.pool == "cells" then
			table.insert(items, cellStack(rng, create, nil, entry.quantity))
		elseif entry.pool == "consumable" then
			table.insert(items, consumableStack(rng, create))
		end
	end

	if def.guaranteedItems then
		for _ = 1, rng:NextInteger(def.guaranteedItems.min, def.guaranteedItems.max) do
			table.insert(
				items,
				create(LootGenerator.pick("equipment", rng), {
					condition = LootGenerator.rollCondition(modeId, rng, def.conditionShift),
				})
			)
		end
	end
	return items
end

return LootGenerator
