--!strict
--[[
	ItemModels : apparence de chaque objet du jeu (armes, armures, sacs,
	gadgets, consommables, cellules), décrite par quelques pièces simples.

	Une seule description sert partout : arme tenue en main (serveur), icône
	des cartes d'objets et aperçus de la boutique (client). Un objet a donc
	la même silhouette dans la caisse, dans le sac et en main.

	Langage visuel (charte, section 17.1) :
	- corps en métal sombre ; pièces secondaires selon l'origine de l'objet :
	  « scrap » (rouille, ruban adhésif : fait maison), « military » (acier
	  propre : matériel repris à AXIOM), « axiom » (acier noir strié : élite) ;
	- UN accent néon par objet. Pour une arme à distance, c'est la couleur de
	  sa CELLULE (jaune légère, cyan standard, blanche précision, rouge
	  lourde) : on reconnaît les munitions à l'arme, et le tracé du tir a la
	  même couleur ;
	- un skin cosmétique remplace la couleur du corps et celle de l'accent.

	Repère d'une arme : -Z vers l'avant (la bouche est à l'avant de la pièce
	« Body », qui court sur toute la longueur), +Y vers le haut.

	`blueprint` est PUR (testé hors Studio) ; `build` crée les Instances.
]]

local Config = require(script.Parent.Parent.Config)

local Visuals = Config.Visuals

local ItemModels = {}

export type Role = "body" | "plate" | "dark" | "tape" | "accent" | "glass" | "steel"

export type PartSpec = {
	name: string,
	size: Vector3,
	cframe: CFrame, -- dans le repère de l'objet (la pièce « Body » est à l'origine)
	role: Role,
	material: string?, -- nom d'Enum.Material (sinon : matière du rôle)
	shape: string?, -- "Cylinder" | "Ball"
}

export type Theme = "scrap" | "military" | "axiom"

export type Blueprint = {
	theme: Theme,
	accent: Color3,
	parts: { PartSpec },
}

export type Skin = { color: Color3, accent: Color3, material: string }

local STEEL = Color3.fromRGB(112, 118, 128)
local DARK = Color3.fromRGB(24, 26, 31)
local TAPE = Color3.fromRGB(152, 150, 138)
local GLASS = Color3.fromRGB(120, 170, 190)

local PLATE: { [Theme]: { color: Color3, material: string } } = {
	scrap = { color = Color3.fromRGB(128, 82, 54), material = "CorrodedMetal" },
	military = { color = Color3.fromRGB(96, 102, 112), material = "Metal" },
	axiom = { color = Color3.fromRGB(38, 40, 48), material = "DiamondPlate" },
}

-- Accents de la charte.
local CYAN = Color3.fromRGB(0, 229, 255)
local MAGENTA = Color3.fromRGB(255, 46, 196)
local ORANGE = Color3.fromRGB(255, 138, 0)
local GREEN = Color3.fromRGB(57, 255, 20)
local RED = Color3.fromRGB(255, 59, 59)
local WHITE = Color3.fromRGB(235, 245, 255)
local GOLD = Color3.fromRGB(255, 176, 32)

-- Constructeurs de pièces --------------------------------------------------------

local function box(
	name: string,
	sx: number,
	sy: number,
	sz: number,
	x: number,
	y: number,
	z: number,
	role: Role,
	material: string?,
	rotation: CFrame?
): PartSpec
	local cframe = CFrame.new(x, y, z)
	if rotation then
		cframe *= rotation
	end
	return { name = name, size = Vector3.new(sx, sy, sz), cframe = cframe, role = role, material = material }
end

-- Cylindre le long de l'axe `axis` de l'objet ("z" : dans la longueur, par défaut).
local function rod(
	name: string,
	diameter: number,
	length: number,
	x: number,
	y: number,
	z: number,
	role: Role,
	axis: string?,
	material: string?
): PartSpec
	-- L'axe d'un cylindre Roblox est son axe X.
	local turn = if axis == "x"
		then CFrame.new()
		elseif axis == "y" then CFrame.Angles(0, 0, math.rad(90))
		else CFrame.Angles(0, math.rad(90), 0)
	return {
		name = name,
		size = Vector3.new(length, diameter, diameter),
		cframe = CFrame.new(x, y, z) * turn,
		role = role,
		material = material,
		shape = "Cylinder",
	}
end

local function ball(name: string, diameter: number, x: number, y: number, z: number, role: Role): PartSpec
	return {
		name = name,
		size = Vector3.new(diameter, diameter, diameter),
		cframe = CFrame.new(x, y, z),
		role = role,
		shape = "Ball",
	}
end

