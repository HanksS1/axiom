--!strict
--[[
	WeaponStats : chiffres de la fiche de détail d'une arme (module PUR).

	Tout vient de Config.Weapons : rien n'est saisi deux fois. Chaque ligne a
	une valeur brute, un texte (clé + paramètres à traduire) et, pour les
	barres, une part de 0 à 1 par rapport à la meilleure arme de la même
	catégorie. L'état de l'objet (efficacité) s'applique aux dégâts.
]]

local Config = require(script.Parent.Parent.Config)

local WeaponStats = {}

export type Line = {
	key: string, -- libellé (weapon.stat.<key>)
	value: number?, -- valeur brute (nil : ligne de texte seule)
	text: string, -- clé de traduction de la valeur
	params: { [string]: any }?,
	ratio: number?, -- 0..1 : barre comparée aux autres armes de la catégorie
}

export type Sheet = {
	itemId: string,
	category: "ranged" | "melee",
	rarity: string,
	lines: { Line },
	traits: { string }, -- particularités (clés weapon.trait.<clé>)
}

local W = Config.Weapons

local function defOf(itemId: string): (any, string?)
	local ranged = W.ranged[itemId]
	if ranged then
		return ranged, "ranged"
	end
	local melee = W.melee[itemId]
	if melee then
		return melee, "melee"
	end
	return nil, nil
end

-- Rareté d'une arme d'après sa valeur de base (Config.Weapons.rarityByValue).
function WeaponStats.rarity(itemId: string): string?
	local def = defOf(itemId)
	if def == nil then
		return nil
	end
	local result = W.rarityByValue[1].rarity
	for _, step in W.rarityByValue do
		if def.baseValue >= step.minValue then
			result = step.rarity
		end
	end
	return result
end

-- Précision affichée (0 à 100) d'après la dispersion de base.
function WeaponStats.precision(spread: number): number
	return math.clamp(math.floor(100 * (1 - spread / W.precisionSpreadZero) + 0.5), 0, 100)
end

-- Dégâts par seconde d'une arme à distance (état Bon, sans tête ni bonus robot).
function WeaponStats.rangedDps(def: any): number
	if def.beamTick then
		return def.damage -- exprimé par seconde
	end
	return def.damage * def.pellets * def.burstCount * def.fireRate
end

-- Dégâts d'un tir (tous les projectiles) dans un état donné.
local function shotDamage(def: any, efficiency: number): number
	if def.beamTick then
		return def.damage * efficiency
	end
	return def.damage * def.pellets * efficiency
end

-- Maximum d'une valeur parmi les armes d'une catégorie (pour les barres).
local function maxOf(list: { [string]: any }, read: (def: any) -> number?): number
	local best = 0
	for _, def in list do
		local value = read(def)
		if value and value > best then
			best = value
		end
	end
	return math.max(best, 1e-6)
end

local function round(value: number, decimals: number): number
	local factor = 10 ^ decimals
	return math.floor(value * factor + 0.5) / factor
end

