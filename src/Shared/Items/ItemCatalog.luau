--!strict
--[[
	ItemCatalog : registre unique de tous les objets définis dans la config.

	Donne, pour un `itemId`, sa catégorie, son encombrement (UP), sa valeur
	de base, s'il a un état et s'il s'empile. Le reste du code ne lit jamais
	directement les tables de config par catégorie pour ces informations.
]]

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

export type ItemInfo = {
	id: string,
	category: Types.ItemCategory,
	up: number,
	-- Valeur de référence : objet à état → valeur à l'état « Bon état » ;
	-- objet empilable → valeur d'une pile pleine.
	baseValue: number,
	hasCondition: boolean,
	stackSize: number?, -- nil = non empilable
	def: any, -- définition brute (RangedDef, MeleeDef, …)
}

local catalog: { [string]: ItemInfo } = {}

local function register(info: ItemInfo)
	assert(catalog[info.id] == nil, `itemId en double : {info.id}`)
	catalog[info.id] = table.freeze(info)
end

for id, def in Config.Weapons.ranged do
	register({ id = id, category = "ranged", up = def.up, baseValue = def.baseValue, hasCondition = true, def = def })
end
for id, def in Config.Weapons.melee do
	register({ id = id, category = "melee", up = def.up, baseValue = def.baseValue, hasCondition = true, def = def })
end
for id, def in Config.Equipment.helmets do
	register({ id = id, category = "helmet", up = def.up, baseValue = def.baseValue, hasCondition = true, def = def })
end
for id, def in Config.Equipment.vests do
	register({ id = id, category = "vest", up = def.up, baseValue = def.baseValue, hasCondition = true, def = def })
end
for id, def in Config.Equipment.backpacks do
	register({ id = id, category = "backpack", up = def.up, baseValue = def.baseValue, hasCondition = true, def = def })
end
for id, def in Config.Equipment.gadgets do
	register({ id = id, category = "gadget", up = def.up, baseValue = def.baseValue, hasCondition = true, def = def })
end
for id, def in Config.Equipment.consumables do
	register({
		id = id,
		category = "consumable",
		up = def.up,
		baseValue = def.stackValue,
		hasCondition = false,
		stackSize = def.stackSize,
		def = def,
	})
end
for id, def in Config.Cells do
	register({
		id = id,
		category = "cell",
		up = def.up,
		baseValue = def.stackValue,
		hasCondition = false,
		stackSize = def.stackSize,
		def = def,
	})
end
for id, def in Config.Equipment.misc do
	register({
		id = id,
		category = "calibration",
		up = def.up,
		baseValue = def.baseValue,
		hasCondition = false,
		def = def,
	})
end

table.freeze(catalog)

local ItemCatalog = {}

function ItemCatalog.get(itemId: string): ItemInfo?
	return catalog[itemId]
end

function ItemCatalog.exists(itemId: string): boolean
	return catalog[itemId] ~= nil
end

function ItemCatalog.all(): { [string]: ItemInfo }
	return catalog
end

-- Catégories autorisées pour chaque emplacement équipé.
local slotCategories: { [Types.SlotName]: Types.ItemCategory } = {
	ranged = "ranged",
	melee = "melee",
	gadget1 = "gadget",
	gadget2 = "gadget",
	helmet = "helmet",
	vest = "vest",
	backpack = "backpack",
}
ItemCatalog.slotCategories = (table.freeze(slotCategories) :: any) :: { [Types.SlotName]: Types.ItemCategory }
ItemCatalog.slotNames = (
	table.freeze({ "ranged", "melee", "gadget1", "gadget2", "helmet", "vest", "backpack" }) :: any
) :: { Types.SlotName }

return ItemCatalog
