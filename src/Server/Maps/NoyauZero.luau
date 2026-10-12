--!strict
--[[
	Noyau Zéro, data center abandonné (section 12.4) — greybox.

	- Cœur serveur 🔥 (centre) : salle d'AXIOM, baies de serveurs, Gardien =
	  projection d'AXIOM dans un corps robotique.
	- Salles de refroidissement (ouest) : brouillard froid, visibilité
	  réduite (les robots n'y voient pas à travers), embuscades.
	- Centre de contrôle (est) : écrans, terminaux, loot technologique.
	- Couloirs couverts entre les trois zones, néons de secours.
	- Mécanique : coupures de courant toutes les 2 à 3 minutes (20 s).
	- Extractions : toit des antennes, tunnel de câbles, quai de livraison.
]]

local LayoutBuilder = require(script.Parent.LayoutBuilder)

local C = LayoutBuilder.colors
local SIZE = 800

local TILE = Color3.fromRGB(38, 42, 52)
local WALL = Color3.fromRGB(58, 64, 78)
local SERVER = Color3.fromRGB(26, 28, 36)
local FOG = Color3.fromRGB(210, 230, 240)

return function(rng: LayoutBuilder.Rng): LayoutBuilder.Layout
	local b = LayoutBuilder.new(WALL, "SmoothPlastic")
	b:ground(SIZE, TILE, "Slate")
	b:borderSpawns(SIZE, 25)

	-- Cœur serveur 🔥 ---------------------------------------------------------------
	b:building({
		x = 0,
		z = 0,
		w = 120,
		d = 120,
		floors = 1,
		floorHeight = 30,
		doors = { "n", "s", "e", "w" },
		windows = false,
		color = WALL,
		name = "Core",
	})
	for _, x in { -40, -20, 20, 40 } do
		for _, z in { -28, 28 } do
			b:block(`Rack{x}_{z}`, x, z, 3, 20, 12, SERVER, "Metal")
			b:block(`RackLight{x}_{z}`, x + (if x > 0 then -1.6 else 1.6), z, 0.2, 18, 0.4, C.cyan, "Neon", {
				base = 10,
				collide = false,
				query = false,
			})
		end
	end
	b:part(
		"CoreRing",
		Vector3.new(0.6, 30, 30),
		CFrame.new(0, 29, 0) * CFrame.Angles(0, 0, math.rad(90)),
		C.red,
		"Neon",
		{
			shape = "Cylinder",
			collide = false,
			query = false,
			transparency = 0.3,
		}
	)
	b:riskZone(Vector3.new(0, 0, 0), 18, true)
	b:crate(Vector3.new(-8, 0, 6), "axiom_locker")
	b:crate(Vector3.new(8, 0, -6), "axiom_locker")
	b:crate(Vector3.new(30, 0, 25), "military")
	b:crate(Vector3.new(-30, 0, -25), "military")
	b:crate(Vector3.new(50, 0, -50), "supply")

	-- Couloirs couverts (est et ouest), avec une ouverture latérale à mi-chemin.
	local function corridor(name: string, x0: number, x1: number)
		local mid = (x0 + x1) / 2
		local length = math.abs(x1 - x0)
		for _, side in { -9, 9 } do
			b:wall(
				`{name}Wall{side}`,
				Vector3.new(mid, 0, side),
				length,
				12,
				"x",
				{ offset = 0, width = 10, bottom = 0, top = 9 },
				WALL,
				"SmoothPlastic"
			)
			b:block(
				`{name}Light{side}`,
				mid,
				side * 0.9,
				length,
				0.2,
				0.3,
				C.green,
				"Neon",
				{ base = 10, collide = false, query = false }
			)
		end
		b:block(name .. "Roof", mid, 0, length, 19, 1, WALL, "SmoothPlastic", { base = 12 })
	end
	corridor("CorridorE", 61, 179)
	corridor("CorridorW", -61, -174)

	-- Salles de refroidissement (ouest) ----------------------------------------------------
	local cooling = b:building({
		x = -220,
		z = 0,
		w = 90,
		d = 70,
		floors = 1,
		floorHeight = 16,
		doors = { "n", "e" },
		windows = false,
		name = "Cooling",
	})
	b:block("CoolingDivider", -220, 10, 2, 50, 10, WALL, "SmoothPlastic")
	for index, unit in
		{ Vector3.new(-245, 0, -20), Vector3.new(-195, 0, -20), Vector3.new(-245, 0, 22), Vector3.new(-195, 0, 22) }
	do
		b:block("CoolingUnit" .. index, unit.X, unit.Z, 10, 6, 7, Color3.fromRGB(150, 170, 190), "Metal")
	end
	-- Brouillard froid : bloque la vision des robots (tag Smoke) et gêne celle des joueurs.
	for index, fog in
		{ Vector3.new(-240, 6, -5), Vector3.new(-200, 6, 5), Vector3.new(-235, 6, 25), Vector3.new(-205, 6, -25) }
	do
		b:part("ColdFog" .. index, Vector3.new(24, 24, 24), CFrame.new(fog), FOG, "SmoothPlastic", {
			shape = "Ball",
			transparency = 0.6,
			collide = false,
			query = false,
			tags = { "Smoke" },
			attributes = { Radius = 12 },
		})
	end
	b:crate(cooling.spots[1][1], "military")
	b:crate(cooling.spots[1][2], "military")
	b:crate(Vector3.new(-245, 0, 0), "supply")
	b:crate(Vector3.new(-190, 0, 0), "supply")
	b:riskZone(Vector3.new(-220, 0, 0), 26, false)

	-- Centre de contrôle (est) ------------------------------------------------------
	local control = b:building({
		x = 220,
		z = 0,
		w = 80,
		d = 60,
		floors = 2,
		doors = { "w", "n", "s" },
		name = "Control",
	})
	for index, terminal in { Vector3.new(235, 0, -12), Vector3.new(235, 0, 12), Vector3.new(205, 0, 14) } do
		b:block("Terminal" .. index, terminal.X, terminal.Z, 6, 2, 3, SERVER, "Metal")
		b:block(
			"Screen" .. index,
			terminal.X,
			terminal.Z,
			5,
			0.3,
			3,
			C.cyan,
			"Neon",
			{ base = 3, collide = false, query = false }
		)
	end
	for level = 1, 2 do
		for _, spot in control.spots[level] do
			b:crate(spot, "tech")
		end
	end
	b:riskZone(Vector3.new(220, 14, 0), 24, false)

	-- Extractions ---------------------------------------------------------------
	-- Toit des antennes.
	local antenna = b:building({
		x = 0,
		z = 280,
		w = 40,
		d = 40,
		floors = 2,
		doors = { "s", "e" },
		roofAccess = true,
		name = "Antenna",
	})
	for index, mast in { Vector3.new(-16, 0, 296), Vector3.new(16, 0, 296) } do
		b:part("Mast" .. index, Vector3.new(1, 30, 1), CFrame.new(mast.X, antenna.roof + 15, mast.Z), C.metal, "Metal")
		b:part(
			"MastLight" .. index,
			Vector3.new(1.4, 1.4, 1.4),
			CFrame.new(mast.X, antenna.roof + 30.7, mast.Z),
			C.red,
			"Neon",
			{
				collide = false,
				query = false,
			}
		)
	end
	b:extraction(Vector3.new(6, antenna.roof, 284), "extraction.noyau_zero.antennas")
	b:crate(antenna.spots[2][1], "supply")
	-- Tunnel de câbles.
	b:block("CableTunnelN", -300, -300, 40, 2, 10, WALL, "SmoothPlastic", { base = 0 })
	b:block("CableTunnelS", -300, -318, 40, 2, 10, WALL, "SmoothPlastic")
	b:block("CableTunnelRoof", -300, -309, 40, 20, 1.5, WALL, "SmoothPlastic", { base = 10 })
	b:block("CableBundle", -300, -316, 40, 2, 2, Color3.fromRGB(20, 20, 24), "Rubber")
	b:extraction(Vector3.new(-270, 0, -309), "extraction.noyau_zero.cable_tunnel")
	b:crate(Vector3.new(-310, 0, -309), "supply")
	-- Quai de livraison.
	b:block("DeliveryDock", 300, -310, 50, 20, 4, C.darkConcrete, "Concrete")
	b:ramp("DeliveryRamp", Vector3.new(300, 0, -280), Vector3.new(300, 4, -299), 12, C.darkConcrete, "Concrete")
	b:extraction(Vector3.new(300, 4, -310), "extraction.noyau_zero.delivery_dock")
	b:crate(Vector3.new(320, 4, -314), "supply")

	-- Campus : bâtiments annexes, couverts, caisses, Accélérateurs, patrouilles --------------
	local reserved: { LayoutBuilder.Reserved } = {
		{ x = 0, z = 0, r = 90 },
		{ x = 120, z = 0, r = 30 },
		{ x = -120, z = 0, r = 30 },
		{ x = -220, z = 0, r = 60 },
		{ x = 220, z = 0, r = 55 },
		{ x = 0, z = 280, r = 35 },
		{ x = -300, z = -309, r = 30 },
		{ x = 300, z = -305, r = 35 },
	}
	b:cityGrid(rng, {
		from = -315,
		to = 315,
		step = 90,
		reserved = reserved,
		chance = 0.4,
		size = { min = 24, max = 36 },
		floors = { min = 1, max = 2 },
		crateChance = 0.7,
		crateType = "supply",
		color = WALL,
		material = "SmoothPlastic",
		prefix = "Annex",
	})
	-- Caisses supplémentaires hors des emplacements d'annexes (centres de la grille).
	local streets = table.clone(reserved)
	for gx = -315, 315, 90 do
		for gz = -315, 315, 90 do
			table.insert(streets, { x = gx, z = gz, r = 22 })
		end
	end
	for _, point in LayoutBuilder.freePoints(rng, 16, 360, streets, 30) do
		b:crate(point, "supply")
		table.insert(reserved, { x = point.X, z = point.Z, r = 4 })
	end
	b:crate(Vector3.new(-50, 0, 50), "supply")
	b:crate(Vector3.new(210, 14, -18), "military")

	-- Rues entre les annexes : couverts et repères.
	local crossings = LayoutBuilder.shuffle(rng, LayoutBuilder.intersections(-315, 315, 90, reserved))
	for index, point in crossings do
		if index <= 6 then
			b:accelerator(point)
		elseif index <= 14 then
			b:robotSpawn(point)
		elseif index <= 26 then
			b:crate(point + Vector3.new(5, 0, 5), "supply")
		elseif index <= 40 then
			b:block("Barrier" .. index, point.X - 8, point.Z, 2, 10, 4, C.darkConcrete, "Concrete")
		end
	end
	return b:finish()
end
