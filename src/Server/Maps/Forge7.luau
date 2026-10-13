--!strict
--[[
	Forge-7, usine de robots (section 12.2).

	- Chaîne d'assemblage 🔥 (grand hall central) : Exécuteurs en cours de
	  fabrication qui s'activent à l'approche, Gardien = bras robotique géant
	  fixé au plafond. La chaîne produit 1 ou 2 Sentinelles toutes les
	  3 minutes, sauf si le panneau de contrôle (300 PV) est détruit.
	- Fonderie (ouest) : coulées de métal en fusion (mort instantanée),
	  passerelles étroites.
	- Entrepôt de pièces (est) : rayonnages, beaucoup de cellules.
	- Extractions : quai de chargement, monte-charge, toit de la cheminée.
]]

local Dress = require(script.Parent.Dress)
local LayoutBuilder = require(script.Parent.LayoutBuilder)
local Props = require(script.Parent.Props)

local C = LayoutBuilder.colors
local SIZE = 800

local FLOOR = Color3.fromRGB(66, 62, 60)
local WALL = Color3.fromRGB(88, 82, 78)
local MOLTEN = Color3.fromRGB(255, 110, 20)

return function(rng: LayoutBuilder.Rng): LayoutBuilder.Layout
	local b = LayoutBuilder.new(WALL, "Concrete")
	b:ground(SIZE, FLOOR, "Concrete")
	b:borderSpawns(SIZE, 25)

	-- Grand hall : chaîne d'assemblage 🔥 ------------------------------------------
	local hallH = 36
	local function hallWall(name: string, center: Vector3, length: number, axis: string, gapOffset: number)
		b:wall(
			name,
			center,
			length,
			hallH,
			axis,
			{ offset = gapOffset, width = 20, bottom = 0, top = 16 },
			WALL,
			"Concrete"
		)
	end
	hallWall("HallS1", Vector3.new(-80, 0, -110), 160, "x", 0)
	hallWall("HallS2", Vector3.new(80, 0, -110), 160, "x", 0)
	hallWall("HallN1", Vector3.new(-80, 0, 110), 160, "x", 0)
	hallWall("HallN2", Vector3.new(80, 0, 110), 160, "x", 0)
	hallWall("HallE", Vector3.new(160, 0, 0), 220, "z", 0)
	hallWall("HallW", Vector3.new(-160, 0, 0), 220, "z", -60)
	for index = 1, 7 do
		local x = -150 + (index - 1) * 50
		b:part(
			"RoofBeam" .. index,
			Vector3.new(3, 3, 220),
			CFrame.new(x, hallH + 1.5, 0),
			C.metal,
			"Metal",
			{ query = false }
		)
	end
	-- Convoyeur et portiques.
	b:block("Conveyor", 0, 0, 240, 10, 1.5, Color3.fromRGB(40, 40, 44), "DiamondPlate")
	for index = 1, 6 do
		local x = -100 + (index - 1) * 40
		b:block("ArchS" .. index, x, -8, 2, 2, 10, C.metal, "Metal")
		b:block("ArchN" .. index, x, 8, 2, 2, 10, C.metal, "Metal")
		b:block("ArchTop" .. index, x, 0, 2, 18, 2, C.orange, "Neon", { base = 10 })
	end
	-- Exécuteurs en cours de fabrication (s'activent à l'approche).
	for _, x in { -90, -30, 30, 90 } do
		b:robotSpawn(Vector3.new(x, 1.5, 0), { RobotId = "executor", Garrison = true, Dormant = true })
	end
	-- Machines (couverts) de part et d'autre de la chaîne.
	for _, x in { -120, -80, -40, 40, 80, 120 } do
		b:block("MachineS" .. x, x, -40, 10, 8, 6, C.rust, "CorrodedMetal")
		b:block("MachineN" .. x, x, 40, 10, 8, 6, C.rust, "CorrodedMetal")
	end
	-- Bras robotique : support au plafond (le Gardien se tient dessous).
	b:part(
		"ArmMount",
		Vector3.new(4, 20, 4),
		CFrame.new(0, hallH - 10, 30),
		C.metal,
		"Metal",
		{ collide = false, query = false }
	)
	b:riskZone(Vector3.new(0, 0, 30), 25, true)
	b:crate(Vector3.new(-12, 0, 54), "axiom_locker")
	b:crate(Vector3.new(12, 0, 54), "axiom_locker")
	b:crate(Vector3.new(-150, 0, -100), "military")
	b:crate(Vector3.new(150, 0, 100), "military")
	for _, position in
		{
			Vector3.new(-100, 0, -70),
			Vector3.new(100, 0, -70),
			Vector3.new(-100, 0, 75),
			Vector3.new(100, 0, 75),
			Vector3.new(0, 0, -70),
			Vector3.new(-60, 0, -20),
			Vector3.new(60, 0, 20),
		}
	do
		b:crate(position, "supply")
	end
	-- Panneau de contrôle (créé par la mécanique : objet destructible) et sortie de production.
	b:block("PanelPedestal", -140, 30, 6, 4, 1, C.darkConcrete, "Concrete")
	b.layout.data.panel = { position = Vector3.new(-140, 1, 30), size = Vector3.new(4, 5, 1.5) }
	b.layout.data.productionExit = Vector3.new(135, 0, 0)

	-- Fonderie (ouest) ------------------------------------------------------------
	b:wall(
		"FoundryS",
		Vector3.new(-265, 0, -60),
		130,
		30,
		"x",
		{ offset = 40, width = 16, bottom = 0, top = 14 },
		WALL,
		"Concrete"
	)
	b:wall("FoundryN", Vector3.new(-265, 0, 120), 130, 30, "x", nil, WALL, "Concrete")
	b:wall(
		"FoundryE",
		Vector3.new(-200, 0, 30),
		180,
		30,
		"z",
		{ offset = 0, width = 16, bottom = 0, top = 14 },
		WALL,
		"Concrete"
	)
	b:wall("FoundryW", Vector3.new(-330, 0, 30), 180, 30, "z", nil, WALL, "Concrete")
	-- Coulées de métal en fusion.
	for index, pool in
		{
			{ x0 = -310, x1 = -250, z0 = -40, z1 = 60 },
			{ x0 = -310, x1 = -250, z0 = 75, z1 = 110 },
		}
	do
		local cx, cz = (pool.x0 + pool.x1) / 2, (pool.z0 + pool.z1) / 2
		local w, d = pool.x1 - pool.x0, pool.z1 - pool.z0
		b:block("Molten" .. index, cx, cz, w, d, 0.4, MOLTEN, "Neon", { query = false })
		b:hazard({ kind = "molten", center = Vector3.new(cx, 0, cz), size = Vector3.new(w, 0, d), height = 5 })
	end
	-- Plateformes et passerelles (y = 8).
	b:block("PlatformE", -230, 10, 24, 24, 8, C.metal, "DiamondPlate")
	b:block("PlatformW", -320, 10, 16, 24, 8, C.metal, "DiamondPlate")
	b:block("PlatformNE", -230, 95, 24, 24, 8, C.metal, "DiamondPlate")
	b:block("PlatformNW", -320, 92, 16, 20, 8, C.metal, "DiamondPlate")
	b:slab("Catwalk1", -312, 8.5, -242, 11.5, 8, C.metal, "DiamondPlate")
	b:slab("Catwalk2", -312, 90.5, -242, 93.5, 8, C.metal, "DiamondPlate")
	b:ramp("PlatformERamp", Vector3.new(-230, 0, -26), Vector3.new(-230, 8, -2), 6, C.metal, "DiamondPlate")
	b:ramp("PlatformNERamp", Vector3.new(-230, 0, 131 - 12), Vector3.new(-230, 8, 107), 6, C.metal, "DiamondPlate")
	b:crate(Vector3.new(-320, 8, 10), "military")
	b:crate(Vector3.new(-320, 8, 94), "military")
	b:crate(Vector3.new(-226, 8, 14), "supply")
	b:crate(Vector3.new(-280, 0, 67), "supply")
	b:riskZone(Vector3.new(-230, 8, 6), 10, false)

	-- Entrepôt de pièces (est) ------------------------------------------------------
	local warehouse = b:building({
		x = 265,
		z = -20,
		w = 130,
		d = 160,
		floors = 1,
		floorHeight = 20,
		doors = { "s", "n", "w" },
		windows = false,
		color = WALL,
		name = "Warehouse",
	})
	for _, x in { 215, 240, 265, 290, 315 } do
		b:block("Shelf" .. x, x, -20, 3, 100, 10, C.rust, "Metal")
	end
	for _, x in { 227.5, 252.5, 277.5, 302.5 } do
		for _, z in { -50, -10, 20 } do
			b:crate(Vector3.new(x, 0, z), "parts_bin")
		end
	end
	b:riskZone(Vector3.new(265, 0, -20), 30, false)

	-- Extractions ---------------------------------------------------------------
	-- Quai de chargement.
	b:block("Dock", 0, -310, 60, 20, 4, C.darkConcrete, "Concrete")
	b:ramp("DockRamp", Vector3.new(0, 0, -280), Vector3.new(0, 4, -299), 12, C.darkConcrete, "Concrete")
	b:extraction(Vector3.new(0, 4, -310), "extraction.forge_7.dock")
	b:crate(Vector3.new(24, 4, -314), "supply")
	-- Monte-charge.
	b:block("Lift", -300, -250, 22, 22, 0.5, Color3.fromRGB(50, 50, 56), "DiamondPlate")
	for index, corner in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
		b:block("LiftPost" .. index, -300 + corner.X * 12, -250 + corner.Z * 12, 1.5, 1.5, 24, C.orange, "Metal")
	end
	b:extraction(Vector3.new(-300, 0.5, -250), "extraction.forge_7.lift")
	-- Toit de la cheminée.
	local chimney = b:building({
		x = 300,
		z = -270,
		w = 36,
		d = 36,
		floors = 3,
		doors = { "n", "w" },
		roofAccess = true,
		name = "Chimney",
	})
	b:part(
		"Stack",
		Vector3.new(30, 10, 10),
		CFrame.new(312, chimney.roof + 15, -258) * CFrame.Angles(0, 0, math.rad(90)),
		C.rust,
		"CorrodedMetal",
		{
			shape = "Cylinder",
		}
	)
	b:extraction(Vector3.new(298, chimney.roof, -272), "extraction.forge_7.chimney")
	b:crate(chimney.spots[2][1], "supply")
	b:crate(chimney.spots[3][2], "military")

	-- Cour : conteneurs, caisses, Accélérateurs, patrouilles ---------------------------
	local reserved: { LayoutBuilder.Reserved } = {
		{ x = 0, z = 0, r = 200 },
		{ x = -265, z = 30, r = 110 },
		{ x = 265, z = -20, r = 110 },
		{ x = 0, z = -305, r = 40 },
		{ x = -300, z = -250, r = 22 },
		{ x = 300, z = -270, r = 32 },
	}
	local containers = LayoutBuilder.freePoints(rng, 14, 360, reserved, 40)
	for index, point in containers do
		local alongX = index % 2 == 0
		local colors = { C.rust, Color3.fromRGB(40, 90, 120), Color3.fromRGB(120, 40, 40), Color3.fromRGB(70, 90, 50) }
		local color = colors[(index % #colors) + 1]
		b:block(
			"Container" .. index,
			point.X,
			point.Z,
			if alongX then 14 else 6,
			if alongX then 6 else 14,
			6,
			color,
			"CorrodedMetal"
		)
		if index % 2 == 1 then
			b:block("ContainerTop" .. index, point.X, point.Z, 6, 14, 6, color, "CorrodedMetal", { base = 6 })
		end
		table.insert(reserved, { x = point.X, z = point.Z, r = 10 })
		b:crate(point + (if alongX then Vector3.new(0, 0, 6) else Vector3.new(6, 0, 0)), "supply")
	end
	-- Couverts : murets, piles de tuyaux, bennes.
	local covers = LayoutBuilder.freePoints(rng, 34, 360, reserved, 26)
	for index, point in covers do
		local kind = index % 3
		if kind == 0 then
			b:block("LowWall" .. index, point.X, point.Z, 12, 2, 4, C.darkConcrete, "Concrete")
		elseif kind == 1 then
			b:block("Pipes" .. index, point.X, point.Z, 3, 16, 3, C.rust, "CorrodedMetal")
		else
			b:block("Skip" .. index, point.X, point.Z, 8, 5, 4, Color3.fromRGB(90, 96, 60), "Metal")
		end
		table.insert(reserved, { x = point.X, z = point.Z, r = 9 })
	end
	local open = LayoutBuilder.freePoints(rng, 26, 360, reserved, 30)
	for index, point in open do
		if index <= 6 then
			b:accelerator(point)
		elseif index <= 14 then
			b:robotSpawn(point)
		else
			b:crate(point, "supply")
		end
	end

	-- Habillage ------------------------------------------------------------------
	Dress.reserve(b)
	b:keepOut(0, 30, 13) -- le bras du Gardien a besoin d'air
	b:keepOut(135, 0, 9) -- sortie de la chaîne de production
	b:keepOut(-140, 30, 8) -- panneau de contrôle

	-- Grand hall : toiture (verrière ouverte au-dessus de la chaîne), passerelles hautes
	-- le long des murs nord et sud, lampes suspendues aux poutres.
	b:slab("HallRoofS", -161, -111, 161, -22, hallH + 4, C.darkConcrete, "Metal")
	b:slab("HallRoofN", -161, 22, 161, 111, hallH + 4, C.darkConcrete, "Metal")
	for _, side in { -1, 1 } do
		local name = if side < 0 then "S" else "N"
		local wallZ, railZ, rampZ = side * 109.4, side * 101.2, side * 97.5
		b:slab(
			"Catwalk" .. name,
			-150,
			math.min(wallZ, side * 101),
			150,
			math.max(wallZ, side * 101),
			18,
			C.metal,
			"DiamondPlate"
		)
		b:block("CatwalkRail" .. name, 0, railZ, 276, 0.4, 3, C.orange, "Metal", { base = 18 })
		for _, endSide in { -1, 1 } do
			local tag = name .. (if endSide < 0 then "W" else "E")
			b:slab(
				"CatwalkLanding" .. tag,
				endSide * 150,
				math.min(side * 101, side * 94),
				endSide * 139,
				math.max(side * 101, side * 94),
				18,
				C.metal,
				"DiamondPlate"
			)
			b:ramp(
				"CatwalkRamp" .. tag,
				Vector3.new(endSide * 99, 0, rampZ),
				Vector3.new(endSide * 139.5, 18, rampZ),
				6,
				C.metal,
				"DiamondPlate"
			)
			b:keepOut(endSide * 93, rampZ, 6, -1, 9) -- pied de la rampe
		end
		for x = -120, 120, 60 do
			if b:isFree(x, 0, side * 105, 1, 16) then
				b:block("CatwalkPost" .. name .. x, x, side * 105, 1, 1, 17, C.metal, "Metal")
			end
		end
	end
	for index = 1, 7 do
		local x = -150 + (index - 1) * 50
		for _, z in { -66, 66 } do
			b:part(
				"HallLampCable" .. index .. z,
				Vector3.new(0.15, 8, 0.15),
				CFrame.new(x, hallH - 4, z),
				C.metal,
				"Metal",
				{
					collide = false,
					query = false,
				}
			)
			Dress.glow(
				b,
				"HallLamp" .. index .. z,
				Vector3.new(x, hallH - 8.3, z),
				Vector3.new(2.4, 0.5, 2.4),
				Color3.fromRGB(255, 214, 160),
				52,
				1.5,
				(index + z) % 3 == 0
			)
		end
	end
	Dress.scatter(b, rng, {
		"machine",
		"machine",
		"press",
		"pod",
		"pod",
		"pallet",
		"crates",
		"pipeRack",
		"forklift",
		"controlDesk",
		"workbench",
		"spool",
		"barrels",
		"railCart",
	}, 100, { x0 = -152, x1 = 152, z0 = -92, z1 = 92 }, 0, "grid")

	-- Fonderie : creusets, braises et lueur des coulées.
	for index, glow in
		{
			Vector3.new(-296, 3, -20),
			Vector3.new(-264, 3, 10),
			Vector3.new(-296, 3, 40),
			Vector3.new(-264, 3, 92),
			Vector3.new(-296, 3, 92),
		}
	do
		b:part("MoltenGlow" .. index, Vector3.new(6, 0.3, 6), CFrame.new(glow), MOLTEN, "Neon", {
			collide = false,
			query = false,
			transparency = 1,
			emitter = "embers",
			light = { color = MOLTEN, range = 44, brightness = 2, flicker = false, emergency = true },
		})
	end
	Dress.scatter(
		b,
		rng,
		{ "crucible", "crucible", "tank", "pipeRack", "barrels", "pallet", "railCart", "generator", "machine" },
		18,
		{ x0 = -326, x1 = -204, z0 = -56, z1 = 116 },
		0,
		"grid"
	)

	-- Entrepôt : rayonnages, palettes, chariots ; plafonniers.
	Dress.interiors(
		b,
		rng,
		{ warehouse },
		{ "shelf", "shelf", "pallet", "pallet", "crates", "forklift", "lockers", "workbench" },
		44
	)
	for index, x in { 225, 265, 305 } do
		for _, z in { -70, -20, 30 } do
			Dress.glow(
				b,
				"WarehouseLamp" .. index .. z,
				Vector3.new(x, 18.4, z),
				Vector3.new(3, 0.3, 3),
				Color3.fromRGB(255, 226, 180),
				40,
				1.3,
				(index + z) % 2 == 0
			)
		end
	end
	Dress.interiors(b, rng, { chimney }, { "lockers", "desk", "cabinet", "crates", "workbench" }, 3)
	Dress.roofs(b, rng, { chimney }, { "vent", "acUnit" }, 2)

	-- Cheminées qui fument encore.
	for _, stack in
		{
			Vector3.new(-352, 0, 160),
			Vector3.new(-352, 0, -104),
			Vector3.new(196, 0, 150),
			Vector3.new(232, 0, 152),
			Vector3.new(-186, 0, -150),
		}
	do
		Props.place(b, "chimney", stack.X, 0, stack.Z, 0, rng)
	end

	-- Cour : conteneurs, cuves, tuyauteries, projecteurs.
	Dress.spawnCover(b, rng, { "container", "barrier", "pallet", "barrierRow" })
	Dress.scatter(b, rng, { "floodlight" }, 16, { x0 = -370, x1 = 370, z0 = -370, z1 = 370 }, 0, "grid")
	Dress.ring(b, rng, {
		"container",
		"containerStack",
		"containerStack",
		"tank",
		"pipeRack",
		"spool",
		"pallet",
		"barrels",
		"generator",
		"forklift",
		"sheetFence",
		"tires",
		"van",
		"fireBarrel",
		"railCart",
		"rubble",
		"crates",
	}, 240, 112, 380)

	-- Horizon : ateliers et silos au pied de l'enceinte.
	Dress.skyline(b, rng, SIZE, {
		colors = { Color3.fromRGB(70, 62, 56), Color3.fromRGB(88, 70, 56), Color3.fromRGB(54, 52, 52) },
		material = "Brick",
		height = { min = 26, max = 78 },
		width = { min = 30, max = 62 },
		glow = { C.orange, MOLTEN },
		glowChance = 0.3,
	})

	-- Points de départ du mode solo : 16, répartis sur toute la carte (en dernier,
	-- pour tenir compte des décors).
	Dress.soloSpawns(b, rng, SIZE)
	return b:finish()
end