-- Position de la main le long de l'arme (voir `gripOffset` dans Config/Visuals).
local function handZ(itemId: string): number
	return -Visuals.weapons[itemId].gripOffset.Position.Z
end

-- Poignée d'une arme à distance, sous le corps, dans la main.
local function grip(itemId: string): PartSpec
	return box("Grip", 0.24, 0.62, 0.3, 0, -0.36, handZ(itemId) + 0.05, "dark", nil, CFrame.Angles(-0.25, 0, 0))
end

local function emitter(length: number, size: number?): PartSpec
	local s = size or 0.14
	return box("Emitter", s, s, 0.06, 0, 0, -length / 2 - 0.02, "accent")
end

-- Armes à distance -----------------------------------------------------------------

local blueprints: { [string]: () -> Blueprint } = {}

local function ranged(itemId: string, theme: Theme, build: (length: number, core: Vector3) -> { PartSpec })
	blueprints[itemId] = function(): Blueprint
		local core = Visuals.weapons[itemId].size
		local parts: { PartSpec } = { box("Body", core.X, core.Y, core.Z, 0, 0, 0, "body") }
		for _, part in build(core.Z, core) do
			table.insert(parts, part)
		end
		table.insert(parts, grip(itemId))
		return { theme = theme, accent = Config.Cells[Config.Weapons.ranged[itemId].cell].color, parts = parts }
	end
end

-- Pistolet laser fait maison : bloc rouillé, cellule apparente, ruban adhésif.
ranged("scrap_laser_pistol", "scrap", function(length)
	return {
		box("Receiver", 0.3, 0.4, 0.8, 0, 0.06, 0.2, "plate"),
		box("Cell", 0.18, 0.3, 0.24, 0, -0.28, 0.05, "accent"),
		box("Tape", 0.33, 0.43, 0.1, 0, 0.06, -0.12, "tape"),
		box("Sight", 0.06, 0.1, 0.12, 0, 0.3, 0.45, "dark"),
		emitter(length),
	}
end)

-- Pistolet « Vigil » : glissière d'acier nette, liseré lumineux.
ranged("vigil_pistol", "military", function(length)
	return {
		box("Slide", 0.3, 0.38, 1.25, 0, 0.05, 0.1, "plate"),
		box("Rail", 0.12, 0.06, 0.9, 0, 0.27, 0.15, "dark"),
		box("Line", 0.32, 0.05, 0.7, 0, -0.02, -0.05, "accent"),
		box("Cell", 0.2, 0.12, 0.26, 0, -0.7, handZ("vigil_pistol") + 0.12, "accent"),
		emitter(length),
	}
end)

-- La Grésilleuse : mitraillette à arc, fourche à la bouche, chargeur vertical.
ranged("crackler", "scrap", function(length)
	return {
		box("Receiver", 0.34, 0.5, 1.1, 0, 0.04, 0.25, "plate"),
		box("Magazine", 0.2, 0.7, 0.26, 0, -0.5, -0.1, "accent"),
		box("Stock", 0.08, 0.3, 0.7, 0, -0.02, length / 2 + 0.3, "dark"),
		box("ProngL", 0.06, 0.06, 0.5, -0.14, 0, -length / 2 + 0.2, "steel"),
		box("ProngR", 0.06, 0.06, 0.5, 0.14, 0, -length / 2 + 0.2, "steel"),
		box("Arc", 0.22, 0.05, 0.05, 0, 0, -length / 2 - 0.04, "accent"),
		box("Coil", 0.3, 0.3, 0.06, 0, 0, -0.6, "accent"),
		box("Tape", 0.36, 0.52, 0.1, 0, 0.04, 0.6, "tape"),
	}
end)

-- Fusil de Sentinelle reconverti : acier d'AXIOM, garde-main sombre, chargeur cyan.
ranged("sentinel_rifle", "military", function(length)
	return {
		box("Receiver", 0.34, 0.55, 1.2, 0, 0.05, 0.55, "plate"),
		box("Stock", 0.28, 0.42, 0.7, 0, -0.06, length / 2 + 0.25, "plate"),
		box("Handguard", 0.38, 0.42, 1.1, 0, 0, -0.75, "dark"),
		box("Magazine", 0.22, 0.65, 0.34, 0, -0.55, 0.45, "accent"),
		box("Rail", 0.1, 0.08, 1.2, 0, 0.35, 0.4, "dark"),
		box("FrontSight", 0.06, 0.16, 0.06, 0, 0.3, -1.2, "dark"),
		box("Line", 0.4, 0.05, 0.5, 0, 0.06, -0.75, "accent"),
		emitter(length),
	}
end)

