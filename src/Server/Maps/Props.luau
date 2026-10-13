--!strict
--[[
	Props : bibliothèque de décors des cartes (épaves, mobilier, machines,
	rochers…). Chaque décor est décrit par quelques pièces simples posées dans
	son propre repère ; il déclare son emprise (`radius`, `height`) pour que
	LayoutBuilder vérifie qu'il ne recouvre ni repère, ni porte, ni autre décor.

	- Couverts légers (planches, tôle, verre, tissu) : tag « LightCover »
	  (traversés par le Canon à rayons X, section 6.6).
	- Lumières : `flicker` = néon défaillant ; `emergency` = reste allumée
	  pendant une coupure de courant (Noyau Zéro).
	- Les petites pièces purement décoratives n'ont ni collision ni blocage
	  des tirs (moins de travail pour la physique).
]]

local LayoutBuilder = require(script.Parent.LayoutBuilder)

type Builder = LayoutBuilder.Builder
type Rng = LayoutBuilder.Rng
type Options = LayoutBuilder.PartOptions

local C = LayoutBuilder.colors

local Props = {}

export type Prop = {
	radius: number,
	height: number,
	build: (b: Builder, cf: CFrame, rng: Rng) -> (),
}

local DARK = Color3.fromRGB(28, 30, 36)
local STEEL = Color3.fromRGB(104, 110, 120)
local WOOD = Color3.fromRGB(124, 92, 60)
local TARP = Color3.fromRGB(84, 96, 70)
local BONE = Color3.fromRGB(226, 220, 200)
local GLASS = Color3.fromRGB(150, 190, 205)
local WARM = Color3.fromRGB(255, 196, 120)
local FIRE = Color3.fromRGB(255, 140, 40)
local SCREEN = Color3.fromRGB(0, 229, 255)

local DECOR: Options = { collide = false, query = false }
local LIGHT_COVER: Options = { tags = { "LightCover" } }

local PAINT = {
	C.rust,
	Color3.fromRGB(70, 80, 96),
	Color3.fromRGB(120, 50, 44),
	Color3.fromRGB(150, 150, 146),
	Color3.fromRGB(40, 42, 48),
	Color3.fromRGB(64, 84, 60),
	Color3.fromRGB(150, 120, 50),
}

