--!strict
--[[
	Caisses de loot sur les cartes (section 9).
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

export type LootCrateDef = {
	id: string,
	openTime: number,
	alarmRadius: number?,
	equipment: { min: number, max: number },
	consumables: { min: number, max: number },
	cells: { min: number, max: number }, -- nombre de piles
	equipmentChance: number, -- probabilité que les objets d'équipement apparaissent
	minCondition: number?, -- état garanti pour le 1er objet
	calibrationChanceHard: number?,
}

local crates: { [string]: LootCrateDef } = {
	supply = {
		id = "supply",
		openTime = 1.5,
		equipment = { min = 1, max = 1 },
		equipmentChance = 0.25, -- « parfois un objet »
		consumables = { min = 0, max = 1 },
		cells = { min = 1, max = 2 },
	},
	military = {
		id = "military",
		openTime = 2.5,
		equipment = { min = 1, max = 2 },
		equipmentChance = 1,
		consumables = { min = 1, max = 2 },
		cells = { min = 0, max = 1 },
	},
	axiom_locker = {
		id = "axiom_locker",
		openTime = 4,
		alarmRadius = 60,
		equipment = { min = 2, max = 2 },
		equipmentChance = 1,
		consumables = { min = 0, max = 1 },
		cells = { min = 0, max = 1 },
		minCondition = 3, -- 1 objet garanti Dégradé ou mieux
		calibrationChanceHard = 0.15,
	},
}

-- Familles de tirage utilisées par les caisses et les robots.
-- Le poids détermine la fréquence relative de chaque objet dans la famille.
local pools: { [string]: { [string]: number } } = {
	equipment = {
		scrap_laser_pistol = 10,
		vigil_pistol = 6,
		crackler = 6,
		sentinel_rifle = 5,
		hullbreaker = 5,
		mag_nailer = 5,
		needle = 3,
		bastion_minigun = 2,
		xray_cannon = 1.5,
		short_circuit = 1.5,
		shock_crowbar = 8,
		laser_saber = 4,
		hydraulic_hammer = 3,
		pulse_gauntlet = 4,
		helmet = 8,
		vest = 7,
		backpack_small = 6,
		backpack_medium = 4,
		backpack_large = 2,
		jump_boots = 3,
		grappling_hook = 3,
		recon_drone = 3,
		deployable_wall = 3,
		smoke_deployer = 4,
	},
	consumable = {
		nanite_injector = 4,
		shield_battery = 4,
		overdrive = 2,
		exo_harness = 1,
	},
	cells = {
		cell_light = 4,
		cell_standard = 4,
		cell_precision = 1.5,
		cell_heavy = 1.5,
	},
}

return Freeze.deep({
	crates = crates,
	pools = pools,
	cratesPerMap = 60,
	-- Quantité d'objets d'une pile de consommables trouvée (1 à 3).
	consumableQuantity = { min = 1, max = 3 },
	-- Nombre de cellules par pile trouvée.
	cellQuantity = { min = 10, max = 30 },
})
