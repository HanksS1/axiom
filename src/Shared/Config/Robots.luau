--!strict
--[[
	Robots d'AXIOM (section 10) : stats de base, IA, densité et loot.
	Les multiplicateurs par mode sont dans Modes.luau.
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

export type LootEntry = {
	itemId: string?, -- objet précis
	pool: string?, -- ou tirage dans une famille (« consumable », « equipment »…)
	chance: number, -- 0..1
	quantity: number?, -- pour les cellules : nombre de cellules
	hardModeOnly: boolean?,
}

export type RobotDef = {
	id: string,
	health: number,
	damage: number,
	rangedDamage: number?,
	scorePoints: number,
	visionRange: number,
	flying: boolean,
	weakSpotMultiplier: number?, -- point faible (dos) du Bastion
	alertRadius: number?, -- la Mouche alerte les robots proches
	packSize: { min: number, max: number }?,
	conditionShift: number, -- décalage d'état du loot (+1 pour les élites)
	guaranteedItems: { min: number, max: number }?,
	loot: { LootEntry },
}

local robots: { [string]: RobotDef } = {
	fly = {
		id = "fly",
		health = 30,
		damage = 5,
		scorePoints = 10,
		visionRange = 80,
		flying = true,
		alertRadius = 40,
		conditionShift = 0,
		loot = {
			{ pool = "cells", chance = 0.5, quantity = 15 },
		},
	},
	stalker = {
		id = "stalker",
		health = 80,
		damage = 15,
		scorePoints = 20,
		visionRange = 60,
		flying = false,
		packSize = { min = 2, max = 3 },
		conditionShift = 0,
		loot = {
			{ pool = "cells", chance = 1, quantity = 15 },
			{ pool = "consumable", chance = 0.3 },
		},
	},
	sentinel = {
		id = "sentinel",
		health = 150,
		damage = 10,
		scorePoints = 30,
		visionRange = 100,
		flying = false,
		conditionShift = 0,
		loot = {
			{ itemId = "cell_standard", chance = 1, quantity = 20 },
			{ itemId = "sentinel_rifle", chance = 0.08 },
			{ pool = "consumable", chance = 0.3 },
		},
	},
	bastion = {
		id = "bastion",
		health = 600,
		damage = 8,
		scorePoints = 60,
		visionRange = 90,
		flying = false,
		weakSpotMultiplier = 2.5,
		conditionShift = 0,
		loot = {
			{ itemId = "cell_heavy", chance = 1, quantity = 30 },
			{ itemId = "bastion_minigun", chance = 0.15 },
			{ itemId = "vest", chance = 0.20 },
		},
	},
	executor = {
		id = "executor",
		health = 400,
		damage = 25,
		rangedDamage = 15,
		scorePoints = 80,
		visionRange = 120,
		flying = false,
		conditionShift = 1,
		guaranteedItems = { min = 1, max = 1 },
		loot = {
			{ itemId = "vibro_blade", chance = 0.10 },
		},
	},
	warden = {
		id = "warden",
		health = 1800,
		damage = 30, -- « selon la carte » : valeur par défaut, surchargée par carte
		scorePoints = 250,
		visionRange = 120,
		flying = false,
		conditionShift = 1,
		guaranteedItems = { min = 2, max = 3 },
		loot = {
			{ itemId = "calibration_module", chance = 0.40, hardModeOnly = true },
		},
	},
}

return Freeze.deep({
	byId = robots,

	density = {
		minActive = 20,
		maxActive = 28,
		garrisonShare = 0.6, -- 60 % en garnison dans les zones à risque
	},

	ai = {
		visionAngle = 90,
		gunshotHearingRadius = 60, -- surchargé par l'arme (noiseRadius)
		updateRate = 8, -- mises à jour par seconde (entre 5 et 10)
		sleepDistance = 150, -- logique lourde désactivée sans joueur à moins de 150 studs
		suspicionTime = 1.0,
		searchTime = 8,
	},
})