-- Brise-Carcasse : gros canon rouillé, pompe, anneau de plasma à la bouche.
ranged("hullbreaker", "scrap", function(length)
	return {
		rod("Shroud", 0.5, 1.5, 0, 0, -0.65, "plate"),
		box("Pump", 0.56, 0.36, 0.6, 0, -0.24, -0.7, "dark"),
		box("Receiver", 0.4, 0.5, 0.9, 0, 0.02, 0.55, "plate"),
		box("Stock", 0.3, 0.44, 0.7, 0, -0.06, length / 2 + 0.25, "plate"),
		box("Cell", 0.42, 0.12, 0.5, 0, 0.3, 0.55, "accent"),
		rod("MuzzleRing", 0.58, 0.08, 0, 0, -length / 2 + 0.04, "accent"),
		box("Tape", 0.32, 0.46, 0.12, 0, -0.06, length / 2 + 0.05, "tape"),
	}
end)

-- Lance-clous magnétique : outil de chantier, rails et bobines, barillet de clous.
ranged("mag_nailer", "scrap", function(length)
	return {
		box("Housing", 0.5, 0.7, 1.0, 0, -0.05, 0.7, "plate"),
		box("RailL", 0.08, 0.12, 1.5, -0.16, 0, -0.55, "dark"),
		box("RailR", 0.08, 0.12, 1.5, 0.16, 0, -0.55, "dark"),
		box("Coil1", 0.46, 0.34, 0.08, 0, 0, -0.2, "accent"),
		box("Coil2", 0.46, 0.34, 0.08, 0, 0, -0.6, "accent"),
		box("Coil3", 0.46, 0.34, 0.08, 0, 0, -1.0, "accent"),
		rod("Drum", 0.6, 0.4, 0, -0.45, 0.35, "steel", "x"),
		box("Handle", 0.1, 0.14, 0.7, 0, 0.45, 0.7, "dark"),
		box("Tape", 0.52, 0.72, 0.12, 0, -0.05, 0.3, "tape"),
		box("Tip", 0.1, 0.1, 0.1, 0, 0, -length / 2, "steel"),
	}
end)

-- L'Aiguille : carabine à rail, deux rails séparés par un trait blanc, lunette.
ranged("needle", "military", function(length)
	return {
		box("RailTop", 0.08, 0.14, 3.0, 0, 0.14, -0.6, "plate"),
		box("RailBottom", 0.08, 0.14, 3.0, 0, -0.14, -0.6, "plate"),
		box("Charge", 0.05, 0.08, 2.9, 0, 0, -0.6, "accent"),
		box("Receiver", 0.3, 0.5, 1.0, 0, 0, 1.3, "plate"),
		rod("Scope", 0.26, 1.0, 0, 0.45, 0.9, "dark"),
		rod("Lens", 0.22, 0.04, 0, 0.45, 0.39, "accent"),
		box("Stock", 0.2, 0.4, 0.6, 0, -0.06, length / 2 + 0.2, "dark"),
		box("Cell", 0.2, 0.4, 0.3, 0, -0.42, 1.0, "accent"),
		box("BipodL", 0.06, 0.6, 0.06, -0.14, -0.4, -1.3, "dark", nil, CFrame.Angles(0, 0, -0.35)),
		box("BipodR", 0.06, 0.6, 0.06, 0.14, -0.4, -1.3, "dark", nil, CFrame.Angles(0, 0, 0.35)),
	}
end)

-- Mitrailleuse de Bastion arrachée : trois canons, bloc moteur, tambour, évents rouges.
ranged("bastion_minigun", "axiom", function(length)
	return {
		rod("Barrel1", 0.2, 1.9, 0, 0.22, -0.75, "steel"),
		rod("Barrel2", 0.2, 1.9, -0.19, -0.11, -0.75, "steel"),
		rod("Barrel3", 0.2, 1.9, 0.19, -0.11, -0.75, "steel"),
		rod("ClampFront", 0.7, 0.12, 0, 0, -1.5, "dark"),
		rod("ClampRear", 0.7, 0.12, 0, 0, -0.4, "dark"),
		box("Motor", 0.8, 0.85, 1.3, 0, 0, 0.85, "plate"),
		rod("Drum", 0.9, 0.5, 0.6, -0.1, 0.8, "dark", "x"),
		rod("DrumHub", 0.3, 0.54, 0.6, -0.1, 0.8, "accent", "x"),
		box("Handle", 0.12, 0.14, 0.9, 0, 0.62, 0.5, "dark"),
		box("Vent1", 0.84, 0.05, 0.12, 0, 0.12, 0.5, "accent"),
		box("Vent2", 0.84, 0.05, 0.12, 0, 0.12, 0.85, "accent"),
		box("Vent3", 0.84, 0.05, 0.12, 0, 0.12, 1.2, "accent"),
		box("Tip", 0.1, 0.1, 0.06, 0, 0, -length / 2, "dark"),
	}
end)

