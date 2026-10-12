--!strict
--[[
	ItemRules : règles pures (sans effet de bord) sur les objets.

	Valeur, encombrement, Score d'Équipement, capacité du sac et du coffre,
	validation structurelle d'une instance d'objet. Utilisé à l'identique
	par le serveur (qui fait autorité) et par le client (affichage).
]]

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local ItemCatalog = require(script.Parent.ItemCatalog)

type ItemInstance = Types.ItemInstance

local Conditions = Config.Conditions

local ItemRules = {}

local function round(x: number): number
	return math.floor(x + 0.5)
end

function ItemRules.isValidCondition(condition: any): boolean
	return type(condition) == "number"
		and condition % 1 == 0
		and condition >= Conditions.MIN
		and condition <= Conditions.MAX
end

function ItemRules.efficiency(condition: number): number
	return Conditions.list[condition].efficiency
end

function ItemRules.valueMultiplier(condition: number): number
	return Conditions.list[condition].valueMultiplier
end

--[[
	Valide la structure d'une instance (données issues d'un profil, d'une
	migration ou générées par le serveur). Retourne false + raison.
]]
function ItemRules.validate(item: any): (boolean, string?)
	if type(item) ~= "table" then
		return false, "pas une table"
	end
	if type(item.uid) ~= "string" or #item.uid == 0 or #item.uid > 64 then
		return false, "uid invalide"
	end
	local info = type(item.itemId) == "string" and ItemCatalog.get(item.itemId) or nil
	if info == nil then
		return false, `itemId inconnu : {tostring(item.itemId)}`
	end
	if info.hasCondition then
		if not ItemRules.isValidCondition(item.condition) then
			return false, "état invalide"
		end
	elseif item.condition ~= nil then
		return false, "état sur un objet sans état"
	end
	if info.stackSize ~= nil then
		local stack = item.stack
		if type(stack) ~= "number" or stack % 1 ~= 0 or stack < 1 or stack > info.stackSize then
			return false, "pile invalide"
		end
	elseif item.stack ~= nil then
		return false, "pile sur un objet non empilable"
	end
	if item.isKit ~= nil and type(item.isKit) ~= "boolean" then
		return false, "isKit invalide"
	end
	if item.tempGamesLeft ~= nil then
		local left = item.tempGamesLeft
		if type(left) ~= "number" or left % 1 ~= 0 or left < 0 then
			return false, "tempGamesLeft invalide"
		end
	end
	return true
end

--[[
	Valeur actuelle d'un objet (revente et SE).
	- Kit de base et objets temporaires : 0 (non vendables).
	- Objet à état : valeur de base × multiplicateur d'état.
	- Pile : valeur d'une pile pleine × (quantité / taille de pile).
]]
function ItemRules.value(item: ItemInstance): number
	if item.isKit or item.tempGamesLeft ~= nil then
		return 0
	end
	local info = ItemCatalog.get(item.itemId)
	if info == nil then
		return 0
	end
	if info.hasCondition then
		return ItemRules.valueAt(item.itemId, item.condition :: number)
	end
	if info.stackSize ~= nil then
		return round(info.baseValue * (item.stack or 0) / info.stackSize)
	end
	return info.baseValue
end

-- Valeur d'un objet à état donné (utile pour l'armurier et le marchand).
function ItemRules.valueAt(itemId: string, condition: number): number
	local info = ItemCatalog.get(itemId)
	if info == nil or not ItemRules.isValidCondition(condition) then
		return 0
	end
	return round(info.baseValue * ItemRules.valueMultiplier(condition))
end

function ItemRules.isSellable(item: ItemInstance): boolean
	return not item.isKit and item.tempGamesLeft == nil and ItemCatalog.exists(item.itemId)
end

-- Encombrement d'un objet rangé (une pile, même partielle, compte en entier).
function ItemRules.up(item: ItemInstance): number
	local info = ItemCatalog.get(item.itemId)
	return if info then info.up else 0
end

function ItemRules.totalUp(items: { ItemInstance }): number
	local total = 0
	for _, item in items do
		total += ItemRules.up(item)
	end
	return total
end

-- Capacité du sac porté (ou des poches sans sac), bonus éventuels inclus.
function ItemRules.bagCapacity(backpack: ItemInstance?, bonusUp: number?): number
	local base = Config.Equipment.pocketsUp
	if backpack ~= nil then
		local info = ItemCatalog.get(backpack.itemId)
		if info and info.category == "backpack" and ItemRules.isValidCondition(backpack.condition) then
			base = info.def.capacityByCondition[backpack.condition :: number]
		end
	end
	return base + (bonusUp or 0)
end

function ItemRules.vaultCapacity(hasExtension: boolean): number
	local vault = Config.Economy.vault
	return vault.baseCapacity + (if hasExtension then vault.extensionBonus else 0)
end

--[[
	Score d'Équipement (section 4.2) : somme des valeurs actuelles de tous
	les objets portés au départ (emplacements équipés + contenu du sac).
]]
function ItemRules.equipmentScore(loadout: Types.Loadout, bag: { ItemInstance }): number
	local total = 0
	for _, slot in ItemCatalog.slotNames do
		local item = (loadout :: any)[slot] :: ItemInstance?
		if item ~= nil then
			total += ItemRules.value(item)
		end
	end
	for _, item in bag do
		total += ItemRules.value(item)
	end
	return total
end

-- Bouclier maximal apporté par un gilet (0 sans gilet).
function ItemRules.maxShield(vest: ItemInstance?): number
	if vest == nil then
		return 0
	end
	local info = ItemCatalog.get(vest.itemId)
	if info == nil or info.category ~= "vest" or not ItemRules.isValidCondition(vest.condition) then
		return 0
	end
	return info.def.shieldByCondition[vest.condition :: number]
end

-- Multiplicateur de dégâts à la tête selon le casque porté.
function ItemRules.headMultiplier(helmet: ItemInstance?): number
	if helmet == nil then
		return Config.Equipment.noHelmetHeadMultiplier
	end
	local info = ItemCatalog.get(helmet.itemId)
	if info == nil or info.category ~= "helmet" or not ItemRules.isValidCondition(helmet.condition) then
		return Config.Equipment.noHelmetHeadMultiplier
	end
	return info.def.headMultiplierByCondition[helmet.condition :: number]
end

-- Modes accessibles pour un SE donné (section 4.2).
function ItemRules.modeAccess(score: number, modeId: string): (boolean, string?)
	local mode = Config.Modes.byId[modeId]
	if mode == nil then
		return false, "unknown_mode"
	end
	if score < mode.minScore then
		return false, "score_too_low"
	end
	if mode.maxScore ~= nil and score > mode.maxScore then
		return false, "score_too_high"
	end
	return true
end

return ItemRules
