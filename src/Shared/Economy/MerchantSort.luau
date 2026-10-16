--!strict
--[[
	MerchantSort : sections du Marchand (module pur, testé ; même principe que
	Monetization/SkinSort pour le Holo-Bazar).

	Sections, dans l'ordre : Armes (à distance, puis mêlée), Gadgets,
	Protections (casques, puis gilets), Sacs à dos, Consommables, Munitions.
	Dans une catégorie : ordre de progression (valeur de base croissante,
	celle du catalogue), puis identifiant. Tout est déduit de la catégorie de
	l'objet (ItemCatalog) : un objet ajouté au catalogue se range seul ; une
	catégorie inconnue part dans une section « Autres », en dernier.

	Sert à l'achat (identifiants d'objets) et à la revente (objets possédés,
	même découpage : avec un coffre plein, s'y retrouver compte autant).
]]

local ItemCatalog = require(script.Parent.Parent.Items.ItemCatalog)
local Types = require(script.Parent.Parent.Types)

type ItemInstance = Types.ItemInstance

export type Section = { key: string, categories: { string } }

export type Group<T> = {
	section: string, -- merchant.section.<clé>
	category: string, -- catégorie d'objet (sous-en-tête si la section en a plusieurs)
	entries: { T },
}

local MerchantSort = {}

MerchantSort.SECTIONS = table.freeze({
	table.freeze({ key = "weapons", categories = table.freeze({ "ranged", "melee" }) }),
	table.freeze({ key = "gadgets", categories = table.freeze({ "gadget" }) }),
	table.freeze({ key = "protection", categories = table.freeze({ "helmet", "vest" }) }),
	table.freeze({ key = "backpacks", categories = table.freeze({ "backpack" }) }),
	table.freeze({ key = "consumables", categories = table.freeze({ "consumable" }) }),
	table.freeze({ key = "ammo", categories = table.freeze({ "cell" }) }),
}) :: { Section }

MerchantSort.OTHER = "other"

-- Section d'une catégorie : (clé, rang de la section, rang de la catégorie dans la section).
function MerchantSort.sectionOf(category: string): (string, number, number)
	for sectionIndex, section in MerchantSort.SECTIONS do
		local categoryIndex = table.find(section.categories, category)
		if categoryIndex then
			return section.key, sectionIndex, categoryIndex
		end
	end
	return MerchantSort.OTHER, #MerchantSort.SECTIONS + 1, 1
end

-- Une section a-t-elle plusieurs catégories (et donc des sous-en-têtes) ?
function MerchantSort.hasSubgroups(sectionKey: string): boolean
	for _, section in MerchantSort.SECTIONS do
		if section.key == sectionKey then
			return #section.categories > 1
		end
	end
	return false
end

type Key = { section: number, category: number, categoryName: string, value: number, id: string, extra: number }

local function keyOf(itemId: string, extra: number): Key
	local info = ItemCatalog.get(itemId)
	local category = if info then info.category else "?"
	local _, section, categoryIndex = MerchantSort.sectionOf(category)
	return {
		section = section,
		category = categoryIndex,
		categoryName = category,
		value = if info then info.baseValue else 0,
		id = itemId,
		extra = extra,
	}
end

local function before(a: Key, b: Key): boolean
	if a.section ~= b.section then
		return a.section < b.section
	end
	if a.category ~= b.category then
		return a.category < b.category
	end
	if a.categoryName ~= b.categoryName then
		return a.categoryName < b.categoryName -- section « Autres » : catégories inconnues
	end
	if a.value ~= b.value then
		return a.value < b.value
	end
	if a.id ~= b.id then
		return a.id < b.id
	end
	return a.extra < b.extra
end

-- Trie et regroupe `entries` ; `keyFor` donne l'objet et un départage stable.
local function group<T>(entries: { T }, keyFor: (entry: T) -> Key): { Group<T> }
	local keyed: { { key: Key, entry: T } } = {}
	for _, entry in entries do
		table.insert(keyed, { key = keyFor(entry), entry = entry })
	end
	table.sort(keyed, function(a, b)
		return before(a.key, b.key)
	end)
	local result: { Group<T> } = {}
	local current: Group<T>? = nil
	for _, pair in keyed do
		local category = pair.key.categoryName
		local section = MerchantSort.sectionOf(category)
		if current == nil or current.category ~= category then
			local created: Group<T> = { section = section, category = category, entries = {} }
			table.insert(result, created)
			current = created
		end
		table.insert((current :: Group<T>).entries, pair.entry)
	end
	return result
end

-- Achat : identifiants d'objets du catalogue, en sections.
function MerchantSort.groupIds(ids: { string }): { Group<string> }
	return group(ids, function(id: string): Key
		return keyOf(id, 0)
	end)
end

-- Revente : objets possédés ; à objet égal, le meilleur état d'abord.
function MerchantSort.groupItems(items: { ItemInstance }): { Group<ItemInstance> }
	return group(items, function(item: ItemInstance): Key
		return keyOf(item.itemId, -(item.condition or 0))
	end)
end

return MerchantSort
