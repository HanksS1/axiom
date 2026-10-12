--!strict
--[[
	Modes de difficulté : accès par Score d'Équipement (4.2), taux de drop
	par état (7.2), multiplicateurs des robots (10.2) et du score (15.3).
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
		reactionTime: number, -- secondes
	},
	scoreMultiplier: number,
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
		robots = { health = 0.7, damage = 0.6, accuracy = 0.40, reactionTime = 0.8 },
		scoreMultiplier = 1,
		calibrationAllowed = false,
	},
	medium = {
		id = "medium",
		order = 2,
		minScore = 800,
		maxScore = 8000,
		conditionDropRates = { 25, 35, 25, 12, 3 },
		robots = { health = 1.0, damage = 1.0, accuracy = 0.60, reactionTime = 0.5 },
		scoreMultiplier = 1.5,
		calibrationAllowed = false,
	},
	hard = {
		id = "hard",
		order = 3,
		minScore = 5000,
		maxScore = nil,
		conditionDropRates = { 5, 20, 35, 28, 12 },
		robots = { health = 1.4, damage = 1.3, accuracy = 0.80, reactionTime = 0.3 },
		scoreMultiplier = 2.5,
		calibrationAllowed = true,
	},
}

return Freeze.deep({
	list = { "easy", "medium", "hard" },
	byId = modes,
	formats = { "solo", "duo" },
})
