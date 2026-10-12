--!strict
--[[
	Progression : XP et niveaux (15.1), tutoriel (15.2), score (15.3) et
	classement saisonnier (15.4).
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

return Freeze.deep({
	xp = {
		scoreShare = 0.5, -- 50 % du score de la partie
		participation = 100,
		-- XP pour passer de n à n+1 = base + perLevel × n
		levelBase = 500,
		levelPerLevel = 150,
		maxLevel = 999,
	},

	tutorial = {
		maxDuration = 5 * 60,
		rewardLevel = 2,
	},

	minLevelToPlay = 2,

	score = {
		playerKill = 100,
		botKill = 50,
		lootValueDivisor = 10,
		deathPenaltyMultiplier = 0.5,
	},

	season = {
		lengthWeeks = 8,
		-- Date de début de la saison 1 (UTC). Les saisons suivantes s'enchaînent.
		firstSeasonStartUnix = 1798761600, -- 2027-01-01 00:00 UTC (à ajuster)
		topGames = 10,
		ranks = {
			{ id = "scrap", minScore = 0 },
			{ id = "copper", minScore = 2000 },
			{ id = "steel", minScore = 6000 },
			{ id = "titanium", minScore = 15000 },
			{ id = "plasma", minScore = 30000 },
		},
		-- « Légende d'AXIOM » : top 500 mondial (calculé via le classement).
		legendTopCount = 500,
	},
})
