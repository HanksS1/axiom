--!strict
--[[
	Armes à distance (section 6.6) et de mêlée (section 6.7).

	Les dégâts indiqués correspondent à l'état « Bon état » (×1,00) ; le
	multiplicateur d'état (Conditions.efficiency) s'applique par-dessus.

	Conventions :
	- `fireRate` = nombre d'activations par seconde (tirs, ou rafales pour
	  une arme à rafale). Pour un rayon continu, la cadence n'a pas de sens :
	  les dégâts sont exprimés par seconde (`damagePerSecond`).
	- Armes à chargeur : 1 cellule = 1 projectile tiré (la recharge prélève
	  les cellules du sac). Une rafale de 3 consomme donc 3 cellules.
	- Armes à surchauffe : pas de chargeur, les cellules sont prélevées
	  directement dans le sac selon `cellCost`.
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

export type FireMode = "semi" | "burst" | "auto" | "beam"

export type RangedDef = {
	id: string,
	category: "ranged",
	class: string,
	cell: string,
	fireMode: FireMode,
	damage: number, -- par projectile (ou par seconde pour un rayon)
	pellets: number, -- projectiles par tir (fusil à pompe)
	burstCount: number, -- projectiles par rafale (1 si pas de rafale)
	burstInterval: number, -- secondes entre deux projectiles d'une rafale
	fireRate: number,
	effectiveRange: number,
	capacity: number?, -- nil = arme à surchauffe sans chargeur
	reloadTime: number?,
	heat: {
		perShot: number?,
		perSecond: number?,
	}?,
	-- Coût en cellules pour les armes à surchauffe : `cells` cellules toutes
	-- les `everyShots` tirs, ou toutes les `everySeconds` secondes de rayon.
	cellCost: {
		cells: number,
		everyShots: number?,
		everySeconds: number?,
	}?,
	headshots: boolean,
	spread: number, -- dispersion en degrés (hanche, debout, Bon état)
	projectileSpeed: number?, -- nil = tir instantané (raycast)
	arcGravity: number?, -- gravité appliquée au projectile (tir en cloche)
	splashRadius: number?,
	noiseRadius: number, -- rayon d'audition des robots
	tracerDuration: number?, -- tracé visible par tous (secondes)
	lightCoverDamageMultiplier: number?, -- traverse les couverts légers
	robotDamageMultiplier: number?,
	slowOnHit: { multiplier: number, duration: number }?,
	up: number,
	baseValue: number,
}

export type MeleeDef = {
	id: string,
	category: "melee",
	damage: number,
	attacksPerSecond: number,
	range: number,
	up: number,
	baseValue: number,
	reflectsLasersWhenPristine: boolean?,
	breaksParry: boolean?,
	parryBreakStun: number?,
	knockback: number?,
	shieldIgnore: number?, -- fraction du bouclier ignorée (0..1)
	dropOnlyFromElites: boolean?,
}

local DEFAULT_NOISE = 60

local ranged: { [string]: RangedDef } = {
	scrap_laser_pistol = {
		id = "scrap_laser_pistol",
		category = "ranged",
		class = "pistol",
		cell = "cell_light",
		fireMode = "semi",
		damage = 18,
		pellets = 1,
		burstCount = 1,
		burstInterval = 0,
		fireRate = 3,
		effectiveRange = 60,
		capacity = 12,
		reloadTime = 1.6,
		headshots = true,
		spread = 1.2,
		noiseRadius = DEFAULT_NOISE,
		up = 2,
		baseValue = 100,
	},
	vigil_pistol = {
		id = "vigil_pistol",
		category = "ranged",
		class = "pistol",
		cell = "cell_light",
		fireMode = "burst",
		damage = 16,
		pellets = 1,
		burstCount = 3,
		burstInterval = 0.06,
		fireRate = 2,
		effectiveRange = 90,
		capacity = 24,
		reloadTime = 1.8,
		headshots = true,
		spread = 0.9,
		noiseRadius = DEFAULT_NOISE,
		up = 2,
		baseValue = 600,
	},
	crackler = {
		id = "crackler",
		category = "ranged",
		class = "smg",
		cell = "cell_light",
		fireMode = "auto",
		damage = 11,
		pellets = 1,
		burstCount = 1,
		burstInterval = 0,
		fireRate = 11,
		effectiveRange = 40,
		capacity = 36,
		reloadTime = 2.0,
		headshots = true,
		spread = 2.2,
		noiseRadius = DEFAULT_NOISE,
		up = 3,
		baseValue = 750,
	},
	sentinel_rifle = {
		id = "sentinel_rifle",
		category = "ranged",
		class = "rifle",
		cell = "cell_standard",
		fireMode = "auto",
		damage = 17,
		pellets = 1,
		burstCount = 1,
		burstInterval = 0,
		fireRate = 8,
		effectiveRange = 120,
		capacity = 30,
		reloadTime = 2.2,
		headshots = true,
		spread = 1.0,
		noiseRadius = DEFAULT_NOISE,
		up = 4,
		baseValue = 1000,
	},
	hullbreaker = {
		id = "hullbreaker",
		category = "ranged",
		class = "shotgun",
		cell = "cell_standard",
		fireMode = "semi",
		damage = 9,
		pellets = 8,
		burstCount = 1,
		burstInterval = 0,
		fireRate = 1.1,
		effectiveRange = 25,
		capacity = 6,
		reloadTime = 2.6,
		headshots = true,
		spread = 6,
		noiseRadius = DEFAULT_NOISE,
		up = 3,
		baseValue = 1100,
	},
	mag_nailer = {
		id = "mag_nailer",
		category = "ranged",
		class = "nailer",
		cell = "cell_standard",
		fireMode = "semi",
		damage = 45,
		pellets = 1,
		burstCount = 1,
		burstInterval = 0,
		fireRate = 1.4,
		effectiveRange = 100,
		capacity = 8,
		reloadTime = 2.4,
		headshots = true,
		spread = 0.5,
		projectileSpeed = 250,
		noiseRadius = 15,
		up = 3,
		baseValue = 900,
	},
	needle = {
		id = "needle",
		category = "ranged",
		class = "railgun",
		cell = "cell_precision",
		fireMode = "semi",
		damage = 85,
		pellets = 1,
		burstCount = 1,
		burstInterval = 0,
		fireRate = 0.7,
		effectiveRange = 300,
		capacity = 5,
		reloadTime = 2.8,
		headshots = true,
		spread = 0.1,
		noiseRadius = DEFAULT_NOISE,
		tracerDuration = 0.5,
		up = 5,
		baseValue = 1500,
	},
	bastion_minigun = {
		id = "bastion_minigun",
		category = "ranged",
		class = "heavy",
		cell = "cell_heavy",
		fireMode = "auto",
		damage = 14,
		pellets = 1,
		burstCount = 1,
		burstInterval = 0,
		fireRate = 14,
		effectiveRange = 110,
		heat = { perShot = 4 },
		cellCost = { cells = 1, everyShots = 3 },
		headshots = true,
		spread = 2.5,
		noiseRadius = DEFAULT_NOISE,
		up = 6,
		baseValue = 2200,
	},
	xray_cannon = {
		id = "xray_cannon",
		category = "ranged",
		class = "beam",
		cell = "cell_heavy",
		fireMode = "beam",
		damage = 60, -- par seconde
		pellets = 1,
		burstCount = 1,
		burstInterval = 0,
		fireRate = 0,
		effectiveRange = 50,
		heat = { perSecond = 25 },
		cellCost = { cells = 1, everySeconds = 0.5 },
		headshots = false,
		spread = 0,
		noiseRadius = DEFAULT_NOISE,
		lightCoverDamageMultiplier = 0.5,
		up = 6,
		baseValue = 2800,
	},
	short_circuit = {
		id = "short_circuit",
		category = "ranged",
		class = "launcher",
		cell = "cell_heavy",
		fireMode = "semi",
		damage = 70, -- en zone
		pellets = 1,
		burstCount = 1,
		burstInterval = 0,
		fireRate = 0.8,
		effectiveRange = 70,
		heat = { perShot = 35 },
		cellCost = { cells = 2, everyShots = 1 },
		headshots = false,
		spread = 0.5,
		projectileSpeed = 90,
		arcGravity = 60,
		splashRadius = 8,
		noiseRadius = DEFAULT_NOISE,
		robotDamageMultiplier = 2.5,
		slowOnHit = { multiplier = 0.5, duration = 1 },
		up = 6,
		baseValue = 2500,
	},
}

local melee: { [string]: MeleeDef } = {
	shock_crowbar = {
		id = "shock_crowbar",
		category = "melee",
		damage = 30,
		attacksPerSecond = 1.5,
		range = 6,
		up = 3,
		baseValue = 80,
	},
	laser_saber = {
		id = "laser_saber",
		category = "melee",
		damage = 28,
		attacksPerSecond = 2.5,
		range = 7,
		up = 2,
		baseValue = 900,
		reflectsLasersWhenPristine = true,
	},
	hydraulic_hammer = {
		id = "hydraulic_hammer",
		category = "melee",
		damage = 70,
		attacksPerSecond = 0.7,
		range = 7,
		up = 4,
		baseValue = 1200,
		breaksParry = true,
		parryBreakStun = 1,
	},
	pulse_gauntlet = {
		id = "pulse_gauntlet",
		category = "melee",
		damage = 35,
		attacksPerSecond = 1.6,
		range = 4,
		up = 2,
		baseValue = 1000,
		knockback = 15,
	},
	vibro_blade = {
		id = "vibro_blade",
		category = "melee",
		damage = 45,
		attacksPerSecond = 2.0,
		range = 7,
		up = 3,
		baseValue = 3000,
		shieldIgnore = 0.5,
		dropOnlyFromElites = true,
	},
}

return Freeze.deep({
	ranged = ranged,
	melee = melee,
})
