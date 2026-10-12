--!strict
--[[
	Cosmétiques (section 14.5) : skins d'armes, de sacs, de casques et de
	gilets. Purement visuels : aucun effet sur le jeu.

	Chaque cosmétique = un MOTIF (couleurs, matière, rareté) appliqué à une
	CIBLE (une arme précise, ou le sac / le casque / le gilet). Le catalogue
	est généré à partir des deux listes ci-dessous ; ajouter un motif ou une
	cible l'enrichit automatiquement. L'identifiant `motif__cible` ne doit
	jamais changer une fois publié (il est stocké dans les profils).
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

export type Category = "weapon" | "backpack" | "helmet" | "vest"

export type CosmeticDef = {
	id: string,
	pattern: string,
	category: Category,
	target: string, -- identifiant d'arme, ou "backpack" / "helmet" / "vest"
	rarity: string,
	color: Color3,
	accent: Color3,
	material: string, -- nom d'Enum.Material
}

type Pattern = {
	rarity: string,
	color: Color3,
	accent: Color3,
	material: string,
	targets: { string },
}

-- Motifs : rareté, couleurs, matière, et cibles qui le reçoivent.
local patterns: { [string]: Pattern } = {
	scrap_gray = {
		rarity = "common",
		color = Color3.fromRGB(110, 112, 116),
		accent = Color3.fromRGB(170, 170, 170),
		material = "Metal",
		targets = { "scrap_laser_pistol", "shock_crowbar", "backpack", "helmet" },
	},
	olive_drab = {
		rarity = "common",
		color = Color3.fromRGB(86, 92, 60),
		accent = Color3.fromRGB(150, 160, 100),
		material = "Fabric",
		targets = { "vigil_pistol", "sentinel_rifle", "vest", "backpack" },
	},
	desert_tan = {
		rarity = "common",
		color = Color3.fromRGB(170, 146, 104),
		accent = Color3.fromRGB(220, 200, 150),
		material = "SmoothPlastic",
		targets = { "crackler", "hullbreaker", "helmet", "vest" },
	},
	rust_red = {
		rarity = "common",
		color = Color3.fromRGB(120, 58, 40),
		accent = Color3.fromRGB(200, 100, 55),
		material = "CorrodedMetal",
		targets = { "needle", "hydraulic_hammer", "backpack", "vest" },
	},
	cobalt = {
		rarity = "rare",
		color = Color3.fromRGB(30, 70, 160),
		accent = Color3.fromRGB(90, 170, 255),
		material = "Metal",
		targets = { "sentinel_rifle", "helmet", "vest" },
	},
	hazard_stripes = {
		rarity = "rare",
		color = Color3.fromRGB(210, 175, 20),
		accent = Color3.fromRGB(25, 25, 25),
		material = "DiamondPlate",
		targets = { "hullbreaker", "backpack", "helmet" },
	},
	night_ops = {
		rarity = "rare",
		color = Color3.fromRGB(22, 24, 30),
		accent = Color3.fromRGB(70, 80, 100),
		material = "Metal",
		targets = { "needle", "vigil_pistol", "vest" },
	},
	copper_wire = {
		rarity = "rare",
		color = Color3.fromRGB(170, 90, 50),
		accent = Color3.fromRGB(245, 160, 100),
		material = "Foil",
		targets = { "crackler", "pulse_gauntlet", "backpack" },
	},
	neon_pulse = {
		rarity = "epic",
		color = Color3.fromRGB(18, 20, 30),
		accent = Color3.fromRGB(0, 229, 255),
		material = "Metal",
		targets = { "sentinel_rifle", "laser_saber", "helmet" },
	},
	circuit = {
		rarity = "epic",
		color = Color3.fromRGB(20, 60, 40),
		accent = Color3.fromRGB(57, 255, 20),
		material = "SmoothPlastic",
		targets = { "mag_nailer", "vest", "backpack" },
	},
	toxic = {
		rarity = "epic",
		color = Color3.fromRGB(60, 90, 30),
		accent = Color3.fromRGB(170, 255, 60),
		material = "Glass",
		targets = { "short_circuit", "hullbreaker", "helmet" },
	},
	solar_flare = {
		rarity = "legendary",
		color = Color3.fromRGB(230, 120, 20),
		accent = Color3.fromRGB(255, 225, 90),
		material = "Foil",
		targets = { "sentinel_rifle", "hydraulic_hammer", "vest" },
	},
	glitch = {
		rarity = "legendary",
		color = Color3.fromRGB(60, 20, 80),
		accent = Color3.fromRGB(255, 46, 196),
		material = "Glass",
		targets = { "needle", "laser_saber", "backpack" },
	},
	axiom_core = {
		rarity = "mythic",
		color = Color3.fromRGB(14, 14, 20),
		accent = Color3.fromRGB(255, 40, 40),
		material = "Glass",
		targets = { "sentinel_rifle", "helmet" },
	},
	gilded = {
		rarity = "mythic",
		color = Color3.fromRGB(205, 165, 45),
		accent = Color3.fromRGB(255, 235, 140),
		material = "Foil",
		targets = { "laser_saber", "vest" },
	},
}

local ARMOR = { backpack = true, helmet = true, vest = true }

local byId: { [string]: CosmeticDef } = {}
local list: { string } = {}
for patternId, pattern in patterns do
	for _, target in pattern.targets do
		local id = `{patternId}__{target}`
		byId[id] = {
			id = id,
			pattern = patternId,
			category = (if ARMOR[target] then target else "weapon") :: Category,
			target = target,
			rarity = pattern.rarity,
			color = pattern.color,
			accent = pattern.accent,
			material = pattern.material,
		}
		table.insert(list, id)
	end
end
table.sort(list)

return Freeze.deep({
	byId = byId,
	list = list,
	patterns = patterns,
})
