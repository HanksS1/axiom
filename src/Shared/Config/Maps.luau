--!strict
--[[
	Les 4 cartes (section 12) : ~800 × 800 studs, 2 ou 3 zones à risque,
	1 Gardien, 3 extractions, 6 emplacements d'Accélérateur, 8 points de
	départ en bordure, une mécanique d'environnement propre.

	Les cartes sont construites en greybox par le code (Server/Maps) à
	`origin`, loin du Terminus et de l'arène de test. Les valeurs non
	précisées par le document (dégâts d'un effondrement, durées d'alerte…)
	sont des valeurs de départ.
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

export type Lighting = {
	ambient: Color3,
	outdoorAmbient: Color3,
	brightness: number,
	clockTime: number,
	fogColor: Color3,
	fogEnd: number,
}

-- Ambiance : brume atmosphérique, halo des néons, étalonnage des couleurs.
export type Mood = {
	density: number,
	offset: number,
	color: Color3,
	decay: Color3,
	glare: number,
	haze: number,
	bloom: number,
	contrast: number,
	saturation: number,
	tint: Color3,
}

export type GuardianDef = {
	robotId: string,
	nameKey: string,
	behavior: string?, -- "anchored" | "burrow" | "phase" | nil
	overrides: { [string]: any },
}

local maps = {
	neo_lumen = {
		id = "neo_lumen",
		order = 1,
		seed = 1101,
		lighting = {
			ambient = Color3.fromRGB(70, 60, 90),
			outdoorAmbient = Color3.fromRGB(110, 90, 140),
			brightness = 1.6,
			clockTime = 18.6,
			fogColor = Color3.fromRGB(90, 70, 120),
			fogEnd = 900,
		},
		-- Crépuscule violet, poussière en suspension, néons qui bavent.
		mood = {
			density = 0.36,
			offset = 0.2,
			color = Color3.fromRGB(150, 120, 170),
			decay = Color3.fromRGB(70, 50, 90),
			glare = 0.2,
			haze = 2.2,
			bloom = 0.9,
			contrast = 0.12,
			saturation = -0.08,
			tint = Color3.fromRGB(240, 228, 255),
		},
		guardian = {
			robotId = "warden",
			nameKey = "guardian.helix_titan",
			-- Le Titan d'Helix : humanoïde géant, canon laser à charge (lent, puissant).
			overrides = {
				size = Vector3.new(7, 13, 5),
				rangedDamage = 42,
				fireInterval = 2.8,
				windup = 1.3, -- charge du canon : longue, bien visible
				attackRange = 110,
				color = Color3.fromRGB(90, 96, 120),
			},
		},
		-- Effondrements : annoncés par des grondements, ouvrent ou ferment des passages.
		collapse = {
			firstAfter = 150,
			interval = { min = 140, max = 200 },
			warning = 8, -- secondes de grondements avant l'effondrement
			damage = 80, -- dégâts aux combattants sous l'édifice
		},
	},
	forge_7 = {
		id = "forge_7",
		order = 2,
		seed = 2207,
		lighting = {
			ambient = Color3.fromRGB(90, 60, 40),
			outdoorAmbient = Color3.fromRGB(140, 90, 60),
			brightness = 1.4,
			clockTime = 16.5,
			fogColor = Color3.fromRGB(80, 50, 30),
			fogEnd = 800,
		},
		-- Fumées d'usine, lueur orangée des coulées.
		mood = {
			density = 0.42,
			offset = 0.1,
			color = Color3.fromRGB(170, 120, 80),
			decay = Color3.fromRGB(90, 50, 30),
			glare = 0.1,
			haze = 2.6,
			bloom = 1.0,
			contrast = 0.16,
			saturation = -0.12,
			tint = Color3.fromRGB(255, 236, 214),
		},
		guardian = {
			robotId = "warden",
			nameKey = "guardian.forge_arm",
			behavior = "anchored",
			-- Bras robotique géant fixé au plafond : frappe large à courte portée, tir secondaire.
			overrides = {
				size = Vector3.new(8, 14, 8),
				attack = "hybrid",
				damage = 36,
				meleeRange = 16,
				meleeInterval = 2,
				meleeWindup = 1,
				rangedDamage = 18,
				fireInterval = 1.2,
				attackRange = 70,
				speed = 0,
				color = Color3.fromRGB(150, 110, 50),
			},
		},
		production = {
			interval = 180, -- toutes les 3 minutes
			robots = { min = 1, max = 2 },
			robotId = "sentinel",
			panelHealth = 300,
		},
		dormantWakeRadius = 18, -- Exécuteurs de la chaîne : s'activent à l'approche
	},
	terres_brulees = {
		id = "terres_brulees",
		order = 3,
		seed = 3313,
		lighting = {
			ambient = Color3.fromRGB(110, 100, 60),
			outdoorAmbient = Color3.fromRGB(170, 150, 90),
			brightness = 2.4,
			clockTime = 13,
			fogColor = Color3.fromRGB(190, 170, 110),
			fogEnd = 700,
		},
		-- Soleil blanc, voile de sable, teinte maladive.
		mood = {
			density = 0.4,
			offset = 0.35,
			color = Color3.fromRGB(214, 196, 140),
			decay = Color3.fromRGB(150, 140, 80),
			glare = 0.5,
			haze = 2.4,
			bloom = 0.6,
			contrast = 0.1,
			saturation = -0.18,
			tint = Color3.fromRGB(255, 250, 226),
		},
		guardian = {
			robotId = "warden",
			nameKey = "guardian.silica_worm",
			behavior = "burrow",
			-- Le Ver de Silice : s'enfouit puis surgit sous sa cible.
			overrides = {
				size = Vector3.new(6, 8, 10),
				attack = "hybrid",
				damage = 30,
				meleeRange = 9,
				meleeInterval = 1.6,
				meleeWindup = 0.8,
				rangedDamage = 14,
				fireInterval = 1.0,
				attackRange = 60,
				speed = 14,
				color = Color3.fromRGB(170, 150, 110),
			},
		},
		radiation = {
			shieldPerSecond = 5,
			healthPerSecond = 3,
		},
	},
	noyau_zero = {
		id = "noyau_zero",
		order = 4,
		seed = 4421,
		lighting = {
			ambient = Color3.fromRGB(40, 50, 80),
			outdoorAmbient = Color3.fromRGB(50, 60, 100),
			brightness = 0.8,
			clockTime = 0.5,
			fogColor = Color3.fromRGB(20, 25, 40),
			fogEnd = 600,
		},
		-- Nuit froide : seuls les néons et les projecteurs éclairent.
		mood = {
			density = 0.3,
			offset = 0,
			color = Color3.fromRGB(60, 80, 120),
			decay = Color3.fromRGB(20, 30, 50),
			glare = 0,
			haze = 1.6,
			bloom = 1.2,
			contrast = 0.18,
			saturation = -0.05,
			tint = Color3.fromRGB(222, 236, 255),
		},
		guardian = {
			robotId = "warden",
			nameKey = "guardian.axiom_projection",
			behavior = "phase",
			-- Projection d'AXIOM : devient intangible et se déplace par à-coups.
			overrides = {
				size = Vector3.new(5, 11, 4),
				rangedDamage = 22,
				fireInterval = 1.1,
				windup = 0.6,
				attackRange = 90,
				color = Color3.fromRGB(255, 59, 59),
			},
		},
		blackout = {
			firstAfter = { min = 120, max = 180 },
			interval = { min = 120, max = 180 }, -- toutes les 2 à 3 minutes
			duration = 20,
			visionMultiplier = 0.55, -- vision des robots et des mercenaires dans le noir
		},
	},
}

-- Comportements des Gardiens.
local guardianBehaviors = {
	-- `warning` : secondes entre l'annonce du point d'émergence (cercle rouge
	-- au sol) et le surgissement. Le point est figé à l'annonce : on s'en écarte.
	burrow = { every = 11, hidden = 2.5, warning = 1.4, minDistance = 20, surfaceRadius = 8, surfaceDamage = 30 },
	-- `jump` : distance de la cible à laquelle la projection réapparaît.
	phase = { every = 10, hidden = 2.5, jump = 22 },
}

local list: { string } = {}
for id in maps :: { [string]: any } do
	table.insert(list, id)
end
table.sort(list, function(a, b)
	return (maps :: any)[a].order < (maps :: any)[b].order
end)

return Freeze.deep({
	byId = maps,
	list = list,
	origin = Vector3.new(0, 0, -1600),
	size = 800,
	-- Plan vu de dessus (touche « carte ») : taille d'une case en studs, et
	-- tranche de hauteur dans laquelle un obstacle compte (hauteur d'homme) ;
	-- `minSpan` : le décor plus court (barils, caisses) n'est pas dessiné.
	plan = { cell = 4, band = { min = 1.5, max = 6, minSpan = 7 } },
	guardianBehaviors = guardianBehaviors,
	-- Métal en fusion (Forge-7) : mort instantanée. Zones vérifiées 5 fois par seconde.
	hazardTick = 0.2,
})