local function pick<T>(rng: Rng, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function with(base: Options, extra: Options): Options
	local merged = table.clone(base)
	for key, value in extra :: any do
		(merged :: any)[key] = value
	end
	return merged
end

local function light(color: Color3, range: number, brightness: number, flicker: boolean?, emergency: boolean?): Options
	return {
		light = { color = color, range = range, brightness = brightness, flicker = flicker, emergency = emergency },
	}
end

-- Boîte dans le repère du décor : (ox, oz) = centre, `oy` = BASE.
local function box(
	b: Builder,
	cf: CFrame,
	name: string,
	sx: number,
	sy: number,
	sz: number,
	ox: number,
	oy: number,
	oz: number,
	color: Color3,
	material: string,
	options: Options?,
	rotation: CFrame?
)
	local cframe = cf * CFrame.new(ox, oy + sy / 2, oz)
	if rotation then
		cframe *= rotation
	end
	return b:part(name, Vector3.new(sx, sy, sz), cframe, color, material, options)
end

-- Cylindre vertical (l'axe des cylindres Roblox est X).
local function tube(
	b: Builder,
	cf: CFrame,
	name: string,
	diameter: number,
	height: number,
	ox: number,
	oy: number,
	oz: number,
	color: Color3,
	material: string,
	options: Options?
)
	local opts = with(options or {}, { shape = "Cylinder" })
	return b:part(
		name,
		Vector3.new(height, diameter, diameter),
		cf * CFrame.new(ox, oy + height / 2, oz) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		material,
		opts
	)
end

-- Cylindre couché : le long de l'axe Z du décor (`alongX` : le long de X). `oy` = centre.
local function pipe(
	b: Builder,
	cf: CFrame,
	name: string,
	diameter: number,
	length: number,
	ox: number,
	oy: number,
	oz: number,
	color: Color3,
	material: string,
	options: Options?,
	alongX: boolean?
)
	local opts = with(options or {}, { shape = "Cylinder" })
	local cframe = cf * CFrame.new(ox, oy, oz)
	if not alongX then
		cframe *= CFrame.Angles(0, math.rad(90), 0)
	end
	return b:part(name, Vector3.new(length, diameter, diameter), cframe, color, material, opts)
end

local function ball(
	b: Builder,
	cf: CFrame,
	name: string,
	diameter: number,
	ox: number,
	oy: number,
	oz: number,
	color: Color3,
	material: string,
	options: Options?
)
	local opts = with(options or {}, { shape = "Ball" })
	return b:part(name, Vector3.new(diameter, diameter, diameter), cf * CFrame.new(ox, oy, oz), color, material, opts)
end

local function tilt(rng: Rng, amount: number): CFrame
	return CFrame.Angles(
		rng:NextNumber(-amount, amount),
		rng:NextNumber(0, math.pi * 2),
		rng:NextNumber(-amount, amount)
	)
end

local catalog: { [string]: Prop } = {}

-- Ville ---------------------------------------------------------------------------

local function wheels(b: Builder, cf: CFrame, halfWidth: number, halfLength: number, diameter: number, rng: Rng)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			-- Une roue sur six a disparu.
			if rng:NextNumber() > 0.16 then
				b:part(
					"Wheel",
					Vector3.new(1, diameter, diameter),
					cf * CFrame.new(sx * halfWidth, diameter / 2, sz * halfLength),
					DARK,
					"SmoothPlastic",
					{ shape = "Cylinder", collide = false, query = false }
				)
			end
		end
	end
end

catalog.car = {
	radius = 7.5,
	height = 4.4,
	build = function(b, cf, rng)
		local color = pick(rng, PAINT)
		box(b, cf, "CarBody", 6, 1.8, 13, 0, 0.9, 0, color, "CorrodedMetal")
		box(b, cf, "CarCabin", 5.4, 1.7, 6.2, 0, 2.7, 0.9, color, "CorrodedMetal")
		box(b, cf, "CarGlass", 5.5, 1.1, 5.2, 0, 3, 0.9, DARK, "Glass", DECOR)
		wheels(b, cf, 3, 4.2, 2.2, rng)
		if rng:NextNumber() < 0.08 then
			-- Un phare qui tient encore, et qui grésille.
			box(
				b,
				cf,
				"Headlight",
				0.8,
				0.5,
				0.2,
				1.9,
				1.5,
				-6.55,
				WARM,
				"Neon",
				with(DECOR, light(WARM, 14, 1.2, true))
			)
		end
	end,
}

catalog.van = {
	radius = 8.5,
	height = 6.6,
	build = function(b, cf, rng)
		local color = pick(rng, PAINT)
		box(b, cf, "VanBody", 6.4, 5, 10, 0, 1.2, 2, color, "CorrodedMetal")
		box(b, cf, "VanCab", 6.2, 3.6, 4.6, 0, 1.2, -5.2, color, "CorrodedMetal")
		box(b, cf, "VanGlass", 6.3, 1.4, 1.6, 0, 3.2, -6.4, DARK, "Glass", DECOR)
		wheels(b, cf, 3.2, 5, 2.4, rng)
	end,
}

catalog.bus = {
	radius = 16,
	height = 8.4,
	build = function(b, cf, rng)
		local color =
			pick(rng, { Color3.fromRGB(150, 120, 50), Color3.fromRGB(120, 50, 44), Color3.fromRGB(70, 80, 96) })
		box(b, cf, "BusBody", 8, 6.6, 30, 0, 1.4, 0, color, "CorrodedMetal")
		box(b, cf, "BusWindows", 8.15, 2, 26, 0, 4.6, 0, DARK, "Glass", DECOR)
		box(b, cf, "BusSkirt", 7.6, 1.4, 26, 0, 0, 0, DARK, "Metal", DECOR)
		box(b, cf, "BusSign", 5, 0.9, 0.2, 0, 6.7, -15.1, C.orange, "Neon", with(DECOR, light(C.orange, 12, 1, true)))
		wheels(b, cf, 4, 10, 3, rng)
	end,
}

catalog.barrier = {
	radius = 4.5,
	height = 3.2,
	build = function(b, cf)
		box(b, cf, "BarrierFoot", 2.4, 1, 8, 0, 0, 0, C.concrete, "Concrete")
		box(b, cf, "BarrierTop", 1.2, 2.1, 8, 0, 1, 0, C.concrete, "Concrete")
	end,
}

catalog.barrierRow = {
	radius = 13,
	height = 3.2,
	build = function(b, cf, rng)
		for index = -1, 1 do
			local offset = cf
				* CFrame.new(rng:NextNumber(-0.6, 0.6), 0, index * 8.6)
				* CFrame.Angles(0, rng:NextNumber(-0.12, 0.12), 0)
			box(b, offset, "BarrierFoot", 2.4, 1, 8, 0, 0, 0, C.concrete, "Concrete")
			box(b, offset, "BarrierTop", 1.2, 2.1, 8, 0, 1, 0, C.concrete, "Concrete")
		end
		box(b, cf, "BarrierStripe", 1.3, 0.5, 25, 0, 2.2, 0, C.orange, "Neon", DECOR)
	end,
}

local function lampPost(b: Builder, cf: CFrame, lit: boolean, flicker: boolean)
	box(b, cf, "LampFoot", 1.4, 1, 1.4, 0, 0, 0, DARK, "Metal")
	box(b, cf, "LampPole", 0.6, 15, 0.6, 0, 1, 0, DARK, "Metal")
	box(b, cf, "LampArm", 0.4, 0.4, 4.4, 0, 15.6, -2, DARK, "Metal", DECOR)
	if lit then
		box(b, cf, "LampHead", 1.4, 0.4, 2.2, 0, 15.2, -3.6, WARM, "Neon", with(DECOR, light(WARM, 34, 1.4, flicker)))
	else
		box(b, cf, "LampHead", 1.4, 0.4, 2.2, 0, 15.2, -3.6, DARK, "Glass", DECOR)
	end
end

catalog.lamp = {
	radius = 1.2,
	height = 17,
	build = function(b, cf, rng)
		lampPost(b, cf, true, rng:NextNumber() < 0.5)
	end,
}

catalog.lampDead = {
	radius = 2.4,
	height = 17,
	build = function(b, cf, rng)
		lampPost(b, cf * CFrame.Angles(rng:NextNumber(-0.14, 0.14), 0, rng:NextNumber(-0.14, 0.14)), false, false)
	end,
}

local function rubblePile(b: Builder, cf: CFrame, rng: Rng, count: number, spread: number, size: number, color: Color3)
	for index = 1, count do
		local sx, sy, sz =
			rng:NextNumber(size * 0.4, size), rng:NextNumber(size * 0.25, size * 0.6), rng:NextNumber(size * 0.4, size)
		b:part(
			"Rubble" .. index,
			Vector3.new(sx, sy, sz),
			cf
				* CFrame.new(rng:NextNumber(-spread, spread), sy * 0.4, rng:NextNumber(-spread, spread))
				* tilt(rng, 0.35),
			color,
			"Slate"
		)
	end
end

catalog.rubble = {
	radius = 6.5,
	height = 4.5,
	build = function(b, cf, rng)
		rubblePile(b, cf, rng, 5, 2.6, 6, C.darkConcrete)
		box(b, cf, "Rebar", 0.25, 5, 0.25, 0.8, 0.5, -0.6, C.rust, "CorrodedMetal", DECOR, CFrame.Angles(0.5, 0, 0.3))
	end,
}

catalog.rubbleSmall = {
	radius = 3.2,
	height = 2.6,
	build = function(b, cf, rng)
		rubblePile(b, cf, rng, 3, 1.2, 3.2, C.darkConcrete)
	end,
}

catalog.dumpster = {
	radius = 4.5,
	height = 5,
	build = function(b, cf, rng)
		local color = pick(rng, { Color3.fromRGB(50, 84, 60), Color3.fromRGB(60, 70, 96), C.rust })
		box(b, cf, "Dumpster", 4.2, 4, 7, 0, 0.3, 0, color, "CorrodedMetal")
		box(b, cf, "DumpsterLid", 4.4, 0.3, 7.2, -0.8, 4.4, 0, DARK, "Metal", DECOR, CFrame.Angles(0, 0, 0.5))
	end,
}

catalog.barrels = {
	radius = 3.2,
	height = 3.4,
	build = function(b, cf, rng)
		tube(b, cf, "Barrel1", 2.2, 3.1, -1, 0, -0.6, pick(rng, PAINT), "CorrodedMetal")
		tube(b, cf, "Barrel2", 2.2, 3.1, 1.3, 0, 0, pick(rng, PAINT), "CorrodedMetal")
		pipe(b, cf, "BarrelDown", 2.2, 3.1, -0.4, 1.1, 1.9, C.rust, "CorrodedMetal", nil, true)
	end,
}

catalog.fireBarrel = {
	radius = 1.8,
	height = 3.4,
	build = function(b, cf)
		tube(b, cf, "FireBarrel", 2.4, 3, 0, 0, 0, C.rust, "CorrodedMetal")
		box(
			b,
			cf,
			"FireCore",
			1.5,
			0.3,
			1.5,
			0,
			2.9,
			0,
			FIRE,
			"Neon",
			with(DECOR, {
				emitter = "fire",
				light = { color = FIRE, range = 22, brightness = 1.8, flicker = true, emergency = true },
			})
		)
	end,
}

catalog.crates = {
	radius = 3.8,
	height = 6.4,
	build = function(b, cf, rng)
		box(b, cf, "Crate1", 3.2, 3.2, 3.2, -1.2, 0, -0.6, WOOD, "WoodPlanks", LIGHT_COVER)
		box(b, cf, "Crate2", 3, 3, 3, 1.6, 0, 0.8, WOOD, "WoodPlanks", LIGHT_COVER, CFrame.Angles(0, 0.3, 0))
		if rng:NextNumber() < 0.7 then
			box(
				b,
				cf,
				"Crate3",
				2.8,
				2.8,
				2.8,
				-0.8,
				3.2,
				-0.4,
				WOOD,
				"WoodPlanks",
				LIGHT_COVER,
				CFrame.Angles(0, -0.4, 0)
			)
		end
	end,
}

catalog.sheetFence = {
	radius = 5.4,
	height = 6.2,
	build = function(b, cf, rng)
		box(b, cf, "FencePostA", 0.5, 6, 0.5, -4.6, 0, 0, C.rust, "CorrodedMetal")
		box(b, cf, "FencePostB", 0.5, 6, 0.5, 4.6, 0, 0, C.rust, "CorrodedMetal")
		box(
			b,
			cf,
			"FenceSheet",
			9.4,
			5.4,
			0.3,
			0,
			0.3,
			0,
			pick(rng, { C.rust, STEEL, Color3.fromRGB(70, 90, 84) }),
			"CorrodedMetal",
			LIGHT_COVER,
			CFrame.Angles(0, 0, rng:NextNumber(-0.05, 0.05))
		)
	end,
}

catalog.busStop = {
	radius = 5.6,
	height = 8.2,
	build = function(b, cf)
		box(b, cf, "StopPostA", 0.4, 7.4, 0.4, -4.4, 0, 1.2, STEEL, "Metal")
		box(b, cf, "StopPostB", 0.4, 7.4, 0.4, 4.4, 0, 1.2, STEEL, "Metal")
		box(b, cf, "StopRoof", 9.6, 0.4, 3.6, 0, 7.4, 0, STEEL, "Metal")
		box(b, cf, "StopGlass", 9, 6, 0.25, 0, 1, 1.3, GLASS, "Glass", with(LIGHT_COVER, { transparency = 0.45 }))
		box(b, cf, "StopBench", 6, 1.6, 1.4, 0, 0, 0.3, DARK, "Metal")
		box(
			b,
			cf,
			"StopAd",
			0.2,
			4,
			2.4,
			4.6,
			1.6,
			-0.4,
			C.magenta,
			"Neon",
			with(DECOR, light(C.magenta, 12, 0.9, true))
		)
	end,
}

catalog.billboard = {
	radius = 8,
	height = 19,
	build = function(b, cf, rng)
		local neon = pick(rng, { C.magenta, C.cyan, C.orange })
		box(b, cf, "BillboardLegA", 0.9, 11, 0.9, -5, 0, 0, DARK, "Metal")
		box(b, cf, "BillboardLegB", 0.9, 11, 0.9, 5, 0, 0, DARK, "Metal")
		box(b, cf, "BillboardPanel", 15, 7.4, 0.5, 0, 11, 0, DARK, "Metal", DECOR)
		box(
			b,
			cf,
			"BillboardGlow",
			13.6,
			0.5,
			0.2,
			0,
			17.4,
			-0.4,
			neon,
			"Neon",
			with(DECOR, light(neon, 26, 1.2, true))
		)
		box(b, cf, "BillboardBand", 9, 1.6, 0.2, -1.6, 13.6, -0.4, neon, "Neon", with(DECOR, { tags = { "Flicker" } }))
		box(b, cf, "BillboardBand2", 6, 0.6, 0.2, 2.6, 12.2, -0.4, C.white, "Neon", DECOR)
	end,
}

catalog.kiosk = {
	radius = 5.2,
	height = 9,
	build = function(b, cf, rng)
		local neon = pick(rng, { C.cyan, C.magenta, C.green })
		box(b, cf, "KioskBack", 7, 7, 0.6, 0, 0, 2.7, C.darkConcrete, "Metal")
		box(b, cf, "KioskSideA", 0.6, 7, 5.4, -3.2, 0, 0, C.darkConcrete, "Metal")
		box(b, cf, "KioskSideB", 0.6, 7, 5.4, 3.2, 0, 0, C.darkConcrete, "Metal")
		box(b, cf, "KioskCounter", 6, 3.2, 1.2, 0, 0, -2.2, STEEL, "Metal")
		box(b, cf, "KioskRoof", 7.8, 0.5, 7, 0, 7, -0.4, C.rust, "CorrodedMetal")
		box(b, cf, "KioskSign", 5.6, 1.1, 0.2, 0, 7.6, -3.8, neon, "Neon", with(DECOR, light(neon, 14, 1, true)))
	end,
}

catalog.sandbags = {
	radius = 5.2,
	height = 3.2,
	build = function(b, cf)
		local sand = Color3.fromRGB(150, 132, 92)
		box(b, cf, "SandbagFront", 9, 3, 1.8, 0, 0, -2, sand, "Fabric")
		box(b, cf, "SandbagLeft", 1.8, 3, 4.4, -3.6, 0, 0.9, sand, "Fabric")
		box(b, cf, "SandbagRight", 1.8, 3, 4.4, 3.6, 0, 0.9, sand, "Fabric")
	end,
}

local function container(b: Builder, cf: CFrame, color: Color3, base: number)
	box(b, cf, "Container", 6, 6, 14, 0, base, 0, color, "CorrodedMetal")
	box(b, cf, "ContainerDoor", 5.2, 5.2, 0.2, 0, base + 0.4, -7.1, DARK, "Metal", DECOR)
	box(b, cf, "ContainerRib", 6.2, 0.4, 14.2, 0, base + 5.8, 0, DARK, "Metal", DECOR)
end

catalog.container = {
	radius = 8,
	height = 6.6,
	build = function(b, cf, rng)
		container(b, cf, pick(rng, PAINT), 0)
	end,
}

catalog.containerStack = {
	radius = 8.6,
	height = 12.6,
	build = function(b, cf, rng)
		container(b, cf, pick(rng, PAINT), 0)
		container(
			b,
			cf * CFrame.new(rng:NextNumber(-0.6, 0.6), 0, 0) * CFrame.Angles(0, rng:NextNumber(-0.1, 0.1), 0),
			pick(rng, PAINT),
			6
		)
	end,
}

catalog.tent = {
	radius = 5.6,
	height = 6.6,
	build = function(b, cf, rng)
		local cloth = pick(rng, { TARP, Color3.fromRGB(120, 96, 66), Color3.fromRGB(70, 80, 96) })
		-- Deux pans inclinés qui se rejoignent au faîte.
		box(
			b,
			cf,
			"TentPanA",
			0.3,
			7.4,
			8,
			-2.3,
			0,
			0,
			cloth,
			"Fabric",
			LIGHT_COVER,
			CFrame.Angles(0, 0, math.rad(-38))
		)
		box(b, cf, "TentPanB", 0.3, 7.4, 8, 2.3, 0, 0, cloth, "Fabric", LIGHT_COVER, CFrame.Angles(0, 0, math.rad(38)))
		box(b, cf, "TentPole", 0.3, 6, 0.3, 0, 0, -3.8, WOOD, "Wood", DECOR)
		box(b, cf, "TentBedroll", 2, 0.5, 5, 0, 0, 0.6, Color3.fromRGB(96, 70, 60), "Fabric", DECOR)
	end,
}

catalog.tires = {
	radius = 2.8,
	height = 4.4,
	build = function(b, cf, rng)
		for index = 0, 2 do
			tube(
				b,
				cf,
				"Tire" .. index,
				4,
				1.3,
				rng:NextNumber(-0.3, 0.3),
				index * 1.35,
				rng:NextNumber(-0.3, 0.3),
				DARK,
				"SmoothPlastic"
			)
		end
	end,
}

catalog.roadSign = {
	radius = 1.4,
	height = 9.4,
	build = function(b, cf, rng)
		local lean = CFrame.Angles(rng:NextNumber(-0.2, 0.2), 0, rng:NextNumber(-0.2, 0.2))
		box(b, cf * lean, "SignPole", 0.4, 8, 0.4, 0, 0, 0, STEEL, "Metal")
		box(b, cf * lean, "SignPlate", 3, 3, 0.2, 0, 6.2, -0.3, pick(rng, { C.orange, C.red, C.white }), "Metal", DECOR)
	end,
}

catalog.planter = {
	radius = 3.6,
	height = 9,
	build = function(b, cf, rng)
		box(b, cf, "Planter", 5, 2.2, 5, 0, 0, 0, C.concrete, "Concrete")
		-- Arbre mort.
		local lean = CFrame.Angles(rng:NextNumber(-0.15, 0.15), rng:NextNumber(0, 6), rng:NextNumber(-0.15, 0.15))
		box(b, cf * lean, "DeadTrunk", 0.8, 6.6, 0.8, 0, 2.2, 0, Color3.fromRGB(60, 48, 40), "Wood", DECOR)
		box(
			b,
			cf * lean,
			"DeadBranch",
			0.4,
			3.4,
			0.4,
			0.9,
			6.4,
			0,
			Color3.fromRGB(60, 48, 40),
			"Wood",
			DECOR,
			CFrame.Angles(0, 0, -0.8)
		)
	end,
}

-- Toits -----------------------------------------------------------------------

catalog.acUnit = {
	radius = 3.2,
	height = 3.6,
	build = function(b, cf)
		box(b, cf, "AcUnit", 4.4, 3.2, 3.6, 0, 0, 0, STEEL, "Metal")
		tube(b, cf, "AcFan", 2.6, 0.3, 0, 3.2, 0, DARK, "Metal", DECOR)
	end,
}

catalog.vent = {
	radius = 2,
	height = 3,
	build = function(b, cf)
		tube(b, cf, "VentStack", 1.6, 2.6, 0, 0, 0, STEEL, "Metal")
		tube(b, cf, "VentCap", 2.4, 0.4, 0, 2.6, 0, DARK, "Metal", with(DECOR, { emitter = "steam" }))
	end,
}

catalog.waterTank = {
	radius = 4.4,
	height = 10,
	build = function(b, cf)
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				box(b, cf, "TankLeg", 0.5, 4, 0.5, sx * 2.4, 0, sz * 2.4, DARK, "Metal")
			end
		end
		tube(b, cf, "WaterTank", 6.6, 5.4, 0, 4, 0, WOOD, "WoodPlanks")
		tube(b, cf, "WaterTankCap", 7, 0.5, 0, 9.4, 0, C.rust, "CorrodedMetal", DECOR)
	end,
}

catalog.antennaMast = {
	radius = 1.6,
	height = 15,
	build = function(b, cf)
		box(b, cf, "MastFoot", 2, 0.6, 2, 0, 0, 0, DARK, "Metal")
		box(b, cf, "Mast", 0.4, 13, 0.4, 0, 0.6, 0, STEEL, "Metal", DECOR)
		box(b, cf, "MastBar", 3, 0.2, 0.2, 0, 10, 0, STEEL, "Metal", DECOR)
		ball(b, cf, "MastLight", 0.7, 0, 14, 0, C.red, "Neon", with(DECOR, light(C.red, 12, 1.4, true, true)))
	end,
}

-- Intérieurs ---------------------------------------------------------------------

catalog.desk = {
	radius = 3.8,
	height = 4.6,
	build = function(b, cf, rng)
		box(b, cf, "Desk", 6.4, 2.8, 2.8, 0, 0, 0, STEEL, "Metal")
		if rng:NextNumber() < 0.5 then
			box(b, cf, "Monitor", 2.2, 1.5, 0.2, -1, 2.9, 0.5, DARK, "Metal", DECOR)
		else
			box(
				b,
				cf,
				"Monitor",
				2.2,
				1.5,
				0.2,
				-1,
				2.9,
				0.5,
				SCREEN,
				"Neon",
				with(DECOR, light(SCREEN, 10, 0.8, true))
			)
		end
		box(
			b,
			cf,
			"Chair",
			1.8,
			3.4,
			1.8,
			1.4,
			0,
			-2.6,
			DARK,
			"Fabric",
			DECOR,
			CFrame.Angles(0, rng:NextNumber(-0.8, 0.8), 0)
		)
	end,
}

catalog.sofa = {
	radius = 4.2,
	height = 3.4,
	build = function(b, cf, rng)
		local cloth = pick(rng, { Color3.fromRGB(96, 60, 60), Color3.fromRGB(60, 72, 96), Color3.fromRGB(84, 84, 70) })
		box(b, cf, "SofaSeat", 7, 1.6, 2.8, 0, 0, 0, cloth, "Fabric")
		box(b, cf, "SofaBack", 7, 3.2, 0.9, 0, 0, 1.4, cloth, "Fabric")
	end,
}

catalog.tableSet = {
	radius = 4,
	height = 3.2,
	build = function(b, cf, rng)
		-- Table renversée : couvert bas.
		box(
			b,
			cf,
			"TableTop",
			5.6,
			3,
			0.4,
			0,
			0,
			0,
			WOOD,
			"WoodPlanks",
			LIGHT_COVER,
			CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, 0)
		)
		box(b, cf, "TableLeg", 0.4, 0.4, 2.4, -2.2, 1.3, 1.3, WOOD, "Wood", DECOR)
		box(b, cf, "Stool", 1.4, 1.6, 1.4, 1.8, 0, -2.2, DARK, "Metal", DECOR, CFrame.Angles(0, 0.5, 1.2))
	end,
}

catalog.bed = {
	radius = 4.4,
	height = 6.6,
	build = function(b, cf)
		box(b, cf, "BedFrame", 3.4, 2, 7, 0, 0, 0, STEEL, "Metal")
		box(b, cf, "Mattress", 3.2, 0.6, 6.6, 0, 2, 0, C.white, "Fabric", DECOR)
		box(b, cf, "DripStand", 0.2, 6, 0.2, 2.2, 0, 2.6, STEEL, "Metal", DECOR)
		-- Rideau de séparation.
		box(b, cf, "Curtain", 0.2, 6.4, 7.4, -2.4, 0, 0, Color3.fromRGB(120, 170, 160), "Fabric", LIGHT_COVER)
	end,
}

catalog.counter = {
	radius = 5.2,
	height = 4,
	build = function(b, cf, rng)
		box(b, cf, "Counter", 9, 3.4, 2.2, 0, 0, 0, C.darkConcrete, "Concrete")
		box(b, cf, "CounterTop", 9.4, 0.3, 2.6, 0, 3.4, 0, STEEL, "Metal", DECOR)
		if rng:NextNumber() < 0.5 then
			box(b, cf, "Register", 1.2, 1, 1.2, 2.6, 3.7, 0, DARK, "Metal", DECOR)
		end
	end,
}

catalog.vending = {
	radius = 2.4,
	height = 7.2,
	build = function(b, cf, rng)
		local neon = pick(rng, { C.cyan, C.magenta, C.green })
		box(b, cf, "Vending", 3.2, 7, 2.6, 0, 0, 0, DARK, "Metal")
		box(b, cf, "VendingFront", 2.6, 4.6, 0.15, 0, 1.8, -1.35, neon, "Neon", with(DECOR, light(neon, 12, 0.9, true)))
	end,
}

catalog.shelf = {
	radius = 5.4,
	height = 7.4,
	build = function(b, cf, rng)
		box(b, cf, "ShelfFrame", 10, 7, 0.4, 0, 0, 0.9, STEEL, "Metal", LIGHT_COVER)
		for level = 0, 2 do
			box(b, cf, "ShelfBoard" .. level, 10, 0.3, 2.2, 0, 1 + level * 2.4, 0, STEEL, "Metal", DECOR)
		end
		box(b, cf, "ShelfBoxA", 2.4, 1.8, 1.8, -3, 1.3, 0, WOOD, "WoodPlanks", DECOR)
		box(b, cf, "ShelfBoxB", 2, 1.6, 1.8, rng:NextNumber(0, 3), 3.7, 0, pick(rng, PAINT), "Metal", DECOR)
	end,
}

catalog.lockers = {
	radius = 4.4,
	height = 7.2,
	build = function(b, cf, rng)
		box(
			b,
			cf,
			"Lockers",
			8,
			7,
			2,
			0,
			0,
			0,
			pick(rng, { Color3.fromRGB(70, 84, 96), Color3.fromRGB(84, 70, 60), STEEL }),
			"Metal"
		)
		box(b, cf, "LockerDoor", 1.8, 6, 0.15, 2.2, 0.5, -1.4, DARK, "Metal", DECOR, CFrame.Angles(0, 0.7, 0))
	end,
}

catalog.partition = {
	radius = 4.8,
	height = 7.4,
	build = function(b, cf, rng)
		if rng:NextNumber() < 0.5 then
			box(
				b,
				cf,
				"PartitionGlass",
				9,
				6.4,
				0.3,
				0,
				0.6,
				0,
				GLASS,
				"Glass",
				with(LIGHT_COVER, { transparency = 0.5 })
			)
			box(b, cf, "PartitionSill", 9, 0.6, 0.6, 0, 0, 0, STEEL, "Metal", DECOR)
		else
			box(b, cf, "PartitionBoards", 9, 7, 0.4, 0, 0, 0, WOOD, "WoodPlanks", LIGHT_COVER)
		end
	end,
}

catalog.cabinet = {
	radius = 2.6,
	height = 5.4,
	build = function(b, cf, rng)
		box(b, cf, "Cabinet", 3.6, 5, 2, 0, 0, 0, STEEL, "Metal")
		box(
			b,
			cf,
			"CabinetDrawer",
			3,
			1.2,
			0.8,
			0,
			1.2,
			-1.2,
			DARK,
			"Metal",
			DECOR,
			CFrame.Angles(0, rng:NextNumber(-0.2, 0.2), 0)
		)
	end,
}

-- Usine ---------------------------------------------------------------------------

catalog.machine = {
	radius = 6.2,
	height = 9,
	build = function(b, cf, rng)
		local color = pick(rng, { C.rust, Color3.fromRGB(70, 78, 70), Color3.fromRGB(84, 80, 60) })
		box(b, cf, "MachineBody", 8, 6, 6, 0, 0, 0, color, "CorrodedMetal")
		box(b, cf, "MachineTop", 5, 2, 4, -1, 6, 0, DARK, "Metal")
		tube(b, cf, "MachineExhaust", 1.2, 3, 2.8, 6, 1.6, STEEL, "Metal", with(DECOR, { emitter = "steam" }))
		pipe(b, cf, "MachinePipe", 1, 8.4, 0, 2.2, -3.4, STEEL, "Metal", DECOR, true)
		box(
			b,
			cf,
			"MachinePanel",
			2,
			1.4,
			0.2,
			2.4,
			2.6,
			-3.05,
			C.orange,
			"Neon",
			with(DECOR, light(C.orange, 12, 0.9, rng:NextNumber() < 0.5))
		)
	end,
}

catalog.press = {
	radius = 5.4,
	height = 12,
	build = function(b, cf)
		box(b, cf, "PressBase", 8, 2, 6, 0, 0, 0, DARK, "Metal")
		box(b, cf, "PressColumnA", 1.4, 9, 1.4, -3.2, 2, 0, STEEL, "Metal")
		box(b, cf, "PressColumnB", 1.4, 9, 1.4, 3.2, 2, 0, STEEL, "Metal")
		box(b, cf, "PressHead", 8, 2, 4, 0, 9.6, 0, C.rust, "CorrodedMetal")
		box(b, cf, "PressRam", 3.4, 3.4, 3, 0, 6.2, 0, STEEL, "DiamondPlate", DECOR)
	end,
}

-- Nacelle d'assemblage : une carcasse de robot inachevée.
catalog.pod = {
	radius = 4.2,
	height = 10.6,
	build = function(b, cf)
		tube(b, cf, "PodBase", 6.6, 0.8, 0, 0, 0, DARK, "Metal")
		box(b, cf, "PodSpine", 1, 10, 1, 0, 0, 2.6, STEEL, "Metal")
		box(b, cf, "PodArm", 5, 0.6, 0.6, 0, 9, 1, STEEL, "Metal", DECOR)
		box(b, cf, "PodTorso", 2.4, 3, 1.6, 0, 3.6, 0, Color3.fromRGB(52, 56, 64), "Metal", DECOR)
		box(b, cf, "PodHead", 1.4, 1.2, 1.4, 0, 6.7, 0, DARK, "Metal", DECOR)
		box(b, cf, "PodEye", 1, 0.16, 0.1, 0, 7.3, -0.72, C.red, "Neon", with(DECOR, { tags = { "Flicker" } }))
		box(b, cf, "PodLegs", 2, 2.8, 1.2, 0, 0.8, 0, Color3.fromRGB(52, 56, 64), "Metal", DECOR)
	end,
}

catalog.tank = {
	radius = 5.6,
	height = 13.4,
	build = function(b, cf, rng)
		tube(
			b,
			cf,
			"Tank",
			9,
			11.4,
			0,
			0.8,
			0,
			pick(rng, { STEEL, C.rust, Color3.fromRGB(96, 104, 90) }),
			"CorrodedMetal"
		)
		tube(b, cf, "TankBase", 9.8, 0.8, 0, 0, 0, C.darkConcrete, "Concrete")
		tube(b, cf, "TankCap", 5, 1, 0, 12.2, 0, DARK, "Metal", DECOR)
		box(b, cf, "TankLadder", 1.4, 11, 0.3, 0, 0.8, -4.7, DARK, "Metal", DECOR)
		box(b, cf, "TankBand", 9.2, 0.5, 9.2, 0, 6, 0, C.orange, "Metal", DECOR)
	end,
}

catalog.pipeRack = {
	radius = 9.4,
	height = 5.6,
	build = function(b, cf)
		for _, oz in { -6.5, 0, 6.5 } do
			box(b, cf, "RackSupport", 5.6, 0.6, 0.8, 0, 0, oz, C.darkConcrete, "Concrete")
		end
		pipe(b, cf, "RackPipeA", 2, 17, -1.6, 1.6, 0, C.rust, "CorrodedMetal")
		pipe(b, cf, "RackPipeB", 2, 17, 1.6, 1.6, 0, STEEL, "Metal")
		pipe(b, cf, "RackPipeC", 2, 17, 0, 3.6, 0, C.rust, "CorrodedMetal")
	end,
}

catalog.pallet = {
	radius = 3.6,
	height = 4.8,
	build = function(b, cf, rng)
		box(b, cf, "Pallet", 5, 0.6, 5, 0, 0, 0, WOOD, "WoodPlanks", DECOR)
		box(
			b,
			cf,
			"PalletLoad",
			4.4,
			3.8,
			4.4,
			0,
			0.6,
			0,
			pick(rng, { WOOD, TARP, C.darkConcrete }),
			"WoodPlanks",
			LIGHT_COVER
		)
	end,
}

catalog.forklift = {
	radius = 4.6,
	height = 7.6,
	build = function(b, cf, rng)
		box(b, cf, "ForkliftBody", 4, 3.4, 6, 0, 0.8, 1, C.orange, "CorrodedMetal")
		box(b, cf, "ForkliftCage", 3.6, 3.6, 3, 0, 4.2, 1.4, DARK, "Metal", DECOR)
		box(b, cf, "ForkliftMast", 3.2, 7, 0.5, 0, 0.4, -2.4, STEEL, "Metal")
		box(b, cf, "ForkliftForks", 2.6, 0.3, 3.4, 0, 0.6, -4.2, STEEL, "Metal", DECOR)
		wheels(b, cf, 2, 2.2, 1.8, rng)
	end,
}

catalog.spool = {
	radius = 3.2,
	height = 5.4,
	build = function(b, cf)
		pipe(b, cf, "SpoolCore", 3, 3, 0, 2.6, 0, DARK, "SmoothPlastic", nil, true)
		pipe(b, cf, "SpoolRimA", 5.2, 0.4, -1.7, 2.6, 0, WOOD, "WoodPlanks", nil, true)
		pipe(b, cf, "SpoolRimB", 5.2, 0.4, 1.7, 2.6, 0, WOOD, "WoodPlanks", nil, true)
	end,
}

catalog.generator = {
	radius = 4.2,
	height = 5.6,
	build = function(b, cf, rng)
		box(b, cf, "Generator", 6, 4, 4, 0, 0.4, 0, Color3.fromRGB(96, 90, 50), "CorrodedMetal")
		box(b, cf, "GeneratorSkid", 6.6, 0.4, 4.6, 0, 0, 0, DARK, "Metal", DECOR)
		tube(b, cf, "GeneratorExhaust", 0.8, 1.6, 2, 4.4, 1, DARK, "Metal", with(DECOR, { emitter = "smoke" }))
		box(
			b,
			cf,
			"GeneratorLamp",
			0.6,
			0.6,
			0.2,
			-2,
			2.6,
			-2.05,
			C.green,
			"Neon",
			with(DECOR, light(C.green, 10, 1, rng:NextNumber() < 0.6, true))
		)
	end,
}

catalog.crucible = {
	radius = 5.6,
	height = 8.4,
	build = function(b, cf)
		tube(b, cf, "Crucible", 9, 6.4, 0, 1.4, 0, DARK, "Metal")
		tube(b, cf, "CrucibleFoot", 6, 1.4, 0, 0, 0, C.darkConcrete, "Concrete")
		tube(
			b,
			cf,
			"CrucibleGlow",
			7.6,
			0.3,
			0,
			7.7,
			0,
			FIRE,
			"Neon",
			with(DECOR, {
				emitter = "embers",
				light = { color = FIRE, range = 30, brightness = 1.6, flicker = false, emergency = true },
			})
		)
	end,
}

catalog.chimney = {
	radius = 6.6,
	height = 62,
	build = function(b, cf)
		tube(b, cf, "ChimneyBase", 12, 6, 0, 0, 0, C.darkConcrete, "Concrete")
		tube(b, cf, "Chimney", 8.4, 52, 0, 6, 0, C.rust, "Brick")
		tube(b, cf, "ChimneyRing", 9, 1.2, 0, 44, 0, C.red, "Metal", DECOR)
		tube(b, cf, "ChimneyMouth", 6, 0.4, 0, 58, 0, DARK, "Metal", with(DECOR, { emitter = "smoke" }))
	end,
}

catalog.workbench = {
	radius = 4.2,
	height = 4.6,
	build = function(b, cf)
		box(b, cf, "Workbench", 7, 3, 2.6, 0, 0, 0, WOOD, "WoodPlanks", LIGHT_COVER)
		box(b, cf, "BenchVise", 1, 1, 1.4, -2.2, 3, 0, STEEL, "Metal", DECOR)
		box(b, cf, "BenchSparks", 0.5, 0.3, 0.5, 1.6, 3, 0, FIRE, "Neon", with(DECOR, { emitter = "sparks" }))
	end,
}

catalog.controlDesk = {
	radius = 4.8,
	height = 5.8,
	build = function(b, cf, rng)
		box(b, cf, "ControlDesk", 8.4, 3, 3, 0, 0, 0, DARK, "Metal")
		box(b, cf, "ControlSlope", 8.4, 0.3, 2, 0, 3, -0.4, STEEL, "Metal", DECOR, CFrame.Angles(0.35, 0, 0))
		for index, ox in { -2.6, 0, 2.6 } do
			if rng:NextNumber() < 0.7 then
				box(
					b,
					cf,
					"ControlScreen" .. index,
					2.2,
					1.6,
					0.15,
					ox,
					3.8,
					0.9,
					SCREEN,
					"Neon",
					with(DECOR, if index == 2 then light(SCREEN, 12, 0.9, true) else { tags = { "Flicker" } })
				)
			end
		end
	end,
}

catalog.railCart = {
	radius = 5.4,
	height = 5.2,
	build = function(b, cf, rng)
		box(b, cf, "CartBed", 5, 1, 9, 0, 1.2, 0, DARK, "Metal")
		box(b, cf, "CartSideA", 0.4, 3, 9, -2.4, 2.2, 0, C.rust, "CorrodedMetal")
		box(b, cf, "CartSideB", 0.4, 3, 9, 2.4, 2.2, 0, C.rust, "CorrodedMetal")
		box(b, cf, "CartLoad", 4, 1.6, 7, 0, 2.2, 0, pick(rng, { C.darkConcrete, C.rust, STEEL }), "Slate", DECOR)
		wheels(b, cf, 2.4, 3, 1.6, rng)
	end,
}

-- Data center --------------------------------------------------------------------

local function rackUnit(b: Builder, cf: CFrame, name: string, rng: Rng)
	box(b, cf, name, 3.6, 9, 3, 0, 0, 0, Color3.fromRGB(26, 28, 36), "Metal")
	if rng:NextNumber() < 0.7 then
		box(
			b,
			cf,
			name .. "Led",
			0.2,
			7,
			0.1,
			1.1,
			1,
			-1.55,
			pick(rng, { C.cyan, C.green, C.red }),
			"Neon",
			with(DECOR, { tags = { "Flicker" } })
		)
	end
end

catalog.rack = {
	radius = 2.8,
	height = 9.4,
	build = function(b, cf, rng)
		rackUnit(b, cf, "Rack", rng)
	end,
}

catalog.rackRow = {
	radius = 9,
	height = 9.4,
	build = function(b, cf, rng)
		for index = 0, 3 do
			rackUnit(b, cf * CFrame.new((index - 1.5) * 3.9, 0, 0), "Rack" .. index, rng)
		end
		box(
			b,
			cf,
			"RowGlow",
			15,
			0.2,
			0.2,
			0,
			9.1,
			-1.4,
			C.cyan,
			"Neon",
			with(DECOR, light(C.cyan, 14, 0.8, true, true))
		)
	end,
}

catalog.coolingUnit = {
	radius = 5.6,
	height = 7.6,
	build = function(b, cf)
		box(b, cf, "CoolingUnit", 9, 6, 5, 0, 0, 0, Color3.fromRGB(150, 170, 190), "Metal")
		tube(b, cf, "CoolingFan", 4, 0.5, -2, 6, 0, DARK, "Metal", with(DECOR, { emitter = "coldfog" }))
		tube(b, cf, "CoolingFan2", 4, 0.5, 2.2, 6, 0, DARK, "Metal", DECOR)
		pipe(b, cf, "CoolingPipe", 1, 9.4, 0, 1.4, -2.9, C.cyan, "Metal", DECOR, true)
	end,
}

catalog.floodlight = {
	radius = 1.8,
	height = 19,
	build = function(b, cf, rng)
		box(b, cf, "FloodFoot", 2.2, 1, 2.2, 0, 0, 0, C.darkConcrete, "Concrete")
		box(b, cf, "FloodPole", 0.7, 17, 0.7, 0, 1, 0, DARK, "Metal")
		box(
			b,
			cf,
			"FloodHead",
			3.4,
			1.2,
			1,
			0,
			17.6,
			-0.4,
			C.white,
			"Neon",
			with(DECOR, {
				light = {
					kind = "spot",
					face = "Bottom",
					angle = 100,
					color = Color3.fromRGB(214, 228, 255),
					range = 60,
					brightness = 2.4,
					flicker = rng:NextNumber() < 0.35,
				},
			})
		)
	end,
}

-- Balise de secours : reste allumée pendant les coupures.
catalog.beacon = {
	radius = 1.2,
	height = 5.4,
	build = function(b, cf)
		box(b, cf, "BeaconPost", 0.6, 4.4, 0.6, 0, 0, 0, DARK, "Metal")
		ball(b, cf, "BeaconLamp", 1.1, 0, 4.9, 0, C.red, "Neon", with(DECOR, light(C.red, 20, 1.6, false, true)))
	end,
}

catalog.transformer = {
	radius = 5.6,
	height = 9,
	build = function(b, cf)
		box(b, cf, "TransformerPad", 9, 0.6, 7, 0, 0, 0, C.darkConcrete, "Concrete")
		box(b, cf, "Transformer", 6, 6, 4.4, 0, 0.6, 0, Color3.fromRGB(84, 96, 100), "CorrodedMetal")
		for _, ox in { -2, 0, 2 } do
			tube(b, cf, "Insulator", 0.8, 2, ox, 6.6, 0, C.white, "SmoothPlastic", DECOR)
		end
		box(b, cf, "TransformerFins", 0.6, 4.4, 5.4, -3.4, 1.2, 0, DARK, "Metal", DECOR)
		box(
			b,
			cf,
			"TransformerWarning",
			1.6,
			1.6,
			0.15,
			1.4,
			3,
			-2.3,
			C.orange,
			"Neon",
			with(DECOR, { tags = { "Flicker" } })
		)
	end,
}

catalog.dish = {
	radius = 5.2,
	height = 10,
	build = function(b, cf, rng)
		tube(b, cf, "DishFoot", 3, 1, 0, 0, 0, C.darkConcrete, "Concrete")
		box(b, cf, "DishPole", 0.9, 6, 0.9, 0, 1, 0, STEEL, "Metal")
		b:part(
			"Dish",
			Vector3.new(0.6, 8, 8),
			cf * CFrame.new(0, 7.4, 0) * CFrame.Angles(0, rng:NextNumber(0, 6), math.rad(55)),
			C.white,
			"Metal",
			{ shape = "Cylinder", collide = false, query = false }
		)
	end,
}

catalog.booth = {
	radius = 5.4,
	height = 9.4,
	build = function(b, cf)
		box(b, cf, "BoothBack", 7, 8, 0.6, 0, 0, 3, DARK, "Metal")
		box(b, cf, "BoothSideA", 0.6, 8, 6, -3.2, 0, 0, DARK, "Metal")
		box(b, cf, "BoothSideB", 0.6, 3.4, 6, 3.2, 0, 0, DARK, "Metal")
		box(b, cf, "BoothGlass", 0.3, 4.4, 6, 3.2, 3.4, 0, GLASS, "Glass", with(LIGHT_COVER, { transparency = 0.5 }))
		box(b, cf, "BoothRoof", 8, 0.5, 7, 0, 8, 0, STEEL, "Metal")
		box(
			b,
			cf,
			"BoothLamp",
			2,
			0.3,
			0.6,
			0,
			7.6,
			-2.6,
			C.red,
			"Neon",
			with(DECOR, light(C.red, 16, 1.2, false, true))
		)
	end,
}

catalog.bollards = {
	radius = 5.4,
	height = 3.8,
	build = function(b, cf)
		for index = 0, 3 do
			local ox = (index - 1.5) * 3
			tube(b, cf, "Bollard" .. index, 1.2, 3.4, ox, 0, 0, DARK, "Metal")
			tube(
				b,
				cf,
				"BollardRing" .. index,
				1.3,
				0.3,
				ox,
				2.6,
				0,
				C.cyan,
				"Neon",
				with(DECOR, { tags = { "Flicker" } })
			)
		end
	end,
}

catalog.terminal = {
	radius = 2.2,
	height = 5.8,
	build = function(b, cf)
		box(b, cf, "TerminalBase", 2.6, 3.4, 2, 0, 0, 0, DARK, "Metal")
		box(
			b,
			cf,
			"TerminalScreen",
			2.4,
			1.8,
			0.2,
			0,
			3.5,
			0.3,
			SCREEN,
			"Neon",
			with(DECOR, { light = { color = SCREEN, range = 12, brightness = 1, flicker = true, emergency = true } }),
			CFrame.Angles(-0.25, 0, 0)
		)
	end,
}

catalog.dataPod = {
	radius = 8,
	height = 6.8,
	build = function(b, cf, rng)
		container(b, cf, Color3.fromRGB(44, 50, 62), 0)
		local neon = pick(rng, { C.cyan, C.green })
		box(b, cf, "PodStripA", 0.15, 0.3, 12, -3.05, 3, 0, neon, "Neon", with(DECOR, light(neon, 12, 0.8, true, true)))
		box(b, cf, "PodStripB", 0.15, 0.3, 12, 3.05, 3, 0, neon, "Neon", DECOR)
	end,
}

-- Désert ---------------------------------------------------------------------------

local ROCKS = { C.rock, Color3.fromRGB(128, 100, 76), Color3.fromRGB(150, 122, 92), Color3.fromRGB(116, 96, 78) }

local function rocks(b: Builder, cf: CFrame, rng: Rng, count: number, spread: number, minSize: number, maxSize: number)
	for index = 1, count do
		local sx, sy, sz =
			rng:NextNumber(minSize, maxSize), rng:NextNumber(minSize, maxSize), rng:NextNumber(minSize, maxSize)
		b:part(
			"Rock" .. index,
			Vector3.new(sx, sy, sz),
			cf * CFrame.new(rng:NextNumber(-spread, spread), sy * 0.3, rng:NextNumber(-spread, spread)) * tilt(rng, 0.5),
			pick(rng, ROCKS),
			pick(rng, { "Rock", "Sandstone", "Basalt" })
		)
	end
end

catalog.rock = {
	radius = 12,
	height = 12,
	build = function(b, cf, rng)
		rocks(b, cf, rng, rng:NextInteger(3, 5), 3.5, 5, 11)
	end,
}

catalog.boulder = {
	radius = 5,
	height = 5.4,
	build = function(b, cf, rng)
		rocks(b, cf, rng, 2, 1, 3, 5.5)
	end,
}

-- Grand piton : un couvert haut, visible de loin.
catalog.spire = {
	radius = 13,
	height = 34,
	build = function(b, cf, rng)
		local color = pick(rng, ROCKS)
		box(
			b,
			cf,
			"SpireBase",
			16,
			12,
			14,
			0,
			-1,
			0,
			color,
			"Sandstone",
			nil,
			CFrame.Angles(0.06, rng:NextNumber(0, 3), -0.05)
		)
		box(
			b,
			cf,
			"SpireMid",
			11,
			14,
			10,
			1,
			9,
			-0.5,
			color,
			"Sandstone",
			nil,
			CFrame.Angles(-0.08, rng:NextNumber(0, 3), 0.1)
		)
		box(
			b,
			cf,
			"SpireTop",
			7,
			12,
			6,
			-0.5,
			21,
			0.5,
			color,
			"Rock",
			nil,
			CFrame.Angles(0.12, rng:NextNumber(0, 3), -0.1)
		)
	end,
}

--[[
	Strate rocheuse : une dalle inclinée qui sort du sable. Le côté bas se
	gravit à pied, le côté haut forme une petite falaise (couvert).
]]
local function slab(
	b: Builder,
	cf: CFrame,
	name: string,
	length: number,
	width: number,
	rise: number,
	color: Color3,
	material: string
)
	local thickness = 10
	local angle = math.asin(math.clamp((rise + 0.6) / length, 0, 0.6))
	local rotation = CFrame.Angles(0, 0, angle)
	-- Centre du dessus à mi-hauteur ; le centre de la dalle est une demi-épaisseur dessous.
	local top = cf * CFrame.new(0, (rise - 0.6) / 2, 0) * rotation
	b:part(name, Vector3.new(length, thickness, width), top * CFrame.new(0, -thickness / 2, 0), color, material)
end

catalog.strata = {
	radius = 17,
	height = 9,
	build = function(b, cf, rng)
		local color = pick(rng, ROCKS)
		slab(b, cf, "Strata", rng:NextNumber(24, 30), rng:NextNumber(14, 20), rng:NextNumber(5, 8), color, "Sandstone")
		slab(
			b,
			cf * CFrame.new(3, 0, 6) * CFrame.Angles(0, 0.3, 0),
			"StrataB",
			18,
			10,
			rng:NextNumber(3, 5),
			color,
			"Rock"
		)
	end,
}

-- Dune : deux dalles de sable adossées, crête au milieu (gravissable des deux côtés).
catalog.dune = {
	radius = 24,
	height = 7,
	build = function(b, cf, rng)
		local sand = Color3.fromRGB(204, 178, 126)
		local rise = rng:NextNumber(4.5, 6.5)
		local width = rng:NextNumber(26, 36)
		slab(b, cf * CFrame.new(-10, 0, 0), "DuneA", 22, width, rise, sand, "Sand")
		slab(b, cf * CFrame.new(10, 0, 0) * CFrame.Angles(0, math.pi, 0), "DuneB", 22, width, rise, sand, "Sand")
	end,
}

catalog.deadTree = {
	radius = 2,
	height = 14,
	build = function(b, cf, rng)
		local bark = Color3.fromRGB(64, 52, 44)
		local lean = cf * CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, 6), rng:NextNumber(-0.2, 0.2))
		box(b, lean, "Trunk", 1.4, 9, 1.4, 0, 0, 0, bark, "Wood")
		box(b, lean, "BranchA", 0.6, 5, 0.6, 1.4, 7.4, 0, bark, "Wood", DECOR, CFrame.Angles(0, 0, -0.7))
		box(b, lean, "BranchB", 0.5, 4, 0.5, -1.2, 6, 0.4, bark, "Wood", DECOR, CFrame.Angles(0.3, 0, 0.8))
		box(b, lean, "BranchC", 0.4, 3, 0.4, 0, 9, -0.8, bark, "Wood", DECOR, CFrame.Angles(-0.6, 0, 0))
	end,
}

