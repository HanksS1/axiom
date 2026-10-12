--!strict
--[[
	Niveau de compte (section 15.1).
	XP pour passer du niveau n au niveau n+1 = 500 + 150 × n.
]]

local Config = require(script.Parent.Parent.Config)

local XP = Config.Progression.xp

local Leveling = {}

function Leveling.xpToNext(level: number): number
	return XP.levelBase + XP.levelPerLevel * level
end

-- XP de fin de partie : 50 % du score + 100 de participation.
function Leveling.matchXp(score: number): number
	return math.floor(math.max(0, score) * XP.scoreShare) + XP.participation
end

--[[
	Ajoute de l'XP et retourne (niveau, xp restante dans le niveau, niveaux gagnés).
	`xp` est l'XP accumulée dans le niveau courant.
]]
function Leveling.addXp(level: number, xp: number, amount: number): (number, number, number)
	local gained = 0
	local total = xp + math.max(0, math.floor(amount))
	while level < XP.maxLevel and total >= Leveling.xpToNext(level) do
		total -= Leveling.xpToNext(level)
		level += 1
		gained += 1
	end
	if level >= XP.maxLevel then
		total = 0
	end
	return level, total, gained
end

return Leveling
