--!strict
--[[
	Néo-Lumen, ville en ruine (section 12.1) — greybox.

	- Tour Helix 🔥 (centre) : gratte-ciel de 7 niveaux à moitié effondré,
	  loot vertical (le meilleur au sommet), Gardien sur le toit (Titan
	  d'Helix). Escaliers (rampes intérieures) ou grappin.
	- Galerie Prisma (sud-est) : centre commercial, combats rapprochés,
	  beaucoup de caisses.
	- Hôpital Saint-Circuit (sud-ouest) : soins et batteries de bouclier.
	- Extractions : héliport sur un toit, place centrale, sortie du métro.
	- Mécanique : 4 édifices s'effondrent pendant la partie (2 immeubles
	  tombent dans la rue et la ferment, 2 barricades s'écroulent et
	  ouvrent un passage).
]]

local LayoutBuilder = require(script.Parent.LayoutBuilder)

local C = LayoutBuilder.colors
local SIZE = 800

local ASPHALT = Color3.fromRGB(48, 50, 56)
local FACADE = Color3.fromRGB(92, 90, 104)

-- Décombres d'un effondrement (ajoutés à ce moment-là).
local function rubble(
	center: Vector3,
	spread: Vector3,
	count: number,
	height: number,
	rng: LayoutBuilder.Rng
): { LayoutBuilder.PartSpec }
	local temp = LayoutBuilder.new(C.darkConcrete, "Slate")
	for index = 1, count do
		local offset =
			Vector3.new(rng:NextNumber(-spread.X / 2, spread.X / 2), 0, rng:NextNumber(-spread.Z / 2, spread.Z / 2))
		local size = Vector3.new(rng:NextNumber(6, 14), rng:NextNumber(height * 0.4, height), rng:NextNumber(6, 14))
		temp:part(
			"Rubble" .. index,
			size,
			CFrame.new(center + offset + Vector3.new(0, size.Y / 2 - 1, 0))
				* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi), rng:NextNumber(-0.3, 0.3)),
			C.darkConcrete,
			"Slate"
		)
	end
	return temp:finish().parts
end