-- Carcasse d'une machine fouisseuse : colonne et côtes.
catalog.bones = {
	radius = 9,
	height = 7,
	build = function(b, cf)
		pipe(b, cf, "Spine", 1.4, 16, 0, 1, 0, BONE, "SmoothPlastic")
		for index = 0, 4 do
			local oz = -6 + index * 3
			for _, side in { -1, 1 } do
				box(
					b,
					cf,
					"Rib",
					0.7,
					6.4,
					0.7,
					side * 2,
					0.4,
					oz,
					BONE,
					"SmoothPlastic",
					DECOR,
					CFrame.Angles(0, 0, side * -0.55)
				)
			end
		end
	end,
}

catalog.planeWreck = {
	radius = 19,
	height = 10,
	build = function(b, cf)
		local hull = Color3.fromRGB(170, 172, 168)
		pipe(b, cf, "Fuselage", 9, 30, 0, 3.6, 0, hull, "CorrodedMetal")
		ball(b, cf, "Nose", 9, 0, 3.6, -15, hull, "CorrodedMetal")
		box(b, cf, "WingA", 16, 0.8, 7, -11, 2, 2, hull, "CorrodedMetal", nil, CFrame.Angles(0, 0.2, 0.22))
		box(b, cf, "WingStub", 6, 0.8, 6, 6, 3.4, 2, hull, "CorrodedMetal", nil, CFrame.Angles(0, -0.2, -0.3))
		box(b, cf, "TailFin", 0.8, 8, 5, 0, 6, 13, C.red, "CorrodedMetal", DECOR, CFrame.Angles(-0.4, 0, 0))
		box(b, cf, "HullBreach", 9.2, 3, 5, 0, 5, 3, DARK, "Metal", DECOR)
	end,
}

