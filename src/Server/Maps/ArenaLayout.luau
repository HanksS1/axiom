--!strict
--[[
	ArenaLayout : description PURE de l'Arène FFA (même chaîne que les cartes :
	LayoutBuilder + Props + Dress, rendue par MapRenderer dans ArenaService).

	Industriel, néons, touche post-apocalyptique — et d'abord un terrain de jeu :
	- verticalité : trois bastions d'angle et la plateforme nord-est (rampes),
	  une passerelle au nord sous laquelle on peut passer ;
	- couverts : conteneurs, sacs de sable, barrières, caisses, tôles légères
	  (traversées par le Canon à rayons X) répartis sans recouvrir un repère ;
	- le centre sud reste dégagé pour les mannequins d'entraînement.
	- enceinte fermée : murs, puis barrière invisible (collision, sans blocage
	  des tirs) jusqu'au plafond `Config.Arena.ceiling`.
	Le décor pur (tuyaux, néons, pilastres, hologrammes) n'a ni collision ni
	blocage des tirs. Les tags `Flicker`, `Spin`, `Hologram`, `SparkBurst` sont
	animés par le client (HubAmbienceController).

	Les repères restent ceux de l'ancienne arène (elle sert aussi de petite
	carte de partie en Studio) : 8 départs, 3 extractions, 6 Accélérateurs,
	2 zones à risque, 4 patrouilles.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local Dress = require(script.Parent.Dress)
local LayoutBuilder = require(script.Parent.LayoutBuilder)
local Props = require(script.Parent.Props)

type Builder = LayoutBuilder.Builder
type Rng = LayoutBuilder.Rng

local C = LayoutBuilder.colors
local A = Config.Arena

local CONCRETE = Color3.fromRGB(70, 74, 82)
local STEEL = Color3.fromRGB(92, 98, 108)
local RUST = Color3.fromRGB(120, 72, 46)
local HAZARD = Color3.fromRGB(230, 180, 30)
local DECOR: LayoutBuilder.PartOptions = { collide = false, query = false }
-- Barrière d'enceinte : arrête les joueurs, pas les tirs ni le grappin.
local BARRIER: LayoutBuilder.PartOptions = { transparency = 1, query = false }

local ArenaLayout = {}

-- Bastions d'angle (la plateforme nord-est existe déjà : test de hauteur et de saut).
ArenaLayout.bastions = {
	{ x = -62, z = -62, ramp = "z+" },
	{ x = -62, z = 62, ramp = "x+" }, -- rampe vers l'est : l'extraction ouest reste dégagée
	{ x = 62, z = -62, ramp = "z+" },
}
ArenaLayout.bastionTop = 7
ArenaLayout.bridgeTop = 7

