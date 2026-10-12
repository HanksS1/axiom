--!strict
--[[
	RangeRules : règles PURES du défi quotidien du stand de tir (16.4).

	Tout dépend uniquement du numéro du jour (UTC) : arme imposée et suite
	des cibles sont identiques sur tous les serveurs, pour l'équité.
	Les positions sont relatives (0..1) à la zone de cibles du stand.
]]

local Config = require(script.Parent.Parent.Config)

local Challenge = Config.Range.challenge

local RangeRules = {}

local DAY = 24 * 60 * 60

export type TargetSpec = {
	-- Position de départ et d'arrivée (0..1 sur la largeur), hauteur (0..1) et profondeur (0..1).
	from: number,
	to: number,
	height: number,
	depth: number,
	speed: number, -- studs/s (0 = immobile)
}

function RangeRules.day(unix: number): number
	return math.floor(unix / DAY)
end

function RangeRules.nextResetAt(unix: number): number
	return (RangeRules.day(unix) + 1) * DAY
end

-- Générateur déterministe (Park-Miller), nombres dans [0, 1).
local function generator(seed: number): () -> number
	local state = (math.floor(seed) % 2147483646) + 1
	return function(): number
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
end

function RangeRules.weaponOfDay(day: number): string
	local pool = Challenge.weapons
	local next = generator(day * 7919 + 17)
	next()
	return pool[math.floor(next() * #pool) + 1]
end

function RangeRules.targets(day: number): { TargetSpec }
	local next = generator(day * 104729 + 3)
	local specs: { TargetSpec } = {}
	for _ = 1, Challenge.sequenceLength do
		local from = next()
		table.insert(specs, {
			from = from,
			to = next(),
			height = next(),
			depth = next(),
			speed = Challenge.speedMin + next() * (Challenge.speedMax - Challenge.speedMin),
		})
	end
	return specs
end

-- Points d'une touche (dégâts arrondis, toujours au moins 1).
function RangeRules.points(damage: number): number
	return math.max(1, math.floor(damage + 0.5))
end

return RangeRules