catalog.pylon = {
	radius = 6.5,
	height = 46,
	build = function(b, cf)
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				box(
					b,
					cf,
					"PylonLeg",
					0.9,
					40,
					0.9,
					sx * 3,
					0,
					sz * 3,
					STEEL,
					"CorrodedMetal",
					nil,
					CFrame.Angles(sz * 0.06, 0, -sx * 0.06)
				)
			end
		end
		box(b, cf, "PylonArmA", 22, 0.8, 0.8, 0, 30, 0, STEEL, "CorrodedMetal", DECOR)
		box(b, cf, "PylonArmB", 16, 0.8, 0.8, 0, 38, 0, STEEL, "CorrodedMetal", DECOR)
		box(b, cf, "PylonBrace", 6.6, 0.6, 6.6, 0, 14, 0, STEEL, "CorrodedMetal", DECOR)
		-- Câble arraché qui pend.
		box(b, cf, "PylonCable", 0.2, 22, 0.2, 10, 8.6, 0, DARK, "SmoothPlastic", DECOR, CFrame.Angles(0, 0, 0.12))
	end,
}

catalog.pylonDown = {
	radius = 21,
	height = 7,
	build = function(b, cf)
		box(b, cf, "FallenTruss", 4, 4, 38, 0, 0.4, 0, STEEL, "CorrodedMetal", nil, CFrame.Angles(0.07, 0, 0.1))
		box(b, cf, "FallenArm", 18, 0.8, 0.8, 0, 3, 8, STEEL, "CorrodedMetal", DECOR, CFrame.Angles(0, 0.2, 0.35))
		box(b, cf, "FallenFoot", 6, 3, 6, 0, 0, -18, C.darkConcrete, "Concrete", nil, CFrame.Angles(0.2, 0.3, 0))
	end,
}

