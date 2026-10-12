--!strict
--[[
	Économie de crédits (sections 7.3, 8.7, 8.8, 14.2 à 14.4).
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

export type KitEntry = {
	itemId: string,
	condition: number?,
	stack: number?,
}

return Freeze.deep({
	vault = {
		baseCapacity = 30,
		extensionBonus = 10, -- Game Pass, achat unique
	},

	merchant = {
		-- Le Marchand ne vend que ces états (Dégradé, Bon état) à ×2 leur valeur.
		sellsConditions = { 3, 4 },
		equipmentPriceMultiplier = 2,
		consumablePriceMultiplier = 1.5,
		-- Revente : à la valeur de l'objet (valeur de base × multiplicateur d'état).
		resaleMultiplier = 1,
		confirmAbove = 1000,
	},

	repair = {
		costMultiplier = 1.5,
		-- Bon état → Neuf exige un Module de calibration.
		calibrationRequiredForCondition = 5,
		calibrationItemId = "calibration_module",
	},

	insurance = {
		tiers = {
			basic = { order = 1, costShare = 0.10, conditionLoss = 2 },
			standard = { order = 2, costShare = 0.18, conditionLoss = 1 },
			premium = { order = 3, costShare = 0.30, conditionLoss = 0 },
		},
	},

	freeCrate = {
		interval = 20 * 60, -- secondes, temps réel (même hors ligne)
		maxStored = 2,
		creditsChance = 0.85,
		credits = { min = 50, max = 300 },
		-- 15 % : objet temporaire (consommable ou gadget, Bon état), 3 parties.
		tempItemCondition = 4,
		tempItemGames = 3,
		tempItemPool = {
			"nanite_injector",
			"shield_battery",
			"overdrive",
			"exo_harness",
			"jump_boots",
			"grappling_hook",
			"recon_drone",
			"deployable_wall",
			"smoke_deployer",
		},
	},

	-- Kit de base gratuit (section 8.8) : non vendable, valeur nulle.
	baseKit = {
		ranged = { itemId = "scrap_laser_pistol", condition = 1 },
		melee = { itemId = "shock_crowbar", condition = 1 },
		backpack = { itemId = "backpack_small", condition = 1 },
		bag = {
			{ itemId = "nanite_injector", stack = 3 },
			{ itemId = "cell_light", stack = 30 },
			{ itemId = "cell_light", stack = 30 },
		},
	},

	-- Garde-fous anti-exploit (plafonds absolus).
	maxCredits = 2_000_000_000,
})
