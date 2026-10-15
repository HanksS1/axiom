--!strict
--[[
	SkinSort : classement des skins du Holo-Bazar (module pur, testé).

	Ordre : type d'objet (arme, sac, casque, gilet), puis objet ciblé (armes
	à distance avant la mêlée, dans l'ordre de progression : valeur de base
	croissante), puis rareté (commune → mythique, Config.Monetization.rarities),
	puis motif. Tout est déduit du catalogue généré (Config.Cosmetics) : un
	motif ou une cible ajoutés se rangent seuls, sans liste à tenir à jour.
]]

local Config = require(script.Parent.Parent.Config)

local SkinSort = {}

-- Ordre des types d'objet (catégories de Config.Cosmetics).
SkinSort.CATEGORY_ORDER = table.freeze({ "weapon", "backpack", "helmet", "vest" })

export type Mode = "type" | "rarity"

export type Group = {
	category: string,
	target: string, -- arme visée, ou le nom de l'emplacement (sac, casque, gilet)
	rarity: string?, -- mode « rareté » : un groupe par rareté
	ids: { string },
}

local function rarityIndex(rarity: string): number
	return table.find(Config.Monetization.rarities, rarity) or math.huge
end

local function categoryIndex(category: string): number
	return table.find(SkinSort.CATEGORY_ORDER, category) or math.huge
end

-- Rang d'un objet ciblé : armes à distance, puis mêlée, par valeur de base.
local function targetRank(category: string, target: string): (number, number)
	if category ~= "weapon" then
		return 0, 0
	end
	local ranged = Config.Weapons.ranged[target]
	if ranged then
		return 1, ranged.baseValue
	end
	local melee = Config.Weapons.melee[target]
	if melee then
		return 2, melee.baseValue
	end
	return 3, 0
end

-- `a` se range-t-il avant `b` ? (mode « type » par défaut, « rareté » d'abord sinon)
function SkinSort.before(a: string, b: string, mode: Mode?): boolean
	local da, db = Config.Cosmetics.byId[a], Config.Cosmetics.byId[b]
	if da == nil or db == nil then
		-- Identifiant inconnu (skin retiré du catalogue) : en dernier.
		if da ~= nil then
			return true
		elseif db ~= nil then
			return false
		end
		return a < b
	end
	local ra, rb = rarityIndex(da.rarity), rarityIndex(db.rarity)
	if mode == "rarity" and ra ~= rb then
		return ra < rb
	end
	local ca, cb = categoryIndex(da.category), categoryIndex(db.category)
	if ca ~= cb then
		return ca < cb
	end
	local fa, va = targetRank(da.category, da.target)
	local fb, vb = targetRank(db.category, db.target)
	if fa ~= fb then
		return fa < fb
	end
	if va ~= vb then
		return va < vb
	end
	if da.target ~= db.target then
		return da.target < db.target
	end
	if ra ~= rb then
		return ra < rb
	end
	return da.pattern < db.pattern
end

-- Copie triée d'une liste d'identifiants.
function SkinSort.sort(ids: { string }, mode: Mode?): { string }
	local sorted = table.clone(ids)
	table.sort(sorted, function(a, b)
		return SkinSort.before(a, b, mode)
	end)
	return sorted
end

--[[
	Triés puis regroupés pour l'affichage :
	- mode « type » : un groupe par objet ciblé (tous les skins d'un même
	  pistolet ensemble), dans l'ordre des types ;
	- mode « rarity » : un groupe par rareté.
]]
function SkinSort.groups(ids: { string }, mode: Mode?): { Group }
	local result: { Group } = {}
	local current: Group? = nil
	for _, id in SkinSort.sort(ids, mode) do
		local def = Config.Cosmetics.byId[id]
		if def then
			local same = current ~= nil
				and (
					if mode == "rarity"
						then current.rarity == def.rarity
						else current.category == def.category and current.target == def.target
				)
			if not same then
				local group: Group = {
					category = def.category,
					target = def.target,
					rarity = if mode == "rarity" then def.rarity else nil,
					ids = {},
				}
				table.insert(result, group)
				current = group
			end
			table.insert((current :: Group).ids, id)
		end
	end
	return result
end

return SkinSort