-- Canon à rayons X modifié : tube émetteur, lentille, ailettes de refroidissement.
ranged("xray_cannon", "axiom", function(length)
	return {
		rod("Tube", 0.6, 1.5, 0, 0, -0.7, "plate"),
		rod("Lens", 0.5, 0.06, 0, 0, -length / 2 + 0.04, "accent"),
		rod("RingFront", 0.74, 0.1, 0, 0, -0.9, "dark"),
		rod("RingRear", 0.74, 0.1, 0, 0, -0.3, "dark"),
		box("PowerPack", 0.75, 0.8, 1.1, 0, 0, 0.85, "plate"),
		box("Fin1", 0.9, 0.5, 0.06, 0, 0.05, 0.55, "dark"),
		box("Fin2", 0.9, 0.5, 0.06, 0, 0.05, 0.85, "dark"),
		box("Fin3", 0.9, 0.5, 0.06, 0, 0.05, 1.15, "dark"),
		box("Cell", 0.3, 0.3, 0.5, 0, 0.5, 0.9, "accent"),
		rod("Cable", 0.1, 1.0, 0.36, -0.3, 0.1, "dark"),
	}
end)

-- Court-Circuit : lance-grenades IEM, tube large, barillet, grenade visible.
ranged("short_circuit", "military", function(length)
	return {
		rod("Tube", 0.66, 1.5, 0, 0, -0.55, "plate"),
		rod("Cylinder", 0.95, 0.5, 0, 0, 0.4, "dark"),
		rod("CylinderBand", 0.98, 0.08, 0, 0, 0.4, "accent"),
		box("Stock", 0.3, 0.4, 0.7, 0, -0.06, length / 2 + 0.25, "plate"),
		box("ForeGrip", 0.2, 0.5, 0.2, 0, -0.5, -0.5, "dark"),
		ball("Grenade", 0.4, 0, 0, -length / 2 + 0.1, "accent"),
		box("Sight", 0.06, 0.4, 0.06, 0, 0.5, -0.2, "dark"),
	}
end)

-- Armes de mêlée --------------------------------------------------------------------
-- Le manche est à l'arrière (+Z), la tête de l'arme à l'avant.

local function melee(
	itemId: string,
	theme: Theme,
	accent: Color3,
	build: (length: number, core: Vector3) -> { PartSpec }
)
	blueprints[itemId] = function(): Blueprint
		local core = Visuals.weapons[itemId].size
		local parts: { PartSpec } = { box("Body", core.X, core.Y, core.Z, 0, 0, 0, "body") }
		for _, part in build(core.Z, core) do
			table.insert(parts, part)
		end
		return { theme = theme, accent = accent, parts = parts }
	end
end

-- Barre à mine électrifiée : pied-de-biche, bobines, batterie scotchée.
melee("shock_crowbar", "scrap", CYAN, function(length)
	local tip = -length / 2
	return {
		box("Handle", 0.22, 0.22, 0.9, 0, 0, length / 2 - 0.5, "tape"),
		box("Hook", 0.16, 0.5, 0.16, 0, 0.2, tip + 0.05, "plate"),
		box("Claw", 0.16, 0.14, 0.4, 0, 0.42, tip + 0.2, "plate"),
		box("Coil1", 0.26, 0.26, 0.06, 0, 0, tip + 0.4, "accent"),
		box("Coil2", 0.26, 0.26, 0.06, 0, 0, tip + 0.7, "accent"),
		box("Coil3", 0.26, 0.26, 0.06, 0, 0, tip + 1.0, "accent"),
		box("Battery", 0.3, 0.3, 0.4, 0, -0.2, 0.4, "plate"),
		box("BatteryLight", 0.32, 0.08, 0.2, 0, -0.2, 0.4, "accent"),
	}
end)

-- Sabre laser de fortune : garde bricolée, lame de lumière.
melee("laser_saber", "scrap", MAGENTA, function(length)
	return {
		rod("Hilt", 0.26, 0.9, 0, 0, length / 2 - 0.5, "plate"),
		rod("Guard", 0.5, 0.08, 0, 0, length / 2 - 1.0, "dark"),
		rod("Pommel", 0.32, 0.12, 0, 0, length / 2 - 0.02, "steel"),
		box("Blade", 0.14, 0.14, length - 1.1, 0, 0, -0.55, "accent"),
		rod("Tape1", 0.28, 0.12, 0, 0, length / 2 - 0.35, "tape"),
		rod("Tape2", 0.28, 0.12, 0, 0, length / 2 - 0.7, "tape"),
	}
end)

