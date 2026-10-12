--!strict
--[[
	Stand de tir du Terminus (section 16.4) : essai des armes du coffre sur
	des cibles mobiles et défi chronométré quotidien (même arme et mêmes
	cibles pour tous).
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

return Freeze.deep({
	-- Distance maximale au comptoir pour rester au stand (studs).
	maxDistance = 22,
	-- Cellules prêtées pendant une séance (jamais conservées).
	reserveCells = 600,
	-- Cibles d'entraînement (partagées, dégâts affichés, jamais détruites).
	practice = {
		targets = 3,
		health = 100000,
		speedMin = 1.5,
		speedMax = 4,
	},
	-- Défi quotidien : remise à zéro à minuit UTC.
	challenge = {
		duration = 30,
		countdown = 3,
		-- État de l'arme imposée (indice dans Config.Conditions).
		condition = 4,
		-- Arme du jour, tirée de cette liste (même tirage pour tous).
		weapons = {
			"scrap_laser_pistol",
			"vigil_pistol",
			"crackler",
			"sentinel_rifle",
			"hullbreaker",
			"mag_nailer",
			"needle",
			"short_circuit",
		},
		-- Cibles qui surgissent : une touche les abat ; le score est la somme des dégâts.
		maxAlive = 3,
		targetLifetime = 2.6,
		respawnDelay = 0.3,
		speedMin = 0,
		speedMax = 5,
		sequenceLength = 90,
		-- Défis simultanés au maximum (les cibles d'un défi n'appartiennent qu'à son joueur).
		maxConcurrent = 2,
	},
})
