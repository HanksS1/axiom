--!strict
--[[
	Visuels provisoires (« greybox ») : formes simples en attendant les
	modèles 3D définitifs. Les couleurs reprennent la charte (section 17.1).
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

export type WeaponShape = {
	size: Vector3, -- corps de l'arme
	accent: Color3, -- bande néon
	gripOffset: CFrame, -- position relative à la main droite
}

local CYAN = Color3.fromRGB(0, 229, 255)
local ORANGE = Color3.fromRGB(255, 138, 0)
local MAGENTA = Color3.fromRGB(255, 46, 196)
local GREEN = Color3.fromRGB(57, 255, 20)

local HOLD = CFrame.new(0, -0.2, -0.6)
local MELEE_HOLD = CFrame.new(0, -0.3, -1.2) * CFrame.Angles(math.rad(-80), 0, 0)

local weapons: { [string]: WeaponShape } = {
	scrap_laser_pistol = { size = Vector3.new(0.3, 0.6, 1.3), accent = ORANGE, gripOffset = HOLD },
	vigil_pistol = { size = Vector3.new(0.3, 0.6, 1.5), accent = CYAN, gripOffset = HOLD },
	crackler = { size = Vector3.new(0.35, 0.7, 2.2), accent = CYAN, gripOffset = HOLD },
	sentinel_rifle = { size = Vector3.new(0.35, 0.7, 3.2), accent = CYAN, gripOffset = CFrame.new(0, -0.2, -1.2) },
	hullbreaker = { size = Vector3.new(0.45, 0.7, 2.8), accent = ORANGE, gripOffset = CFrame.new(0, -0.2, -1.1) },
	mag_nailer = { size = Vector3.new(0.4, 0.8, 2.6), accent = GREEN, gripOffset = CFrame.new(0, -0.2, -1.0) },
	needle = { size = Vector3.new(0.3, 0.6, 4.2), accent = Color3.new(1, 1, 1), gripOffset = CFrame.new(0, -0.2, -1.6) },
	bastion_minigun = {
		size = Vector3.new(0.8, 0.9, 3.4),
		accent = Color3.fromRGB(255, 59, 59),
		gripOffset = CFrame.new(0, -0.3, -1.2),
	},
	xray_cannon = { size = Vector3.new(0.7, 0.9, 3.0), accent = GREEN, gripOffset = CFrame.new(0, -0.3, -1.1) },
	short_circuit = { size = Vector3.new(0.7, 0.8, 2.6), accent = MAGENTA, gripOffset = CFrame.new(0, -0.3, -1.0) },
	shock_crowbar = { size = Vector3.new(0.2, 0.2, 3.2), accent = CYAN, gripOffset = MELEE_HOLD },
	laser_saber = { size = Vector3.new(0.15, 0.15, 3.6), accent = MAGENTA, gripOffset = MELEE_HOLD },
	hydraulic_hammer = { size = Vector3.new(0.3, 0.3, 3.6), accent = ORANGE, gripOffset = MELEE_HOLD },
	pulse_gauntlet = { size = Vector3.new(0.7, 0.7, 0.9), accent = CYAN, gripOffset = CFrame.new(0, -0.2, 0) },
	vibro_blade = { size = Vector3.new(0.12, 0.35, 3.4), accent = Color3.fromRGB(255, 59, 59), gripOffset = MELEE_HOLD },
}

return Freeze.deep({
	weapons = weapons,
	bodyColor = Color3.fromRGB(46, 50, 58),

	tracer = {
		width = 0.08,
		lifetime = 0.06,
		color = CYAN,
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