-- Marteau hydraulique : tête massive, vérin orange, contrepoids.
melee("hydraulic_hammer", "military", ORANGE, function(length)
	local head = -length / 2 + 0.38
	return {
		box("Head", 0.9, 0.9, 0.75, 0, 0, head, "plate"),
		box("Face", 0.7, 0.7, 0.1, 0, 0, head - 0.42, "dark"),
		rod("Piston", 0.3, 0.6, 0, 0.6, head, "steel"),
		rod("PistonRing", 0.36, 0.14, 0, 0.6, head, "accent"),
		box("Hose", 0.08, 0.08, 1.0, 0.12, 0.2, head + 0.8, "dark"),
		box("Counterweight", 0.4, 0.4, 0.3, 0, 0, length / 2 - 0.1, "plate"),
		box("Handle", 0.26, 0.26, 0.9, 0, 0, length / 2 - 0.75, "tape"),
	}
end)

-- Gantelet à impulsion : poing blindé, émetteur frontal, vérins.
melee("pulse_gauntlet", "military", CYAN, function(length)
	return {
		box("Knuckles", 0.78, 0.4, 0.3, 0, 0.05, -length / 2, "plate"),
		rod("Emitter", 0.42, 0.06, 0, 0, -length / 2 - 0.17, "accent"),
		box("Brace", 0.6, 0.6, 0.6, 0, 0, length / 2 + 0.25, "plate"),
		rod("PistonL", 0.12, 0.7, -0.4, 0.1, 0.2, "steel"),
		rod("PistonR", 0.12, 0.7, 0.4, 0.1, 0.2, "steel"),
		box("Strip", 0.72, 0.06, 0.5, 0, 0.36, 0, "accent"),
	}
end)

-- Lame vibrante d'Exécuteur : acier noir d'AXIOM, fil rouge.
melee("vibro_blade", "axiom", RED, function(length)
	return {
		rod("Hilt", 0.24, 0.8, 0, 0, length / 2 - 0.45, "dark"),
		box("Guard", 0.5, 0.12, 0.12, 0, 0, length / 2 - 0.9, "plate"),
		box("Blade", 0.07, 0.4, length - 1.0, 0, 0, -0.5, "plate"),
		box("Edge", 0.08, 0.05, length - 1.0, 0, -0.2, -0.5, "accent"),
		box("Spine", 0.09, 0.08, 0.6, 0, 0.2, 0.2, "steel"),
	}
end)

-- Armures, sacs, gadgets, consommables, cellules ------------------------------------------

local function simple(itemId: string, theme: Theme, accent: Color3, parts: { PartSpec })
	blueprints[itemId] = function(): Blueprint
		return { theme = theme, accent = accent, parts = parts }
	end
end

simple("helmet", "military", CYAN, {
	box("Body", 1.25, 0.8, 1.3, 0, 0.15, 0, "body"),
	box("Brim", 1.32, 0.3, 1.36, 0, -0.3, 0, "plate"),
	box("Visor", 1.0, 0.28, 0.1, 0, 0, -0.66, "glass"),
	box("Ridge", 0.2, 0.12, 1.0, 0, 0.6, 0, "dark"),
	box("EarL", 0.1, 0.4, 0.4, -0.66, -0.05, 0.1, "dark"),
	box("EarR", 0.1, 0.4, 0.4, 0.66, -0.05, 0.1, "dark"),
	box("Lamp", 0.14, 0.12, 0.08, 0.42, 0.34, -0.66, "accent"),
})