catalog.pipeline = {
	radius = 15,
	height = 7,
	build = function(b, cf)
		for _, oz in { -11, 0, 11 } do
			box(b, cf, "PipelineSupport", 5, 2.4, 1.6, 0, 0, oz, C.darkConcrete, "Concrete")
		end
		pipe(b, cf, "Pipeline", 4.4, 28, 0, 4.6, 0, C.rust, "CorrodedMetal")
		pipe(b, cf, "PipelineFlange", 5.2, 0.8, 0, 4.6, -5, STEEL, "Metal", DECOR)
		pipe(b, cf, "PipelineFlange2", 5.2, 0.8, 0, 4.6, 7, STEEL, "Metal", DECOR)
	end,
}

-- Fûts qui fuient : signalent une poche irradiée.
catalog.radBarrels = {
	radius = 3.6,
	height = 3.8,
	build = function(b, cf)
		local drum = Color3.fromRGB(150, 140, 50)
		tube(b, cf, "RadBarrel1", 2.4, 3.2, -1.1, 0, 0, drum, "CorrodedMetal")
		tube(b, cf, "RadBarrel2", 2.4, 3.2, 1.2, 0, 0.8, drum, "CorrodedMetal")
		tube(
			b,
			cf,
			"RadPuddle",
			6.4,
			0.12,
			0,
			0,
			0,
			C.toxic,
			"Neon",
			with(DECOR, {
				emitter = "motes",
				light = { color = C.toxic, range = 16, brightness = 1.2, flicker = true, emergency = true },
			})
		)
	end,
}