--[[
	Fiche d'une arme. `condition` : état (indice de Config.Conditions), 4 (Bon)
	par défaut. Retourne nil si l'objet n'est pas une arme.
]]
function WeaponStats.sheet(itemId: string, condition: number?): Sheet?
	local def, category = defOf(itemId)
	if def == nil or category == nil then
		return nil
	end
	local state = Config.Conditions.list[condition or 4] or Config.Conditions.list[4]
	local efficiency = state.efficiency
	local lines: { Line } = {}
	local traits: { string } = {}

	if category == "ranged" then
		local list = W.ranged
		local damage = shotDamage(def, efficiency)
		table.insert(lines, {
			key = "damage",
			value = damage,
			text = if def.beamTick
				then "weapon.value.perSecond"
				elseif def.pellets > 1 then "weapon.value.pellets"
				else "weapon.value.number",
			params = { value = round(damage, 1), pellets = def.pellets, each = round(def.damage * efficiency, 1) },
			ratio = damage / maxOf(list, function(d)
				return shotDamage(d, efficiency)
			end),
		})
		local dps = WeaponStats.rangedDps(def) * efficiency
		table.insert(lines, {
			key = "dps",
			value = dps,
			text = "weapon.value.number",
			params = { value = round(dps, 0) },
			ratio = dps / maxOf(list, function(d)
				return WeaponStats.rangedDps(d) * efficiency
			end),
		})
		table.insert(lines, {
			key = "fireRate",
			value = def.fireRate,
			text = if def.beamTick
				then "weapon.value.continuous"
				elseif def.burstCount > 1 then "weapon.value.burst"
				else "weapon.value.perSecondShots",
			params = { value = round(def.fireRate, 1), burst = def.burstCount },
			ratio = if def.beamTick
				then 1
				else def.fireRate / maxOf(list, function(d)
					return if d.beamTick then nil else d.fireRate
				end),
		})
		table.insert(lines, {
			key = "magazine",
			value = def.capacity,
			text = if def.capacity then "weapon.value.magazine" else "weapon.value.heat",
			params = { value = def.capacity or 0, reload = def.reloadTime or 0 },
			ratio = if def.capacity
				then def.capacity / maxOf(list, function(d)
					return d.capacity
				end)
				else nil,
		})
		local precision = WeaponStats.precision(def.spread)
		table.insert(lines, {
			key = "precision",
			value = precision,
			text = "weapon.value.percent",
			params = { value = precision },
			ratio = precision / 100,
		})
		table.insert(lines, {
			key = "range",
			value = def.effectiveRange,
			text = "weapon.value.studs",
			params = { value = def.effectiveRange },
			ratio = def.effectiveRange / maxOf(list, function(d)
				return d.effectiveRange
			end),
		})
		table.insert(lines, {
			key = "ammo",
			text = "item." .. def.cell,
		})
		if def.headshots then
			table.insert(traits, "headshots")
		end
		if def.scope then
			table.insert(traits, "scope")
		end
		if def.projectileSpeed then
			table.insert(traits, if def.arcGravity then "arc" else "projectile")
		end
		if def.splashRadius then
			table.insert(traits, "splash")
		end
		if def.lightCoverDamageMultiplier then
			table.insert(traits, "throughCover")
		end
		if def.slowOnHit then
			table.insert(traits, "slow")
		end
		if def.robotDamageMultiplier then
			table.insert(traits, "antiRobot")
		end
		if def.noiseRadius < 30 then
			table.insert(traits, "quiet")
		end
	else
		local list = W.melee
		local damage = def.damage * efficiency
		table.insert(lines, {
			key = "damage",
			value = damage,
			text = "weapon.value.number",
			params = { value = round(damage, 1) },
			ratio = damage / maxOf(list, function(d)
				return d.damage * efficiency
			end),
		})
		local dps = damage * def.attacksPerSecond
		table.insert(lines, {
			key = "dps",
			value = dps,
			text = "weapon.value.number",
			params = { value = round(dps, 0) },
			ratio = dps / maxOf(list, function(d)
				return d.damage * efficiency * d.attacksPerSecond
			end),
		})
		table.insert(lines, {
			key = "attackRate",
			value = def.attacksPerSecond,
			text = "weapon.value.perSecondHits",
			params = { value = round(def.attacksPerSecond, 1) },
			ratio = def.attacksPerSecond / maxOf(list, function(d)
				return d.attacksPerSecond
			end),
		})
		table.insert(lines, {
			key = "reach",
			value = def.range,
			text = "weapon.value.studs",
			params = { value = def.range },
			ratio = def.range / maxOf(list, function(d)
				return d.range
			end),
		})
		table.insert(traits, "parry")
		if def.breaksParry then
			table.insert(traits, "breaksParry")
		end
		if def.reflectsLasersWhenPristine then
			table.insert(traits, "reflects")
		end
		if def.knockback then
			table.insert(traits, "knockback")
		end
	end

	return {
		itemId = itemId,
		category = category,
		rarity = WeaponStats.rarity(itemId) :: string,
		lines = lines,
		traits = traits,
	}
end

return WeaponStats
