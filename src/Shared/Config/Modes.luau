--!strict
--[[
	Modes de difficulté : accès par Score d'Équipement (4.2), taux de drop
	par état (7.2), multiplicateurs des robots (10.2) et du score (15.3).

	Temps de réaction allongés après les premiers tests (0,8 / 0,5 / 0,3 s
	dans le document) : c'est la fenêtre pendant laquelle le détecteur
	prévient le joueur qu'un robot l'a repéré.
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

export type ModeDef = {
	id: string,
	order: number,
	minScore: number, -- SE minimum
	maxScore: number?, -- SE maximum (nil = aucun)
	-- Probabilités (%) de chaque état, indexées par indice d'état. Somme = 100.
	conditionDropRates: { number },
	robots: {
		health: number,
		damage: number,
		accuracy: number, -- probabilité de toucher (0..1)
		reactionTime: number, -- secondes entre le repérage et la première attaque
		-- Robots qui peuvent attaquer la même cible en même temps (les autres
		-- approchent et attendent leur tour). Le Gardien n'est jamais limité.
		maxAttackers: number,
	},
	scoreMultiplier: number,
	-- Multiplicateur du budget de valeur des caisses (loot Faible / Moyen / Élevé).
	lootValueMultiplier: number,
	-- Le Module de calibration n'existe qu'en Difficile (7.3).
	calibrationAllowed: boolean,
}

local modes: { [string]: ModeDef } = {
	easy = {
		id = "easy",
		order = 1,
		minScore = 0,
		maxScore = 2000,
		conditionDropRates = { 50, 30, 15, 4.5, 0.5 },
		robots = { health = 0.7, damage = 0.6, accuracy = 0.40, reactionTime = 1.4, maxAttackers = 2 },
		scoreMultiplier = 1,
		lootValueMultiplier = 1,
		calibrationAllowed = false,
	},
	medium = {
		id = "medium",
		order = 2,
		minScore = 800,
		maxScore = 8000,
		conditionDropRates = { 25, 35, 25, 12, 3 },
		robots = { health = 1.0, damage = 1.0, accuracy = 0.60, reactionTime = 1.0, maxAttackers = 3 },
		scoreMultiplier = 1.5,
		lootValueMultiplier = 1.6,
		calibrationAllowed = false,
	},
	hard = {
		id = "hard",
		order = 3,
		minScore = 5000,
		maxScore = nil,
		conditionDropRates = { 5, 20, 35, 28, 12 },
		robots = { health = 1.4, damage = 1.3, accuracy = 0.80, reactionTime = 0.6, maxAttackers = 4 },
		scoreMultiplier = 2.5,
		lootValueMultiplier = 2.5,
		calibrationAllowed = true,
	},
}

return Freeze.deep({
	list = { "easy", "medium", "hard" },
	byId = modes,
	formats = { "solo", "duo" },
})