return function(rng: LayoutBuilder.Rng): LayoutBuilder.Layout
	local b = LayoutBuilder.new(FACADE, "Concrete")
	b:ground(SIZE, ASPHALT, "Asphalt")
	b:borderSpawns(SIZE, 25)

	-- Tour Helix 🔥 ------------------------------------------------------------
	local helix = b:building({
		x = 0,
		z = 0,
		w = 40,
		d = 40,
		floors = 7,
		doors = { "n", "s", "e", "w" },
		roofAccess = true,
		color = Color3.fromRGB(80, 84, 100),
		name = "Helix",
	})
	-- Morceaux effondrés au pied de la tour (couverts).
	b:part(
		"HelixDebris1",
		Vector3.new(26, 8, 10),
		CFrame.new(32, 3, 18) * CFrame.Angles(0, 0.4, 0.25),
		C.darkConcrete,
		"Slate"
	)
	b:part(
		"HelixDebris2",
		Vector3.new(18, 6, 12),
		CFrame.new(-30, 2, -24) * CFrame.Angles(0.2, -0.6, 0),
		C.darkConcrete,
		"Slate"
	)
	b:part(
		"HelixNeon",
		Vector3.new(0.4, 90, 0.4),
		CFrame.new(20.5, 45, 20.5),
		C.magenta,
		"Neon",
		{ collide = false, query = false }
	)
	b:crate(helix.spots[1][2], "supply")
	b:crate(helix.spots[2][1], "supply")
	b:crate(helix.spots[3][3], "supply")
	b:crate(helix.spots[4][1], "military")
	b:crate(helix.spots[5][2], "military")
	b:crate(helix.spots[6][1], "military")
	b:crate(helix.spots[8][1], "axiom_locker")
	b:crate(helix.spots[8][2], "axiom_locker")
	b:riskZone(Vector3.new(4, helix.roof, 0), 12, true) -- Gardien et garnison sur le toit

	-- Galerie Prisma ------------------------------------------------------------
	local galerie = b:building({
		x = 210,
		z = -170,
		w = 110,
		d = 70,
		floors = 2,
		doors = { "n", "s", "e", "w" },
		color = Color3.fromRGB(70, 66, 86),
		name = "Prisma",
	})
	for index, offset in { -35, -10, 15, 38 } do
		b:block("PrismaShop" .. index, 210 + offset, -170 + 8, 3, 18, 6, C.darkConcrete, "Concrete")
		b:part(
			"PrismaSign" .. index,
			Vector3.new(10, 1.2, 0.3),
			CFrame.new(210 + offset, 11, -170 - 35.7),
			if index % 2 == 0 then C.cyan else C.magenta,
			"Neon",
			{ collide = false, query = false }
		)
	end
	for level = 1, 2 do
		for _, spot in galerie.spots[level] do
			b:crate(spot, "supply")
		end
	end
	b:crate(Vector3.new(250, 0, -150), "supply")
	b:crate(Vector3.new(175, 14, -185), "supply")
	b:crate(Vector3.new(230, 14, -150), "military")
	b:crate(Vector3.new(190, 0, -150), "military")
	b:riskZone(Vector3.new(210, 0, -170), 40, false)

	-- Hôpital Saint-Circuit -------------------------------------------------------
	local hospital = b:building({
		x = -220,
		z = -170,
		w = 70,
		d = 50,
		floors = 3,
		doors = { "n", "e" },
		color = Color3.fromRGB(200, 204, 210),
		name = "Hospital",
	})
	b:part(
		"HospitalCross",
		Vector3.new(8, 8, 0.4),
		CFrame.new(-220, 34, -144.8),
		C.red,
		"Neon",
		{ collide = false, query = false }
	)
	for level = 1, 3 do
		b:crate(hospital.spots[level][1], "medical")
		b:crate(hospital.spots[level][2], "medical")
	end
	b:crate(hospital.spots[3][3], "military")
	b:riskZone(Vector3.new(-220, 0, -170), 30, false)

	-- Extractions ---------------------------------------------------------------
	-- Héliport sur un toit.
	local heliport = b:building({
		x = -260,
		z = 260,
		w = 40,
		d = 40,
		floors = 3,
		doors = { "s", "e" },
		roofAccess = true,
		name = "Heliport",
	})
	b:part(
		"Helipad",
		Vector3.new(0.2, 22, 22),
		CFrame.new(-252, heliport.roof + 0.1, 260) * CFrame.Angles(0, 0, math.rad(90)),
		C.cyan,
		"Neon",
		{
			shape = "Cylinder",
			collide = false,
			query = false,
			transparency = 0.6,
		}
	)
	b:extraction(Vector3.new(-252, heliport.roof, 260), "extraction.neo_lumen.heliport")
	b:crate(heliport.spots[2][1], "supply")

	-- Place centrale (fontaine, bancs).
	b:block("PlazaFloor", 120, 150, 90, 90, 0.4, Color3.fromRGB(110, 108, 118), "Pavement")
	b:part(
		"Fountain",
		Vector3.new(3, 18, 18),
		CFrame.new(120, 1.5, 150) * CFrame.Angles(0, 0, math.rad(90)),
		C.concrete,
		"Marble",
		{ shape = "Cylinder" }
	)
	for index, offset in
		{ Vector3.new(-25, 0, -25), Vector3.new(25, 0, -25), Vector3.new(-25, 0, 25), Vector3.new(25, 0, 25) }
	do
		b:block("Bench" .. index, 120 + offset.X, 150 + offset.Z, 8, 2, 2.5, C.metal, "Metal", { base = 0.4 })
	end
	b:extraction(Vector3.new(120, 0.4, 120), "extraction.neo_lumen.plaza")
	b:crate(Vector3.new(150, 0.4, 180), "supply")

	-- Sortie du tunnel de métro.
	b:block("MetroWallW", 290, 310, 2, 40, 12, C.darkConcrete, "Concrete")
	b:block("MetroWallE", 310, 310, 2, 40, 12, C.darkConcrete, "Concrete")
	b:block("MetroRoof", 300, 310, 22, 40, 2, C.darkConcrete, "Concrete", { base = 12 })
	b:part(
		"MetroSign",
		Vector3.new(8, 2, 0.3),
		CFrame.new(300, 15, 289.8),
		C.cyan,
		"Neon",
		{ collide = false, query = false }
	)
	b:extraction(Vector3.new(300, 0, 276), "extraction.neo_lumen.metro")
	b:crate(Vector3.new(300, 0, 320), "supply")

	-- Effondrements -----------------------------------------------------------
	local collapses = b.layout.collapses
	-- Immeubles qui tombent dans la rue (la ferment).
	b:building({
		x = -110,
		z = 60,
		w = 26,
		d = 26,
		floors = 5,
		doors = { "e" },
		group = "collapse_1",
		name = "Leaning1",
	})
	table.insert(collapses, {
		id = "collapse_1",
		kind = "building",
		center = Vector3.new(-92, 0, 60),
		size = Vector3.new(60, 30, 34),
		rubble = rubble(Vector3.new(-88, 0, 60), Vector3.new(40, 0, 26), 9, 12, rng),
	})
	b:building({
		x = 110,
		z = -60,
		w = 26,
		d = 26,
		floors = 5,
		doors = { "w" },
		group = "collapse_2",
		name = "Leaning2",
	})
	table.insert(collapses, {
		id = "collapse_2",
		kind = "building",
		center = Vector3.new(92, 0, -60),
		size = Vector3.new(60, 30, 34),
		rubble = rubble(Vector3.new(88, 0, -60), Vector3.new(40, 0, 26), 9, 12, rng),
	})
	-- Barricades qui s'écroulent (ouvrent un passage).
	b:block("Barrier3", -40, -120, 34, 3, 12, C.darkConcrete, "Slate", { group = "collapse_3" })
	table.insert(collapses, {
		id = "collapse_3",
		kind = "barrier",
		center = Vector3.new(-40, 0, -120),
		size = Vector3.new(34, 14, 10),
		rubble = rubble(Vector3.new(-40, 0, -120), Vector3.new(30, 0, 8), 4, 2.5, rng),
	})
	b:block("Barrier4", 120, 200, 3, 34, 12, C.darkConcrete, "Slate", { group = "collapse_4" })
	table.insert(collapses, {
		id = "collapse_4",
		kind = "barrier",
		center = Vector3.new(120, 0, 200),
		size = Vector3.new(10, 14, 34),
		rubble = rubble(Vector3.new(120, 0, 200), Vector3.new(8, 0, 30), 4, 2.5, rng),
	})

	-- Ville de remplissage --------------------------------------------------------
	local reserved: { LayoutBuilder.Reserved } = {
		{ x = 0, z = 0, r = 40 },
		{ x = 210, z = -170, r = 75 },
		{ x = -220, z = -170, r = 55 },
		{ x = -260, z = 260, r = 35 },
		{ x = 120, z = 150, r = 55 },
		{ x = 300, z = 300, r = 35 },
		{ x = -110, z = 60, r = 30 },
		{ x = 110, z = -60, r = 30 },
	}
	b:cityGrid(rng, {
		from = -320,
		to = 320,
		step = 80,
		reserved = reserved,
		chance = 0.45,
		size = { min = 22, max = 34 },
		floors = { min = 1, max = 3 },
		crateChance = 0.75,
		crateType = "supply",
		color = FACADE,
		prefix = "Ruin",
	})

	-- Carrefours : Accélérateurs, patrouilles, caisses de rue.
	local barriers: { LayoutBuilder.Reserved } = table.clone(reserved)
	table.insert(barriers, { x = -40, z = -120, r = 20 })
	table.insert(barriers, { x = 120, z = 200, r = 20 })
	local crossings = LayoutBuilder.shuffle(rng, LayoutBuilder.intersections(-320, 320, 80, barriers))
	for index = 1, 6 do
		b:accelerator(crossings[index])
	end
	for index = 7, 14 do
		b:robotSpawn(crossings[index])
	end
	for index = 15, 26 do
		b:crate(crossings[index] + Vector3.new(6, 0, 6), "supply")
	end
	return b:finish()
end
