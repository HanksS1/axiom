--!strict
--[[
	Caisses de loot sur les cartes (section 9).

	Contenu piloté par un BUDGET DE VALEUR (validé par l'auteur) :
	en moyenne, 2 caisses de ravitaillement en mode Facile rapportent de quoi
	racheter l'équivalent du kit de base chez le Marchand (au prix le plus
	bas), avec une variation aléatoire au-dessus ou en dessous.

	budget = coût du kit au Marchand × kitShare × multiplicateur du mode
	         × tirage uniforme dans [1 - variance, 1 + variance]

	Le coût du kit est calculé depuis la config (Economy.baseKit + prix du
	Marchand) : si les prix changent, le contenu des caisses suit.
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

export type LootCrateDef = {
	id: string,
	openTime: number,
	alarmRadius: number?,
	-- Part du coût du kit de base visée par une caisse (0,5 = 2 caisses pour un kit).
	kitShare: number,
	variance: number, -- ± autour du budget (0,3 = de 70 % à 130 %)
	equipmentChance: number, -- probabilité d'au moins un objet d'équipement
	equipment: { min: number, max: number }, -- nombre d'objets si la caisse en contient
	minCondition: number?, -- état garanti pour le 1er objet d'équipement
	calibrationChanceHard: number?, -- Module de calibration (mode Difficile uniquement)
	cellStacks: { min: number, max: number }, -- piles de cellules toujours présentes
	maxItems: number, -- nombre maximal d'objets dans la caisse
}

local crates: { [string]: LootCrateDef } = {
	-- Caisse de ravitaillement : partout, cellules et consommables, parfois un objet.
	supply = {
		id = "supply",
		openTime = 1.5,
		kitShare = 0.5,
		variance = 0.3,
		equipmentChance = 0.25,
		equipment = { min = 1, max = 1 },
		cellStacks = { min = 1, max = 2 },
		maxItems = 6,
	},
	-- Coffre militaire : zones à risque, 1 à 2 objets d'équipement et des consommables.
	military = {
		id = "military",
		openTime = 2.5,
		kitShare = 1.25,
		variance = 0.3,
		equipmentChance = 1,
		equipment = { min = 1, max = 2 },
		cellStacks = { min = 0, max = 1 },
		maxItems = 6,
	},
	-- Casier d'AXIOM : cœur des zones à risque, 2 objets dont un Dégradé ou mieux.
	axiom_locker = {
		id = "axiom_locker",
		openTime = 4,
		alarmRadius = 60,
		kitShare = 2.5,
		variance = 0.25,
		equipmentChance = 1,
		equipment = { min = 2, max = 2 },
		minCondition = 3,
		calibrationChanceHard = 0.15,
		cellStacks = { min = 0, max = 1 },
		maxItems = 6,
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
	-- Cellules par pile trouvée (une pile pleine = 30).
	cellQuantity = { min = 10, max = 30 },
	-- Le remplissage s'arrête quand le budget restant passe sous ce seuil (crédits).
	fillThreshold = 25,
	-- Délai de réapparition des caisses dans l'arène de test (Studio).
	arenaRespawnDelay = 30,
})
