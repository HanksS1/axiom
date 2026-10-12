--!strict
--[[
	Pricing : prix du Marchand, revente, réparation et assurance
	(sections 7.3, 14.2, 14.3). Fonctions PURES partagées.
]]

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local ItemCatalog = require(script.Parent.Parent.Items.ItemCatalog)
local ItemRules = require(script.Parent.Parent.Items.ItemRules)

local Merchant = Config.Economy.merchant

local Pricing = {}

local function round(x: number): number
	return math.floor(x + 0.5)
end

--[[
	Prix d'achat chez le Marchand.
	- Équipement : seulement aux états vendus (Dégradé, Bon état), à ×2 la valeur.
	- Consommables : valeur × 1,5 (au prorata de la quantité).
	- Cellules : prix fixe par pile (au prorata).
	Retourne nil si l'objet n'est pas vendu dans cet état.
]]
function Pricing.merchantPrice(itemId: string, condition: number?, quantity: number?): number?
	local info = ItemCatalog.get(itemId)
	if info == nil then
		return nil
	end
	if info.hasCondition then
		if condition == nil or table.find(Merchant.sellsConditions, condition) == nil then
			return nil
		end
		return round(ItemRules.valueAt(itemId, condition) * Merchant.equipmentPriceMultiplier)
	end
	local stackSize = info.stackSize or 1
	local amount = math.clamp(quantity or stackSize, 1, stackSize)
	if info.category == "cell" then
		return round(info.def.merchantStackPrice * amount / stackSize)
	elseif info.category == "consumable" then
		return round(info.baseValue * Merchant.consumablePriceMultiplier * amount / stackSize)
	end
	return nil -- Module de calibration : jamais vendu (loot uniquement)
end

-- Prix de revente d'un objet (0 si non vendable).
function Pricing.sellPrice(item: Types.ItemInstance): number
	if not ItemRules.isSellable(item) then
		return 0
	end
	return round(ItemRules.value(item) * Merchant.resaleMultiplier)
end

--[[
	Coût pour racheter l'équivalent du kit de base au Marchand, au prix le
	plus bas (état le moins cher vendu). Sert de référence au budget des caisses.
]]
function Pricing.baseKitPurchaseCost(): number
	local kit = Config.Economy.baseKit
	local cheapest = math.huge
	for _, condition in Merchant.sellsConditions do
		cheapest = math.min(cheapest, condition)
	end
	local total = 0
	for _, entry in { kit.ranged, kit.melee, kit.backpack } do
		total += Pricing.merchantPrice(entry.itemId, cheapest) or 0
	end
	for _, entry in kit.bag do
		total += Pricing.merchantPrice(entry.itemId, nil, entry.stack) or 0
	end
	return total
end

--[[
	Réparation (Armurier) : un état à la fois.
	Coût = 1,5 × (valeur au nouvel état − valeur à l'état actuel).
	Retourne (coût, Module de calibration requis) ou nil si impossible.
]]
function Pricing.repairCost(item: Types.ItemInstance): (number?, boolean)
	local info = ItemCatalog.get(item.itemId)
	if info == nil or not info.hasCondition or item.isKit or item.tempGamesLeft ~= nil then
		return nil, false
	end
	local condition = item.condition :: number
	if condition >= Config.Conditions.MAX then
		return nil, false
	end
	local repair = Config.Economy.repair
	local delta = ItemRules.valueAt(item.itemId, condition + 1) - ItemRules.valueAt(item.itemId, condition)
	return round(repair.costMultiplier * delta), condition + 1 >= repair.calibrationRequiredForCondition
end

-- Coût de l'assurance pour un SE donné (section 14.3).
function Pricing.insuranceCost(tier: string, equipmentScore: number): number?
	local def = Config.Economy.insurance.tiers[tier]
	if def == nil then
		return nil
	end
	return round(equipmentScore * def.costShare)
end

return Pricing