local function enclosure(b: Builder, size: number)
	local half = size / 2
	b:part("Floor", Vector3.new(size, 2, size), CFrame.new(0, -1, 0), CONCRETE, "Concrete")
	local barrierHeight = A.ceiling - A.wallHeight
	for index, offset in
		{ Vector3.new(half, 0, 0), Vector3.new(-half, 0, 0), Vector3.new(0, 0, half), Vector3.new(0, 0, -half) }
	do
		local alongX = offset.X == 0
		local inward = -offset.Unit
		b:part(
			"Wall" .. index,
			if alongX then Vector3.new(size, A.wallHeight, 2) else Vector3.new(2, A.wallHeight, size),
			CFrame.new(offset + Vector3.new(0, A.wallHeight / 2, 0)),
			CONCRETE,
			"Concrete"
		)
		b:part(
			"Barrier" .. index,
			if alongX then Vector3.new(size + 4, barrierHeight, 2) else Vector3.new(2, barrierHeight, size + 4),
			CFrame.new(offset + Vector3.new(0, A.wallHeight + barrierHeight / 2, 0)),
			C.white,
			"SmoothPlastic",
			BARRIER
		)
		-- Néon cyan à mi-hauteur, coupé en tronçons (certains grésillent).
		for segment = -3, 3 do
			local along = segment * (size / 7)
			local center = offset + inward * 1.15 + Vector3.new(0, 6, 0)
			local position = if alongX then center + Vector3.new(along, 0, 0) else center + Vector3.new(0, 0, along)
			local length = size / 7 - 3
			b:part(
				`Neon{index}_{segment}`,
				if alongX then Vector3.new(length, 0.4, 0.2) else Vector3.new(0.2, 0.4, length),
				CFrame.new(position),
				C.cyan,
				"Neon",
				{ collide = false, query = false, tags = if segment % 3 == 0 then { "Flicker" } else nil }
			)
		end
		-- Pilastres d'acier rouillé et conduite haute (décor).
		for segment = -4, 4 do
			local along = segment * (size / 9)
			local base = offset + inward * 1.6
			local position = if alongX then base + Vector3.new(along, 0, 0) else base + Vector3.new(0, 0, along)
			b:part(
				`Pilaster{index}_{segment}`,
				Vector3.new(1.4, A.wallHeight, 1.4),
				CFrame.new(position + Vector3.new(0, A.wallHeight / 2, 0)),
				RUST,
				"CorrodedMetal",
				DECOR
			)
		end
		local pipeAt = offset + inward * 1.9 + Vector3.new(0, 12, 0)
		b:part(
			"Pipe" .. index,
			if alongX then Vector3.new(size - 6, 1.2, 1.2) else Vector3.new(1.2, 1.2, size - 6),
			CFrame.new(pipeAt),
			STEEL,
			"Metal",
			DECOR
		)
	end
	-- Plafond invisible : aucune sortie par le haut (bottes de saut, grappin).
	b:part(
		"Ceiling",
		Vector3.new(size + 4, 2, size + 4),
		CFrame.new(0, A.ceiling + 1, 0),
		C.white,
		"SmoothPlastic",
		BARRIER
	)
end