-- Fissure luminescente (posée au sol, sans collision).
catalog.glowCrack = {
	radius = 7,
	height = 0.4,
	build = function(b, cf, rng)
		for index = 1, 3 do
			box(
				b,
				cf,
				"GlowCrack" .. index,
				rng:NextNumber(0.4, 0.9),
				0.12,
				rng:NextNumber(6, 12),
				rng:NextNumber(-3, 3),
				0.02,
				rng:NextNumber(-2, 2),
				C.toxic,
				"Neon",
				if index == 1 then with(DECOR, light(C.toxic, 14, 0.9, true, true)) else DECOR,
				CFrame.Angles(0, rng:NextNumber(0, 3), 0)
			)
		end
	end,
}

catalog.tankWreck = {
	radius = 8.4,
	height = 6.8,
	build = function(b, cf, rng)
		local olive = Color3.fromRGB(86, 94, 62)
		box(b, cf, "TankHull", 8, 3, 13, 0, 0.6, 0, olive, "CorrodedMetal")
		box(b, cf, "TankTrackA", 1.6, 2.4, 14, -4.4, 0, 0, DARK, "Metal")
		box(b, cf, "TankTrackB", 1.6, 2.4, 14, 4.4, 0, 0, DARK, "Metal")
		local turret = cf * CFrame.new(0, 3.6, 1) * CFrame.Angles(0, rng:NextNumber(-1, 1), 0)
		box(b, turret, "TankTurret", 5.4, 2.4, 6, 0, 0, 0, olive, "CorrodedMetal")
		pipe(b, turret, "TankBarrel", 0.9, 9, 0, 1.4, -7, DARK, "Metal", DECOR)
	end,
}