-- Gilet : il enveloppe le torse (porté, il est mis à l'échelle du personnage). Le
-- disque cyan sur la poitrine est l'émetteur du bouclier.
simple("vest", "military", CYAN, {
	box("Body", 2.1, 1.5, 1.15, 0, 0, 0, "body", "Fabric"),
	box("ChestPlate", 1.5, 1.0, 0.14, 0, 0.05, -0.62, "plate"),
	box("BackPlate", 1.5, 1.0, 0.14, 0, 0.05, 0.62, "plate"),
	rod("ShieldEmitter", 0.4, 0.08, 0, 0.2, -0.71, "accent"),
	box("StrapL", 0.4, 0.3, 1.2, -0.7, 0.85, 0, "dark"),
	box("StrapR", 0.4, 0.3, 1.2, 0.7, 0.85, 0, "dark"),
	box("PouchL", 0.4, 0.4, 0.22, -0.6, -0.45, -0.68, "dark", "Fabric"),
	box("PouchR", 0.4, 0.4, 0.22, 0.6, -0.45, -0.68, "dark", "Fabric"),
})

local function backpack(itemId: string, w: number, h: number, d: number, roll: boolean)
	local parts: { PartSpec } = {
		box("Body", w, h, d, 0, 0, 0, "body", "Fabric"),
		box("Flap", w + 0.06, h * 0.3, d + 0.06, 0, h * 0.36, 0, "plate"),
		-- La face avant de l'objet regarde vers -Z, comme pour les armes.
		box("Pocket", w * 0.6, h * 0.36, 0.2, 0, -h * 0.18, -d / 2 - 0.1, "dark", "Fabric"),
		box("StrapL", 0.14, h * 0.9, 0.08, -w * 0.3, 0, d / 2 + 0.04, "dark"),
		box("StrapR", 0.14, h * 0.9, 0.08, w * 0.3, 0, d / 2 + 0.04, "dark"),
		box("Tag", 0.3, 0.1, 0.04, w * 0.25, h * 0.1, -d / 2 - 0.22, "accent"),
	}
	if roll then
		table.insert(parts, rod("Bedroll", 0.5, w + 0.2, 0, h / 2 + 0.25, 0, "tape", "x", "Fabric"))
	end
	simple(itemId, "scrap", ORANGE, parts)
end
backpack("backpack_small", 1.2, 1.3, 0.6, false)
backpack("backpack_medium", 1.5, 1.6, 0.75, false)
backpack("backpack_large", 1.8, 2.0, 0.9, true)

-- Gadgets : outils orange (la couleur des alertes et de l'équipement de terrain).
-- Bottes de saut : une botte de chaque côté (x < 0 : gauche), propulseur sous la semelle.
simple("jump_boots", "military", ORANGE, {
	box("Body", 0.5, 0.3, 0.56, -0.4, 0, 0, "body"),
	box("ShaftL", 0.5, 0.5, 0.42, -0.4, 0.36, 0.08, "plate"),
	box("ThrusterL", 0.42, 0.06, 0.44, -0.4, -0.18, 0, "accent"),
	box("BootR", 0.5, 0.3, 0.56, 0.4, 0, 0, "body"),
	box("ShaftR", 0.5, 0.5, 0.42, 0.4, 0.36, 0.08, "plate"),
	box("ThrusterR", 0.42, 0.06, 0.44, 0.4, -0.18, 0, "accent"),
})

simple("grappling_hook", "scrap", ORANGE, {
	box("Body", 0.3, 0.4, 1.0, 0, 0, 0, "body"),
	rod("Spool", 0.6, 0.3, 0, -0.1, 0.3, "plate", "x"),
	rod("SpoolHub", 0.22, 0.34, 0, -0.1, 0.3, "accent", "x"),
	box("Grip", 0.24, 0.5, 0.26, 0, -0.4, 0.35, "dark"),
	box("ClawTop", 0.08, 0.4, 0.08, 0, 0.16, -0.62, "steel", nil, CFrame.Angles(0.6, 0, 0)),
	box("ClawL", 0.08, 0.4, 0.08, -0.14, -0.1, -0.62, "steel", nil, CFrame.Angles(-0.4, 0, 0.6)),
	box("ClawR", 0.08, 0.4, 0.08, 0.14, -0.1, -0.62, "steel", nil, CFrame.Angles(-0.4, 0, -0.6)),
})

simple("recon_drone", "military", ORANGE, {
	box("Body", 0.8, 0.36, 0.8, 0, 0, 0, "body"),
	rod("RotorFL", 0.6, 0.05, -0.6, 0.2, -0.6, "dark", "y"),
	rod("RotorFR", 0.6, 0.05, 0.6, 0.2, -0.6, "dark", "y"),
	rod("RotorBL", 0.6, 0.05, -0.6, 0.2, 0.6, "dark", "y"),
	rod("RotorBR", 0.6, 0.05, 0.6, 0.2, 0.6, "dark", "y"),
	box("ArmA", 1.7, 0.08, 0.1, 0, 0.12, 0, "plate", nil, CFrame.Angles(0, math.rad(45), 0)),
	box("ArmB", 1.7, 0.08, 0.1, 0, 0.12, 0, "plate", nil, CFrame.Angles(0, math.rad(-45), 0)),
	ball("Eye", 0.3, 0, -0.1, -0.4, "accent"),
})

simple("deployable_wall", "military", ORANGE, {
	box("Body", 1.5, 1.0, 0.14, 0, 0, 0, "body"),
	box("PanelB", 1.5, 1.0, 0.14, 0.08, 0.06, 0.18, "plate"),
	box("PanelC", 1.5, 1.0, 0.14, 0.16, 0.12, 0.36, "plate"),
	box("Handle", 0.5, 0.1, 0.1, 0, 0.58, 0, "dark"),
	box("Stripe", 1.52, 0.1, 0.04, 0, -0.3, -0.08, "accent"),
})

simple("smoke_deployer", "scrap", ORANGE, {
	rod("Body", 0.6, 1.1, 0, 0, 0, "body", "y"),
	rod("Cap", 0.5, 0.2, 0, 0.62, 0, "dark", "y"),
	rod("Band", 0.63, 0.16, 0, 0.1, 0, "accent", "y"),
	box("Nozzle", 0.14, 0.14, 0.3, 0, 0.68, -0.2, "steel"),
	box("Lever", 0.08, 0.5, 0.1, 0.34, 0.35, 0, "steel"),
})

-- Consommables : la couleur dit l'effet (vert = soin, cyan = bouclier, orange = vitesse).
simple("nanite_injector", "military", GREEN, {
	rod("Body", 0.3, 0.9, 0, 0, 0, "glass", "y"),
	rod("Nanites", 0.2, 0.7, 0, -0.04, 0, "accent", "y"),
	rod("Plunger", 0.36, 0.14, 0, 0.55, 0, "dark", "y"),
	rod("Collar", 0.36, 0.1, 0, -0.44, 0, "steel", "y"),
	rod("Needle", 0.05, 0.4, 0, -0.68, 0, "steel", "y"),
})

simple("shield_battery", "military", CYAN, {
	box("Body", 0.6, 0.9, 0.4, 0, 0, 0, "body"),
	box("Window", 0.4, 0.5, 0.05, 0, -0.05, -0.2, "accent"),
	box("TerminalL", 0.12, 0.14, 0.12, -0.16, 0.5, 0, "steel"),
	box("TerminalR", 0.12, 0.14, 0.12, 0.16, 0.5, 0, "steel"),
	box("Band", 0.62, 0.08, 0.42, 0, 0.3, 0, "dark"),
})

simple("overdrive", "scrap", ORANGE, {
	rod("Body", 0.45, 0.8, 0, 0, 0, "body", "y"),
	rod("Band", 0.48, 0.2, 0, 0.05, 0, "accent", "y"),
	rod("Cap", 0.3, 0.2, 0, 0.5, 0, "dark", "y"),
	rod("Tip", 0.1, 0.24, 0, -0.5, 0, "steel", "y"),
})

simple("exo_harness", "military", WHITE, {
	box("Body", 0.14, 1.4, 0.14, -0.4, 0, 0, "body"),
	box("BarR", 0.14, 1.4, 0.14, 0.4, 0, 0, "body"),
	box("Cross", 0.94, 0.14, 0.14, 0, 0.3, 0, "plate"),
	box("Belt", 1.1, 0.2, 0.3, 0, -0.5, 0, "dark"),
	ball("NodeL", 0.26, -0.4, 0.7, 0, "accent"),
	ball("NodeR", 0.26, 0.4, 0.7, 0, "accent"),
})

-- Cellules : le même boîtier, le cœur à la couleur du type.
for id, cell in Config.Cells :: { [string]: any } do
	simple(id, "military", cell.color, {
		box("Body", 0.5, 0.7, 0.5, 0, 0, 0, "dark"),
		box("Core", 0.36, 0.5, 0.54, 0, 0, 0, "accent"),
		box("CapTop", 0.54, 0.1, 0.54, 0, 0.36, 0, "steel"),
		box("CapBottom", 0.54, 0.1, 0.54, 0, -0.36, 0, "steel"),
		box("Contact", 0.16, 0.1, 0.16, 0, 0.46, 0, "steel"),
	})
end

-- Module de calibration : une puce dorée (la couleur de l'état Neuf).
simple("calibration_module", "axiom", GOLD, {
	box("Body", 0.9, 0.1, 0.9, 0, 0, 0, "dark"),
	box("Core", 0.4, 0.16, 0.4, 0, 0.06, 0, "accent"),
	box("PinsL", 0.06, 0.06, 0.7, -0.48, -0.02, 0, "steel"),
	box("PinsR", 0.06, 0.06, 0.7, 0.48, -0.02, 0, "steel"),
	box("Trace", 0.7, 0.03, 0.05, 0, 0.06, 0.3, "accent"),
})

-- API -----------------------------------------------------------------------------------

-- Description d'un objet (nil si l'objet n'a pas d'apparence définie).
function ItemModels.blueprint(itemId: string): Blueprint?
	local make = blueprints[itemId]
	return if make then make() else nil
end

function ItemModels.has(itemId: string): boolean
	return blueprints[itemId] ~= nil
end

-- Couleur et matière d'une pièce selon son rôle, le thème de l'objet et le skin éventuel.
function ItemModels.appearance(blueprint: Blueprint, part: PartSpec, skin: Skin?): (Color3, string)
	local role = part.role
	if role == "accent" then
		return if skin then skin.accent else blueprint.accent, "Neon"
	elseif role == "body" then
		if skin then
			return skin.color, skin.material
		end
		return Visuals.bodyColor, part.material or "Metal"
	elseif role == "plate" then
		if skin then
			-- La pièce secondaire suit le skin, un ton plus sombre.
			return skin.color:Lerp(Color3.new(), 0.25), skin.material
		end
		local plate = PLATE[blueprint.theme]
		return plate.color, part.material or plate.material
	elseif role == "tape" then
		return TAPE, part.material or "Fabric"
	elseif role == "glass" then
		return GLASS, "Glass"
	elseif role == "steel" then
		return STEEL, part.material or "Metal"
	end
	return DARK, part.material or "SmoothPlastic"
end

export type PlaceOptions = {
	skin: Skin?,
	scale: number?, -- échelle uniforme (objet porté : à la taille du personnage)
	weldTo: BasePart?, -- soude les pièces à cette pièce (sinon elles sont ancrées)
	filter: ((spec: PartSpec) -> boolean)?, -- ne poser qu'une partie des pièces (une botte)
	shift: Vector3?, -- décalage appliqué avant l'échelle (recentrer une botte sur son pied)
}

local function makePart(blueprint: Blueprint, spec: PartSpec, skin: Skin?, scale: number): Part
	local part = Instance.new("Part")
	part.Name = spec.name
	if spec.shape == "Cylinder" then
		part.Shape = Enum.PartType.Cylinder
	elseif spec.shape == "Ball" then
		part.Shape = Enum.PartType.Ball
	end
	part.Size = spec.size * scale
	local color, material = ItemModels.appearance(blueprint, spec, skin)
	part.Color = color
	local ok, item = pcall(function()
		return (Enum.Material :: any)[material]
	end)
	part.Material = if ok and item then item else Enum.Material.Metal
	if spec.role == "glass" then
		part.Transparency = 0.35
	end
	-- Décoratif : ni collision, ni rayons, ni masse.
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

--[[
	Pose les pièces d'un objet sous `parent`, l'origine de l'objet en `cframe`
	(objet porté, gadget déployé, butin au sol). Retourne les pièces créées
	(liste vide si l'objet n'a pas de modèle).
]]
function ItemModels.place(itemId: string, parent: Instance, cframe: CFrame, options: PlaceOptions?): { BasePart }
	local blueprint = ItemModels.blueprint(itemId)
	local created: { BasePart } = {}
	if blueprint == nil then
		return created
	end
	local opts: PlaceOptions = options or {}
	local scale = opts.scale or 1
	local shift = opts.shift or Vector3.zero
	for _, spec in blueprint.parts do
		if opts.filter == nil or opts.filter(spec) then
			local part = makePart(blueprint, spec, opts.skin, scale)
			local localFrame = spec.cframe.Rotation + (spec.cframe.Position + shift) * scale
			part.CFrame = cframe * localFrame
			local weldTo = opts.weldTo
			if weldTo then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = weldTo
				weld.Part1 = part
				weld.Parent = part
				part.Anchored = false
			end
			part.Parent = parent
			table.insert(created, part)
		end
	end
	return created
end

--[[
	Crée le modèle d'un objet (pièce « Body » à l'origine, PrimaryPart), pièces ancrées :
	vignettes et aperçus.
]]
function ItemModels.build(itemId: string, skin: Skin?): Model?
	if not ItemModels.has(itemId) then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = itemId
	ItemModels.place(itemId, model, CFrame.new(), { skin = skin })
	local body = model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		model.PrimaryPart = body
	end
	return model
end

-- Dimensions de l'objet (pour cadrer une icône) : centre et taille de la boîte englobante.
function ItemModels.bounds(blueprint: Blueprint): (Vector3, Vector3)
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for _, spec in blueprint.parts do
		local cf, size = spec.cframe, spec.size
		local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
		local extent = Vector3.new(
			math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z,
			math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z,
			math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z
		) / 2
		local low, high = cf.Position - extent, cf.Position + extent
		minX, minY, minZ = math.min(minX, low.X), math.min(minY, low.Y), math.min(minZ, low.Z)
		maxX, maxY, maxZ = math.max(maxX, high.X), math.max(maxY, high.Y), math.max(maxZ, high.Z)
	end
	local min, max = Vector3.new(minX, minY, minZ), Vector3.new(maxX, maxY, maxZ)
	return (min + max) / 2, max - min
end

return ItemModels
