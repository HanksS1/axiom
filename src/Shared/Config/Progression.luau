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
		maxDuration = 5 * 60, -- au-delà, le tutoriel se termine de lui-même (récompense comprise)
		rewardLevel = 2,
		-- Simulation privée : une zone par joueur, loin du Terminus.
		originX = 4000,
		originZ = 0,
		slotSpacing = 400,
		maxSlots = 24,
		-- Étapes
		moveRadius = 6,
		targets = 3,
		parryInterval = 2.6, -- secondes entre deux coups du robot d'entraînement
		parryWindUp = 0.8, -- œil rouge avant le coup
		parryDamage = 12,
		parryRange = 11,
		healTo = 55, -- PV après la décharge d'AXIOM (étape soin)
		minHealth = 40, -- personne ne meurt dans le tutoriel
		extractRadius = 8,
		extractDuration = 30,
		cinematicDuration = 7,
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
		-- Score de classement minimum pour être Légende (évite que tout le monde
		-- le soit tant que le jeu compte peu de joueurs).
		legendMinScore = 15000,
	},

	-- Classements (OrderedDataStore, avec repli en mémoire en Studio).
	leaderboards = {
		storeName = "AxiomBoards_v1",
		entries = 50, -- lignes envoyées au client
		cacheSeconds = 60, -- un même classement n'est relu qu'une fois par minute et par serveur
		friendsLimit = 40, -- amis consultés au maximum (budget GetAsync)
		friendScoreCacheSeconds = 300,
		nameCacheSeconds = 3600,
		legendRefreshSeconds = 600,
		-- Mur des Légendes (hub) : top 10 en hologrammes.
		wallSize = 10,
		wallRefreshSeconds = 600,
		wallScale = 0.55,
		wallChampionScale = 0.8,
	},
})