-- Repères (identiques à l'ancienne arène).
local function markers(b: Builder, half: number)
	for index = 1, 8 do
		local angle = index / 8 * math.pi * 2 + math.pi / 8
		b:deploySpawn(Vector3.new(math.cos(angle) * (half - 10), 0, math.sin(angle) * (half - 10)))
	end
	b:extraction(Vector3.new(0, 0, -70), "extraction.arena.north")
	b:extraction(Vector3.new(65, 0, 35), "extraction.arena.east")
	b:extraction(Vector3.new(-65, 0, 35), "extraction.arena.west")
	for index = 1, 6 do
		local angle = index / 6 * math.pi * 2
		b:accelerator(Vector3.new(math.cos(angle) * 60, 0, math.sin(angle) * 60))
	end
	b:riskZone(Vector3.new(0, 0, 62), 14, true)
	b:riskZone(Vector3.new(50, 8, 50), 8, false)
	for index = 1, 4 do
		local angle = index / 4 * math.pi * 2 + math.pi / 4
		b:robotSpawn(Vector3.new(math.cos(angle) * 55, 0, math.sin(angle) * 55))
	end
end

-- Plateforme surélevée d'angle, parapets bas et rampe vers le centre.
local function bastion(b: Builder, spec: { x: number, z: number, ramp: string }, index: number)
	local top = ArenaLayout.bastionTop
	b:block(`Bastion{index}`, spec.x, spec.z, 12, 12, top, STEEL, "DiamondPlate")
	local outwardX = if spec.x > 0 then 1 else -1
	local outwardZ = if spec.z > 0 then 1 else -1
	-- Parapets côté murs (couvert accroupi), le côté centre reste ouvert.
	b:block(`BastionRailX{index}`, spec.x + outwardX * 5.5, spec.z, 1, 12, 1.4, RUST, "CorrodedMetal", { base = top })
	b:block(`BastionRailZ{index}`, spec.x, spec.z + outwardZ * 5.5, 12, 1, 1.4, RUST, "CorrodedMetal", { base = top })
	-- Rampe vers le centre (axe et sens : « z+ », « z- », « x+ », « x- »).
	local alongX = string.sub(spec.ramp, 1, 1) == "x"
	local direction = if string.sub(spec.ramp, 2, 2) == "+" then 1 else -1
	local axis = if alongX then Vector3.new(direction, 0, 0) else Vector3.new(0, 0, direction)
	local edge = Vector3.new(spec.x, 0, spec.z) + axis * 6
	b:ramp(`BastionRamp{index}`, edge + axis * 16, edge + Vector3.new(0, top, 0), 6, STEEL, "DiamondPlate")
	-- Bandes de danger au pied de la rampe (décor au sol).
	local foot = edge + axis * 17
	Dress.groundStrip(
		b,
		`BastionStripe{index}`,
		foot.X,
		foot.Z,
		if alongX then 1 else 6,
		if alongX then 6 else 1,
		HAZARD,
		"SmoothPlastic"
	)
	-- Lumière de bastion : projecteur au sommet (lisibilité).
	Dress.glow(b, `BastionLamp{index}`, Vector3.new(spec.x, top + 6, spec.z), Vector3.new(1, 0.4, 1), C.white, 40, 1.6)
end

-- Plateforme nord-est d'origine (test de hauteur, zone à risque secondaire).
local function northEastPlatform(b: Builder)
	b:block("Platform", 50, 50, 20, 20, 1, CONCRETE, "DiamondPlate", { base = 7.5 })
	for _, x in { 41, 59 } do
		for _, z in { 41, 59 } do
			b:block("PlatformLeg", x, z, 1.2, 1.2, 7.5, RUST, "CorrodedMetal")
		end
	end
	b:ramp("Ramp", Vector3.new(50, 0, 16), Vector3.new(50, 8.5, 40), 6, CONCRETE, "DiamondPlate")
	Dress.groundStrip(b, "RampStripe", 50, 15, 6, 1, HAZARD, "SmoothPlastic")
end

-- Passerelle au nord : on la parcourt en hauteur ou on passe dessous.
local function bridge(b: Builder)
	local top = ArenaLayout.bridgeTop
	b:slab("Bridge", -25, 17, 25, 23, top, STEEL, "DiamondPlate")
	for _, x in { -24, -8, 8, 24 } do
		b:block("BridgeLeg", x, 20, 1, 1, top - 1, RUST, "CorrodedMetal")
	end
	-- Garde-corps décoratifs (on peut tirer entre les barreaux).
	for _, z in { 17.2, 22.8 } do
		b:part("BridgeRail", Vector3.new(50, 0.3, 0.3), CFrame.new(0, top + 1.2, z), RUST, "Metal", DECOR)
	end
	b:ramp("BridgeRampW", Vector3.new(-41, 0, 20), Vector3.new(-25, top, 20), 6, STEEL, "DiamondPlate")
	b:ramp("BridgeRampE", Vector3.new(41, 0, 20), Vector3.new(25, top, 20), 6, STEEL, "DiamondPlate")
	-- Néons sous le tablier (repère visuel du passage).
	b:part("BridgeUnderglow", Vector3.new(48, 0.2, 0.4), CFrame.new(0, top - 1.1, 20), C.magenta, "Neon", {
		collide = false,
		query = false,
		light = { color = C.magenta, range = 18, brightness = 1.2 },
	})
end

-- Couverts légers (tôle) : un anneau, traversés par le Canon à rayons X.
local function lightCovers(b: Builder)
	for index = 1, 6 do
		local angle = index / 6 * math.pi * 2
		b:part(
			"LightCover" .. index,
			Vector3.new(8, 6, 0.4),
			CFrame.new(math.cos(angle) * 45, 3, math.sin(angle) * 45) * CFrame.Angles(0, -angle, 0),
			RUST,
			"CorrodedMetal",
			{ tags = { "LightCover" } }
		)
	end
end

-- Décor animé : anneau holographique au-dessus du centre, gerbes d'étincelles.
local function centerpiece(b: Builder)
	-- Disque vertical (axe des cylindres : X) qui tourne sur lui-même autour de la verticale.
	b:part("HoloRing", Vector3.new(0.4, 22, 22), CFrame.new(0, 22, 30), C.cyan, "ForceField", {
		shape = "Cylinder",
		collide = false,
		query = false,
		transparency = 0.55,
		tags = { "Spin", "Hologram" },
		attributes = { Speed = 0.08 },
	})
	b:part("HoloCore", Vector3.new(3, 3, 3), CFrame.new(0, 22, 30), C.cyan, "Neon", {
		shape = "Ball",
		collide = false,
		query = false,
		transparency = 0.3,
		tags = { "Hologram" },
		light = { color = C.cyan, range = 40, brightness = 1.4 },
	})
	for index, position in { Vector3.new(-88, 9, -40), Vector3.new(88, 9, 40), Vector3.new(-40, 9, 88) } do
		b:part(`JunctionBox{index}`, Vector3.new(1.4, 2, 1.4), CFrame.new(position), STEEL, "Metal", {
			collide = false,
			query = false,
			tags = { "SparkBurst" },
		})
	end
end

-- Projecteurs d'angle, fûts enflammés, éclairage d'appoint des zones sombres.
local function lights(b: Builder, rng: Rng, half: number)
	local inner = half - 4
	for _, x in { -inner, inner } do
		for _, z in { -inner, inner } do
			Props.put(b, "floodlight", x, 0, z, math.atan2(x, z), rng)
		end
	end
	for _, spot in { { -80, 0 }, { 80, -10 }, { 10, 80 }, { -55, -82 } } do
		Props.put(b, "fireBarrel", spot[1], 0, spot[2], 0, rng)
	end
	-- Plafonniers suspendus (sans collision) : lumière franche sur tout le terrain.
	for _, x in { -45, 0, 45 } do
		for _, z in { -45, 0, 45 } do
			Dress.glow(b, "Overhead", Vector3.new(x, 30, z), Vector3.new(6, 0.4, 1), C.white, 60, 1.1)
		end
	end
end

function ArenaLayout.build(rng: Rng): LayoutBuilder.Layout
	local size = Config.Dev.arenaSize
	local half = size / 2
	local b = LayoutBuilder.new(CONCRETE, "Concrete")
	enclosure(b, size)
	markers(b, half)
	northEastPlatform(b)
	for index, spec in ArenaLayout.bastions do
		bastion(b, spec, index)
	end
	bridge(b)
	lightCovers(b)
	centerpiece(b)

	-- Zones à garder libres : mannequins, pavé de retour, abords des repères.
	b:keepOut(0, -30, 20, -2, 12)
	b:keepOut(0, -82, 8, -2, 12)
	Dress.reserve(b)

	-- Couverts (posés seulement là où la place est libre).
	local inner = { x0 = -half + 10, x1 = half - 10, z0 = -half + 10, z1 = half - 10 }
	Dress.scatter(b, rng, { "container", "containerStack" }, 4, inner, 0, "grid")
	Dress.scatter(b, rng, { "sandbags", "barrierRow", "crates", "barrels", "tires", "dumpster" }, 14, inner, 0, nil)
	-- Touche post-apocalyptique le long des murs : épaves, gravats, machines à l'arrêt.
	local edge = { x0 = -half + 6, x1 = half - 6, z0 = -half + 6, z1 = half - 6 }
	Dress.ring(b, rng, { "rubble", "rubbleSmall", "generator", "spool", "pallet", "tires" }, 12, half - 18, half - 6)
	Dress.scatter(b, rng, { "rubbleSmall" }, 6, edge, 0, nil)

	lights(b, rng, half)
	Dress.particles(b, "Motes", Vector3.new(0, 12, 0), "motes", Vector3.new(size - 20, 1, size - 20))
	return b:finish()
end

return ArenaLayout
