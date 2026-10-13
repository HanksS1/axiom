--!strict
--[[
	Visuels des armes : dimensions du « cœur » de chaque arme, prise en main
	et couleur d'accent. La silhouette complète (carcasse, chargeur, crosse…)
	est décrite dans Shared/Visuals/ItemModels, autour de ce cœur.

	- `size` : cœur de l'arme (pièce « Body »). Sa longueur (Z) est celle de
	  l'arme : la bouche est à l'avant du cœur (tracés des tirs).
	- `gripOffset` : position du cœur par rapport à la main droite.
	- `accent` : arme à distance = couleur de sa cellule (le tracé du tir a la
	  même couleur) ; mêlée = couleur propre à l'arme.
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)
local Cells = require(script.Parent.Cells)

export type WeaponShape = {
	size: Vector3, -- cœur de l'arme
	accent: Color3, -- néon
	gripOffset: CFrame, -- position relative à la main droite
}

local CYAN = Color3.fromRGB(0, 229, 255)
local ORANGE = Color3.fromRGB(255, 138, 0)
local MAGENTA = Color3.fromRGB(255, 46, 196)
local RED = Color3.fromRGB(255, 59, 59)

local LIGHT = Cells.cell_light.color
local STANDARD = Cells.cell_standard.color
local PRECISION = Cells.cell_precision.color
local HEAVY = Cells.cell_heavy.color

-- Arme à distance : le cœur passe au-dessus de la main, qui tient la poignée à
-- `back` studs de son centre.
local function held(back: number): CFrame
	return CFrame.new(0, 0.25, -back)
end

-- Arme de mêlée : tenue par l'arrière du manche, tête relevée vers l'avant.
local function raised(length: number): CFrame
	return CFrame.Angles(math.rad(55), 0, 0) * CFrame.new(0, 0, -(length / 2 - 0.5))
end

local weapons: { [string]: WeaponShape } = {
	scrap_laser_pistol = { size = Vector3.new(0.2, 0.24, 1.3), accent = LIGHT, gripOffset = held(0.4) },
	vigil_pistol = { size = Vector3.new(0.2, 0.24, 1.5), accent = LIGHT, gripOffset = held(0.45) },
	crackler = { size = Vector3.new(0.22, 0.26, 2.2), accent = LIGHT, gripOffset = held(0.6) },
	sentinel_rifle = { size = Vector3.new(0.22, 0.26, 3.2), accent = STANDARD, gripOffset = held(1.1) },
	hullbreaker = { size = Vector3.new(0.3, 0.34, 2.8), accent = STANDARD, gripOffset = held(1.0) },
	mag_nailer = { size = Vector3.new(0.14, 0.14, 2.6), accent = STANDARD, gripOffset = held(0.95) },
	needle = { size = Vector3.new(0.04, 0.05, 4.2), accent = PRECISION, gripOffset = held(1.5) },
	bastion_minigun = { size = Vector3.new(0.3, 0.3, 3.4), accent = HEAVY, gripOffset = held(1.2) },
	xray_cannon = { size = Vector3.new(0.3, 0.3, 3.0), accent = HEAVY, gripOffset = held(1.1) },
	short_circuit = { size = Vector3.new(0.3, 0.3, 2.6), accent = HEAVY, gripOffset = held(1.0) },
	shock_crowbar = { size = Vector3.new(0.16, 0.16, 3.2), accent = CYAN, gripOffset = raised(3.2) },
	laser_saber = { size = Vector3.new(0.06, 0.06, 3.6), accent = MAGENTA, gripOffset = raised(3.6) },
	hydraulic_hammer = { size = Vector3.new(0.2, 0.2, 3.6), accent = ORANGE, gripOffset = raised(3.6) },
	pulse_gauntlet = { size = Vector3.new(0.7, 0.7, 0.9), accent = CYAN, gripOffset = CFrame.new(0, -0.2, 0) },
	vibro_blade = { size = Vector3.new(0.08, 0.2, 3.4), accent = RED, gripOffset = raised(3.4) },
}

return Freeze.deep({
	weapons = weapons,
	bodyColor = Color3.fromRGB(46, 50, 58),

	tracer = {
		width = 0.08,
		beamWidth = 0.3, -- rayon continu (Canon à rayons X)
		lifetime = 0.06,
		color = STANDARD,
		robotColor = Color3.fromRGB(255, 40, 40),
	},

	disintegration = {
		voxelsPerPart = 5,
		voxelsPerPartMobile = 2,
		voxelSize = 0.35,
		riseSpeed = 6,
		spread = 4,
		colors = { CYAN, MAGENTA, ORANGE },
	},
})
