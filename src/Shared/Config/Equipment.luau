--!strict
--[[
	Équipement non-arme : casques, gilets (sections 6.2, 6.3, 8.4), sacs
	(section 8.3), gadgets (section 8.5), consommables (section 8.6) et
	Module de calibration (section 7.3).

	Les tableaux indexés par état utilisent l'indice d'état (1 = Très abîmé …
	5 = Neuf, voir Conditions).
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

export type HelmetDef = {
	id: string,
	category: "helmet",
	headMultiplierByCondition: { number },
	up: number,
	baseValue: number,
}

export type VestDef = {
	id: string,
	category: "vest",
	shieldByCondition: { number },
	up: number,
	baseValue: number,
}

export type BackpackDef = {
	id: string,
	category: "backpack",
	size: "small" | "medium" | "large",
	capacityByCondition: { number },
	up: number, -- encombrement quand le sac est rangé
	baseValue: number,
}

export type GadgetDef = {
	id: string,
	category: "gadget",
	-- Stat principale modulée par l'état (multipliée par l'efficacité).
	stats: { [string]: number },
	-- Recharge en secondes (divisée par l'efficacité) OU nombre d'utilisations par partie.
	cooldown: number?,
	usesPerMatch: number?,
	up: number,
	baseValue: number,
}

export type ConsumableDef = {
	id: string,
	category: "consumable",
	stackSize: number,
	stackValue: number, -- valeur d'une pile pleine
	useTime: number, -- secondes (0 = instantané)
	moveSpeedMultiplierWhileUsing: number,
	effect: { [string]: number },
	up: number, -- par pile
}

export type MiscDef = {
	id: string,
	category: "calibration",
	up: number,
	baseValue: number,
	hardModeOnly: boolean,
}

local helmets: { [string]: HelmetDef } = {
	helmet = {
		id = "helmet",
		category = "helmet",
		-- Multiplicateur de dégâts à la tête selon l'état du casque porté.
		headMultiplierByCondition = { 1.8, 1.7, 1.6, 1.45, 1.3 },
		up = 2,
		baseValue = 500,
	},
}

local vests: { [string]: VestDef } = {
	vest = {
		id = "vest",
		category = "vest",
		shieldByCondition = { 25, 40, 55, 70, 100 },
		up = 3,
		baseValue = 900,
	},
}

local backpacks: { [string]: BackpackDef } = {
	backpack_small = {
		id = "backpack_small",
		category = "backpack",
		size = "small",
		capacityByCondition = { 8, 9, 10, 11, 13 },
		up = 2,
		baseValue = 300,
	},
	backpack_medium = {
		id = "backpack_medium",
		category = "backpack",
		size = "medium",
		capacityByCondition = { 12, 13, 14, 16, 18 },
		up = 3,
		baseValue = 700,
	},
	backpack_large = {
		id = "backpack_large",
		category = "backpack",
		size = "large",
		capacityByCondition = { 16, 18, 20, 22, 25 },
		up = 4,
		baseValue = 1400,
	},
}

local gadgets: { [string]: GadgetDef } = {
	jump_boots = {
		id = "jump_boots",
		category = "gadget",
		stats = { jumpHeight = 20 },
		cooldown = 15,
		up = 2,
		baseValue = 700,
	},
	grappling_hook = {
		id = "grappling_hook",
		category = "gadget",
		stats = { range = 60 },
		cooldown = 12,
		up = 1,
		baseValue = 800,
	},
	recon_drone = {
		id = "recon_drone",
		category = "gadget",
		stats = { radius = 40, duration = 8 },
		usesPerMatch = 2,
		up = 2,
		baseValue = 900,
	},
	deployable_wall = {
		id = "deployable_wall",
		category = "gadget",
		stats = { width = 6, height = 8, health = 300, duration = 45 },
		usesPerMatch = 2,
		up = 2,
		baseValue = 750,
	},
	smoke_deployer = {
		id = "smoke_deployer",
		category = "gadget",
		stats = { radius = 15, duration = 12 },
		usesPerMatch = 3,
		up = 1,
		baseValue = 400,
	},
}

-- Stats d'un gadget qui NE sont PAS modulées par l'état (dimensions physiques).
local gadgetFixedStats: { [string]: boolean } = {
	width = true,
	height = true,
}

local consumables: { [string]: ConsumableDef } = {
	nanite_injector = {
		id = "nanite_injector",
		category = "consumable",
		stackSize = 3,
		stackValue = 150,
		useTime = 1.5,
		moveSpeedMultiplierWhileUsing = 0.5,
		effect = { heal = 50 },
		up = 1,
	},
	shield_battery = {
		id = "shield_battery",
		category = "consumable",
		stackSize = 3,
		stackValue = 150,
		useTime = 2,
		moveSpeedMultiplierWhileUsing = 0.5,
		effect = { shield = 50 },
		up = 1,
	},
	overdrive = {
		id = "overdrive",
		category = "consumable",
		stackSize = 3,
		stackValue = 200,
		useTime = 0,
		moveSpeedMultiplierWhileUsing = 1,
		effect = { speedMultiplier = 1.2, duration = 20 },
		up = 1,
	},
	exo_harness = {
		id = "exo_harness",
		category = "consumable",
		stackSize = 3,
		stackValue = 300,
		useTime = 0,
		moveSpeedMultiplierWhileUsing = 1,
		effect = { bonusUp = 6 },
		up = 1,
	},
}

local misc: { [string]: MiscDef } = {
	calibration_module = {
		id = "calibration_module",
		category = "calibration",
		up = 1,
		baseValue = 1500,
		hardModeOnly = true,
	},
}

return Freeze.deep({
	helmets = helmets,
	vests = vests,
	backpacks = backpacks,
	gadgets = gadgets,
	gadgetFixedStats = gadgetFixedStats,
	consumables = consumables,
	misc = misc,
	-- Sans sac, le joueur dispose de 4 UP de poches (section 8.3).
	pocketsUp = 4,
	-- Sans casque : multiplicateur de tête ×2,0 (section 6.3).
	noHelmetHeadMultiplier = 2.0,
})
