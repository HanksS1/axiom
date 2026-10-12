--!strict
--[[
	Mercenaires IA de remplissage (section 11).

	Ils complètent les parties incomplètes après le délai de matchmaking,
	avec un équipement dans la plage de SE du mode et un pseudo généré. Ils
	explorent, lootent, combattent et s'extraient (IA plus simple que celle
	des joueurs, pas de réanimation par orbe). Leur kill compte 50 % d'un
	kill de joueur (Progression.score.botKill).
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

return Freeze.deep({
	names = {
		prefixes = {
			"Rook",
			"Vex",
			"Kestrel",
			"Nyx",
			"Talon",
			"Ash",
			"Cobalt",
			"Rift",
			"Echo",
			"Volt",
			"Jinx",
			"Onyx",
			"Sable",
			"Hex",
			"Drift",
			"Flint",
			"Wraith",
			"Cinder",
			"Gauge",
			"Brine",
			"Moth",
			"Static",
			"Quill",
			"Rust",
		},
		numberMin = 10,
		numberMax = 99,
	},

	-- Équipement : armes à chargeur uniquement (IA plus simple), par mode.
	weapons = {
		easy = { "scrap_laser_pistol", "vigil_pistol", "crackler", "sentinel_rifle" },
		medium = { "vigil_pistol", "crackler", "sentinel_rifle", "hullbreaker", "needle" },
		hard = { "sentinel_rifle", "hullbreaker", "needle", "crackler" },
	},
	melee = { "shock_crowbar", "laser_saber", "hydraulic_hammer", "pulse_gauntlet" },
	armorChance = { helmet = 0.6, vest = 0.8 },
	backpacks = { "backpack_small", "backpack_medium", "backpack_large" },
	consumables = { "nanite_injector", "shield_battery" },
	consumableCount = { min = 1, max = 3 },
	cellStacks = { min = 2, max = 4 },
	-- SE visé : entre le minimum du mode et son maximum (ou minimum × 2 en Difficile).
	hardCeilingMultiplier = 2,
	gearAttempts = 40,

	ai = {
		updateRate = 5, -- décisions par seconde (étalées entre les mercenaires)
		visionRange = 110,
		visionAngle = 120, -- degrés
		closeAwareness = 10, -- perçu même hors du cône en dessous de cette distance
		maxRaycastsPerUpdate = 3,
		-- Probabilité de toucher, par mode (avant la portée).
		accuracy = { easy = 0.28, medium = 0.4, hard = 0.52 },
		headshotChance = 0.12,
		reactionTime = 0.6, -- délai avant le premier tir sur une nouvelle cible
		missSpread = 4,
		lootRadius = 90,
		lootTime = 2.5,
		-- Moment où le mercenaire part s'extraire (secondes de partie) ; à
		-- l'alerte de 12:00, tous partent.
		extractAfter = { min = 300, max = 690 },
		fullBagFreeUp = 2, -- sac considéré plein en dessous de cette place libre
		healBelow = 0.45, -- part des PV max
		shieldBelow = 0.4, -- part du bouclier max
		strafeInterval = 1.4,
		strafeDistance = 6,
		memory = 6, -- secondes : poursuite de la dernière position connue
		pathRefresh = 1.5,
		wanderRadius = 50,
	},
})
