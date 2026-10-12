--!strict
--[[
	Règles de combat (sections 5.2, 6.1 à 6.11).
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

return Freeze.deep({
	maxHealth = 100,

	movement = {
		walkSpeed = 14,
		sprintSpeed = 22,
		crouchSpeed = 8,
		proneSpeed = 4,
		jumpHeight = 7,
		sprintToFireDelay = 0.15,
		proneTransition = 0.4,
		crouchAccuracyBonus = 0.15, -- réduit la dispersion de 15 %
		proneAccuracyBonus = 0.30,
		-- Pas de dispersion supplémentaire en visée (« ADS ») précisée par le
		-- document : valeur de départ, à ajuster pendant les tests.
		aimAccuracyBonus = 0.5,
		-- Appui long sur la touche accroupi/couché (secondes).
		proneHoldThreshold = 0.35,
	},

	-- Au-delà de la portée efficace : dégâts dégressifs.
	-- QUESTION OUVERTE : le document ne précise pas ce qui se passe au-delà
	-- de la portée efficace. Valeurs provisoires : dégâts pleins jusqu'à la
	-- portée efficace, puis baisse linéaire jusqu'à 50 % à 2× la portée
	-- efficace, et aucun dégât au-delà de 3×.
	falloff = {
		endRangeMultiplier = 2,
		minDamageMultiplier = 0.5,
		maxRangeMultiplier = 3,
	},

	overheat = {
		max = 100,
		coolPerSecond = 30,
		coolDelay = 0.4,
		lockDuration = 2.5,
	},

	parry = {
		meleeFrontalReduction = 0.60,
		frontalAngle = 120, -- angle (degrés) considéré comme « de face »
		moveSpeedMultiplier = 0.5,
		perfectWindow = 0.25,
		perfectStun = 0.8,
		failedPerfectCooldown = 0.5,
	},

	death = {
		disintegrateDuration = 1.2,
	},

	revive = {
		orbLifetime = 90,
		orbHealth = 100,
		acceleratorMinDistance = 80,
		acceleratorMaxDistance = 200,
		channelTime = 5,
		reviveHealth = 50,
	},

	-- Validation serveur des tirs (section 6.11).
	validation = {
		-- Tolérance sur la cadence (le réseau regroupe parfois les paquets).
		fireRateTolerance = 0.85,
		-- Écart maximal entre la position déclarée du tireur et sa position serveur.
		maxShooterPositionError = 12,
		-- Marge ajoutée à la portée maximale.
		rangeTolerance = 6,
		-- Écart maximal entre le point d'impact déclaré et la cible (latence).
		maxHitPositionError = 8,
		-- Âge maximal d'un tir déclaré (secondes).
		maxShotAge = 1.0,
	},
})