catalog.solarArray = {
	radius = 6.4,
	height = 5.4,
	build = function(b, cf, rng)
		for index = -1, 1 do
			box(b, cf, "SolarPost" .. index, 0.5, 3, 0.5, index * 3.8, 0, 0, STEEL, "Metal")
			box(
				b,
				cf,
				"SolarPanel" .. index,
				3.6,
				0.25,
				5.4,
				index * 3.8,
				3,
				0,
				Color3.fromRGB(30, 40, 70),
				"Glass",
				LIGHT_COVER,
				CFrame.Angles(0.5 + rng:NextNumber(-0.1, 0.1), 0, rng:NextNumber(-0.1, 0.1))
			)
		end
	end,
}

-- Éclats de silice vitrifiée (bord du Cratère).
catalog.shards = {
	radius = 4.4,
	height = 9,
	build = function(b, cf, rng)
		for index = 1, 3 do
			local height = rng:NextNumber(4, 9)
			box(
				b,
				cf,
				"Shard" .. index,
				rng:NextNumber(1, 2.2),
				height,
				rng:NextNumber(1, 2.2),
				rng:NextNumber(-2, 2),
				-0.6,
				rng:NextNumber(-2, 2),
				Color3.fromRGB(110, 200, 120),
				"Glass",
				if index == 1
					then with({ transparency = 0.25 }, light(C.toxic, 12, 0.8, false, true))
					else { transparency = 0.25 },
				CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3))
			)
		end
	end,
}

Props.catalog = catalog

local LIMIT = 386

-- Pose un décor sans vérification (emplacements choisis à la main).
function Props.put(b: Builder, name: string, x: number, y: number, z: number, yaw: number, rng: Rng)
	local prop = catalog[name]
	assert(prop ~= nil, `décor inconnu : {name}`)
	prop.build(b, CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0), rng)
end

-- Pose un décor si la place est libre (ni pièce solide, ni repère, ni porte).
function Props.place(b: Builder, name: string, x: number, y: number, z: number, yaw: number, rng: Rng): boolean
	local prop = catalog[name]
	assert(prop ~= nil, `décor inconnu : {name}`)
	-- En deçà des silhouettes qui bordent la carte.
	if math.abs(x) + prop.radius > LIMIT or math.abs(z) + prop.radius > LIMIT then
		return false
	end
	if not b:isFree(x, y, z, prop.radius, prop.height) then
		return false
	end
	prop.build(b, CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0), rng)
	return true
end

return Props
