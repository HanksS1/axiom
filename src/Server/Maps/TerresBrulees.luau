--!strict
--[[
	Les Terres Brûlées, désert irradié (section 12.3).

	- Le Cratère 🔥 (centre) : point d'impact en terrasses, très irradié,
	  Gardien au fond (Ver de Silice).
	- Base militaire Kestrel (nord-ouest) : bunkers, armes lourdes, tourelles
	  d'AXIOM (fixes, destructibles).
	- Caravane-cimetière (sud-est) : convoi abandonné, combats à découvert.
	- Mécanique : zones de radiation (brume verdâtre) : -5 bouclier/s, puis
	  -3 PV/s quand le bouclier est vide. Le meilleur loot s'y trouve.
	- Extractions : piste d'atterrissage, station-service, sommet du canyon.
]]

local Dress = require(script.Parent.Dress)
local LayoutBuilder = require(script.Parent.LayoutBuilder)
local Props = require(script.Parent.Props)

local C = LayoutBuilder.colors
local SIZE = 800
local HALF = SIZE / 2

local SAND = Color3.fromRGB(196, 168, 116)
local OLIVE = Color3.fromRGB(96, 104, 70)
local HAZE = Color3.fromRGB(120, 255, 90)

-- Brume de radiation (visuel) + zone dangereuse.
local function radiation(b: LayoutBuilder.Builder, name: string, center: Vector3, radius: number, height: number)
	b:part(
		name,
		Vector3.new(height, radius * 2, radius * 2),
		CFrame.new(center + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		HAZE,
		"ForceField",
		{ shape = "Cylinder", transparency = 0.82, collide = false, query = false }
	)
	b:hazard({ kind = "radiation", center = center, radius = radius, height = height })
end

return function(rng: LayoutBuilder.Rng): LayoutBuilder.Layout
	local b = LayoutBuilder.new(C.rock, "Rock")

	-- Sol percé au centre (cratère de 200 × 200).
	local hole = 100
	b:part("GroundN", Vector3.new(SIZE, 4, HALF - hole), CFrame.new(0, -2, (HALF + hole) / 2), SAND, "Sand")
	b:part("GroundS", Vector3.new(SIZE, 4, HALF - hole), CFrame.new(0, -2, -(HALF + hole) / 2), SAND, "Sand")
	b:part("GroundE", Vector3.new(HALF - hole, 4, hole * 2), CFrame.new((HALF + hole) / 2, -2, 0), SAND, "Sand")
	b:part("GroundW", Vector3.new(HALF - hole, 4, hole * 2), CFrame.new(-(HALF + hole) / 2, -2, 0), SAND, "Sand")
	b:boundary(SIZE)
	b:borderSpawns(SIZE, 25)

	-- Le Cratère 🔥 : terrasses (-10, -20) et fond (-30), rampes sur les 4 côtés.
	local terraces = { { outer = 100, inner = 80, top = -10 }, { outer = 80, inner = 60, top = -20 } }
	for index, ring in terraces do
		local depth = ring.top + 40
		local o, i = ring.outer, ring.inner
		local function solid(name: string, x0: number, z0: number, x1: number, z1: number)
			b:part(
				name,
				Vector3.new(math.abs(x1 - x0), depth, math.abs(z1 - z0)),
				CFrame.new((x0 + x1) / 2, ring.top - depth / 2, (z0 + z1) / 2),
				Color3.fromRGB(150, 120, 86),
				"Sand"
			)
		end
		solid("TerraceN" .. index, -o, i, o, o)
		solid("TerraceS" .. index, -o, -o, o, -i)
		solid("TerraceE" .. index, i, -i, o, i)
		solid("TerraceW" .. index, -o, -i, -i, i)
	end
	b:part("CraterFloor", Vector3.new(120, 10, 120), CFrame.new(0, -35, 0), Color3.fromRGB(70, 90, 60), "Glass")
	for _, direction in { Vector3.new(0, 0, 1), Vector3.new(0, 0, -1), Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0) } do
		local steps = { { 104, 0, 88, -10 }, { 84, -10, 68, -20 }, { 64, -20, 50, -30 } }
		for index, step in steps do
			b:ramp(
				`CraterRamp{direction.X}{direction.Z}_{index}`,
				direction * step[1] + Vector3.new(0, step[2], 0),
				direction * step[3] + Vector3.new(0, step[4], 0),
				10,
				Color3.fromRGB(120, 96, 70),
				"Sand"
			)
		end
	end
	-- Débris de l'impact (couverts au fond).
	for index, offset in
		{ Vector3.new(-30, 0, 20), Vector3.new(28, 0, -26), Vector3.new(-20, 0, -34), Vector3.new(34, 0, 30) }
	do
		b:block("ImpactRock" .. index, offset.X, offset.Z, 10, 8, 6, C.rock, "Basalt", { base = -30 })
	end
	radiation(b, "CraterHaze", Vector3.new(0, -40, 0), 96, 46)
	b:riskZone(Vector3.new(0, -30, 0), 22, true)
	b:crate(Vector3.new(-10, -30, -12), "axiom_locker")
	b:crate(Vector3.new(14, -30, 10), "axiom_locker")
	b:crate(Vector3.new(-90, -10, 40), "military")
	b:crate(Vector3.new(70, -20, -30), "military")
	b:crate(Vector3.new(40, -30, 44), "supply")

	-- Base militaire Kestrel ----------------------------------------------------
	local base = Vector3.new(-230, 0, 220)
	for index, wall in
		{
			{ center = base + Vector3.new(0, 0, -60), length = 140, axis = "x", gap = 0 },
			{ center = base + Vector3.new(0, 0, 60), length = 140, axis = "x", gap = 30 },
			{ center = base + Vector3.new(70, 0, 0), length = 120, axis = "z", gap = -20 },
			{ center = base + Vector3.new(-70, 0, 0), length = 120, axis = "z", gap = 20 },
		}
	do
		b:wall(
			"Fence" .. index,
			wall.center,
			wall.length,
			6,
			wall.axis,
			{ offset = wall.gap, width = 14, bottom = 0, top = 6 },
			OLIVE,
			"Metal"
		)
	end
	local bunker1 = b:building({
		x = -265,
		z = 245,
		w = 34,
		d = 22,
		floors = 1,
		floorHeight = 9,
		doors = { "s", "e" },
		color = OLIVE,
		name = "Bunker1",
	})
	local bunker2 = b:building({
		x = -200,
		z = 190,
		w = 30,
		d = 22,
		floors = 1,
		floorHeight = 9,
		doors = { "n", "w" },
		color = OLIVE,
		name = "Bunker2",
	})
	local tower = b:building({
		x = -185,
		z = 255,
		w = 24,
		d = 24,
		floors = 2,
		doors = { "s" },
		roofAccess = true,
		color = OLIVE,
		name = "Watchtower",
	})
	b:crate(bunker1.spots[1][1], "military")
	b:crate(bunker1.spots[1][3], "military")
	b:crate(bunker2.spots[1][2], "military")
	b:crate(tower.spots[3][1], "military")
	b:crate(bunker2.spots[1][4], "supply")
	b:crate(base + Vector3.new(-40, 0, -40), "supply")
	-- Tourelles d'AXIOM : fixes, destructibles.
	b:robotSpawn(Vector3.new(-185 + 6, tower.roof, 255 + 6), { RobotId = "turret", Garrison = true })
	b:robotSpawn(base + Vector3.new(60, 0, -50), { RobotId = "turret", Garrison = true })
	b:robotSpawn(base + Vector3.new(-60, 0, -50), { RobotId = "turret", Garrison = true })
	b:robotSpawn(base + Vector3.new(-60, 0, 50), { RobotId = "turret", Garrison = true })
	b:riskZone(base + Vector3.new(10, 0, -25), 25, false)

	-- Caravane-cimetière ---------------------------------------------------------
	local caravan = Vector3.new(220, 0, -160)
	local trucks = 0
	for row = -1, 1 do
		for column = -2, 1 do
			trucks += 1
			local center = caravan + Vector3.new(column * 34 + 17, 0, row * 36)
			local alongX = (row + column) % 2 == 0
			if alongX then
				b:block("Trailer" .. trucks, center.X, center.Z, 18, 7, 7, C.rust, "CorrodedMetal")
				b:block("Cab" .. trucks, center.X + 12, center.Z, 6, 7, 6, Color3.fromRGB(150, 60, 40), "CorrodedMetal")
			else
				b:block("Trailer" .. trucks, center.X, center.Z, 7, 18, 7, C.rust, "CorrodedMetal")
				b:block("Cab" .. trucks, center.X, center.Z + 12, 7, 6, 6, Color3.fromRGB(150, 60, 40), "CorrodedMetal")
			end
			if trucks % 2 == 0 then
				b:crate(center + (if alongX then Vector3.new(0, 0, 8) else Vector3.new(8, 0, 0)), "supply")
			end
		end
	end
	radiation(b, "CaravanHazeA", Vector3.new(180, 0, -205), 16, 16)
	radiation(b, "CaravanHazeB", Vector3.new(265, 0, -110), 16, 16)
	b:crate(Vector3.new(180, 0, -205), "axiom_locker")
	b:crate(Vector3.new(265, 0, -110), "military")
	b:riskZone(caravan + Vector3.new(0, 0, -60), 25, false)
	-- Poche irradiée isolée (bon loot).
	radiation(b, "DuneHaze", Vector3.new(-60, 0, -290), 20, 16)
	b:crate(Vector3.new(-60, 0, -290), "military")
	b:crate(Vector3.new(-50, 0, -282), "supply")

	-- Extractions ---------------------------------------------------------------
	-- Piste d'atterrissage.
	b:block("Airstrip", 250, 290, 170, 30, 0.3, Color3.fromRGB(60, 60, 64), "Asphalt")
	for index = -4, 4 do
		b:block(
			"RunwayLightN" .. index,
			250 + index * 20,
			304,
			1,
			1,
			0.6,
			C.orange,
			"Neon",
			{ base = 0.3, collide = false }
		)
		b:block(
			"RunwayLightS" .. index,
			250 + index * 20,
			276,
			1,
			1,
			0.6,
			C.orange,
			"Neon",
			{ base = 0.3, collide = false }
		)
	end
	b:extraction(Vector3.new(250, 0.3, 290), "extraction.terres_brulees.airstrip")
	-- Station-service.
	local shop = b:building({
		x = -300,
		z = -270,
		w = 26,
		d = 18,
		floors = 1,
		floorHeight = 10,
		doors = { "n" },
		name = "GasShop",
	})
	b:block("CanopyRoof", -280, -230, 40, 24, 1, Color3.fromRGB(180, 40, 40), "Metal", { base = 11 })
	for index, corner in
		{ Vector3.new(-18, 0, -10), Vector3.new(18, 0, -10), Vector3.new(-18, 0, 10), Vector3.new(18, 0, 10) }
	do
		b:block("CanopyPost" .. index, -280 + corner.X, -230 + corner.Z, 1.5, 1.5, 11, C.white, "Metal")
	end
	b:block("Pump1", -288, -230, 2, 3, 4, C.white, "Metal")
	b:block("Pump2", -272, -230, 2, 3, 4, C.white, "Metal")
	b:extraction(Vector3.new(-280, 0, -222), "extraction.terres_brulees.gas_station")
	b:crate(shop.spots[1][3], "supply")
	-- Sommet du canyon (mesa).
	b:block("Mesa", 320, -320, 60, 60, 30, C.rock, "Sandstone")
	b:ramp("MesaRamp", Vector3.new(320, 0, -246), Vector3.new(320, 30, -291), 10, C.rock, "Sandstone")
	b:extraction(Vector3.new(320, 30, -322), "extraction.terres_brulees.canyon")
	b:crate(Vector3.new(336, 30, -340), "supply")

	-- Rochers, caisses, Accélérateurs, patrouilles ----------------------------------------
	local reserved: { LayoutBuilder.Reserved } = {
		{ x = 0, z = 0, r = 148 }, -- couvre les coins du trou carré du cratère
		{ x = base.X, z = base.Z, r = 85 },
		{ x = caravan.X, z = caravan.Z, r = 85 },
		{ x = 250, z = 290, r = 90 },
		{ x = -290, z = -250, r = 40 },
		{ x = 320, z = -300, r = 60 },
		{ x = -60, z = -290, r = 24 },
	}
	local rocks = LayoutBuilder.freePoints(rng, 40, 360, reserved, 28)
	for index, point in rocks do
		local size = rng:NextInteger(6, 14)
		b:block("Rock" .. index, point.X, point.Z, size, rng:NextInteger(5, 12), rng:NextInteger(4, 9), C.rock, "Rock")
		table.insert(reserved, { x = point.X, z = point.Z, r = size / 2 + 6 })
	end
	local open = LayoutBuilder.freePoints(rng, 46, 360, reserved, 26)
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
	-- Le cratère est un trou : rien au niveau du sol au-dessus (les décors du
	-- cratère sont posés plus bas, sur les terrasses).
	b:keepOut(0, 0, 146, -0.5)
	b:keepOut(0, 0, 15, -32, -8) -- le Ver de Silice surgit au fond
	for x = 175, 325, 30 do
		b:keepOut(x, 290, 19) -- piste d'atterrissage dégagée
	end

	-- Le Cratère : éclats de silice vitrifiée, fûts, fissures luminescentes.
	local function terrace(list: { string }, count: number, inner: number, outer: number, y: number)
		local placed, attempts = 0, 0
		while placed < count and attempts < count * 14 do
			attempts += 1
			local x, z = rng:NextNumber(-outer, outer), rng:NextNumber(-outer, outer)
			if math.max(math.abs(x), math.abs(z)) >= inner then
				if Props.place(b, list[rng:NextInteger(1, #list)], x, y, z, rng:NextNumber(0, 6), rng) then
					placed += 1
				end
			end
		end
	end
	terrace({ "shards", "boulder", "glowCrack", "radBarrels" }, 14, 18, 54, -30)
	terrace({ "shards", "boulder", "glowCrack", "radBarrels" }, 12, 63, 77, -20)
	terrace({ "boulder", "glowCrack", "radBarrels" }, 12, 83, 97, -10)
	Dress.glow(b, "CraterCore", Vector3.new(0, -29.6, 0), Vector3.new(14, 0.2, 14), HAZE, 60, 2, true, true)
	Dress.particles(b, "CraterMotes", Vector3.new(0, -28, 0), "motes", Vector3.new(60, 0.4, 60))

	-- Poches irradiées : fûts qui fuient et fissures (on les repère de loin).
	for index, pocket in { Vector3.new(180, 0, -205), Vector3.new(265, 0, -110), Vector3.new(-60, 0, -290) } do
		Props.place(b, "radBarrels", pocket.X + 7, 0, pocket.Z - 6, index, rng)
		Props.place(b, "glowCrack", pocket.X - 8, 0, pocket.Z + 7, index * 2, rng)
		Props.place(b, "shards", pocket.X - 6, 0, pocket.Z - 9, index * 3, rng)
		Dress.particles(b, "PocketMotes" .. index, pocket + Vector3.new(0, 1, 0), "motes", Vector3.new(24, 0.4, 24))
	end

	-- Route du convoi : chaussée craquelée d'est en ouest, épaves.
	Dress.groundStrip(b, "Highway", 0, -160, 772, 22, Color3.fromRGB(58, 56, 56), "Asphalt", 0.04)
	for x = -360, 360, 40 do
		Dress.groundStrip(b, "HighwayDash" .. x, x, -160, 14, 0.7, Color3.fromRGB(176, 160, 110), "SmoothPlastic", 0.1)
	end
	Dress.along(
		b,
		rng,
		{ "car", "car", "van", "bus", "tankWreck", "barrierRow", "tires" },
		13,
		-370,
		-160,
		130,
		-160,
		9,
		0.5
	)
	Dress.scatter(
		b,
		rng,
		{ "tires", "barrels", "crates", "tent", "fireBarrel", "rubbleSmall", "sandbags", "car" },
		22,
		{ x0 = 140, x1 = 300, z0 = -240, z1 = -84 },
		0
	)

	-- Base Kestrel : sacs de sable, tentes, matériel, projecteurs.
	Dress.scatter(b, rng, {
		"sandbags",
		"sandbags",
		"crates",
		"tent",
		"tankWreck",
		"barrels",
		"generator",
		"floodlight",
		"container",
		"solarArray",
		"antennaMast",
	}, 24, { x0 = base.X - 64, x1 = base.X + 64, z0 = base.Z - 54, z1 = base.Z + 54 }, 0, "grid")
	Dress.interiors(b, rng, { bunker1, bunker2, tower }, { "lockers", "crates", "desk", "cabinet", "workbench" }, 3)
	Dress.roofs(b, rng, { bunker1, bunker2 }, { "antennaMast", "vent", "sandbags" }, 2)

	-- Station-service : enseigne, épaves aux pompes.
	Dress.glow(b, "GasSign", Vector3.new(-280, 13.4, -242), Vector3.new(18, 2, 0.4), C.red, 34, 1.4, true)
	Dress.interiors(b, rng, { shop }, { "shelf", "counter", "vending" }, 3)
	Dress.scatter(
		b,
		rng,
		{ "car", "van", "tires", "barrels", "roadSign" },
		7,
		{ x0 = -330, x1 = -240, z0 = -300, z1 = -196 },
		0
	)

	-- Piste : épave d'avion, fûts.
	Props.place(b, "planeWreck", 118, 0, 246, 0.7, rng)
	Dress.scatter(
		b,
		rng,
		{ "barrels", "crates", "container", "tires", "floodlight" },
		9,
		{ x0 = 150, x1 = 360, z0 = 228, z1 = 262 },
		0
	)

	-- Ligne à haute tension abandonnée (certains pylônes sont tombés).
	for index, z in { -340, -232, 146, 250, 348 } do
		Props.place(b, if index % 2 == 0 then "pylonDown" else "pylon", -146, 0, z, 0.1 * index, rng)
	end

	-- Relief : pitons, strates et dunes cassent les lignes de tir du désert.
	Dress.spawnCover(b, rng, { "boulder", "sandbags", "car", "tires" })
	Dress.scatter(b, rng, { "spire" }, 12, { x0 = -372, x1 = 372, z0 = -372, z1 = 372 }, 0)
	Dress.scatter(b, rng, { "dune", "dune", "strata" }, 34, { x0 = -360, x1 = 360, z0 = -360, z1 = 360 }, 0)
	Dress.scatter(b, rng, { "rock", "rock", "boulder" }, 46, { x0 = -376, x1 = 376, z0 = -376, z1 = 376 }, 0)
	Dress.scatter(b, rng, {
		"deadTree",
		"deadTree",
		"deadTree",
		"bones",
		"boulder",
		"tires",
		"car",
		"solarArray",
		"pipeline",
		"barrels",
	}, 120, { x0 = -378, x1 = 378, z0 = -378, z1 = 378 }, 0)

	-- Vent de sable.
	for index, point in LayoutBuilder.freePoints(rng, 12, 340, {}, 120) do
		Dress.particles(b, "Dust" .. index, point + Vector3.new(0, 2, 0), "dust", Vector3.new(30, 0.4, 30))
	end

	-- Horizon : falaises du canyon.
	Dress.skyline(b, rng, SIZE, {
		colors = { C.rock, Color3.fromRGB(150, 118, 86), Color3.fromRGB(126, 98, 74) },
		material = "Sandstone",
		height = { min = 30, max = 84 },
		width = { min = 24, max = 60 },
	})
	return b:finish()
end
