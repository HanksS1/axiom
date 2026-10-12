--!strict
--[[
	TerminusBuilder : le Terminus, ancienne gare souterraine où survivent les
	mercenaires (section 2.3) — greybox détaillé.

	- Quai et voies effondrées, wagons abandonnés, piliers rouillés, voûte
	  percée (rais de lumière et poussière), câbles qui pendent, tuyaux qui
	  fuient (vapeur), gouttes d'eau et flaques.
	- Marché de survivants : étals bâchés (Coffre, Marchand, Armurier,
	  Assureur, Holo-Bazar), avec un PNJ derrière chaque comptoir.
	- Porte blindée de déploiement, stand de tir, Mur des Légendes.
	- Vie : feux de bidons, drones de maintenance, rongeurs mécaniques,
	  écrans d'AXIOM parasités, affiches de propagande et tags de résistance.

	Les animations sont jouées par le client (tags, voir Kit).
]]

local Kit = require(script.Parent.Kit)

local TerminusBuilder = {}

-- Palette du Terminus.
local FLOOR = Color3.fromRGB(46, 47, 52)
local WALL = Color3.fromRGB(64, 60, 58)
local DARK = Color3.fromRGB(30, 31, 36)
local RUST = Color3.fromRGB(116, 66, 40)
local METAL = Color3.fromRGB(82, 86, 94)
local TARP =
	{ Color3.fromRGB(70, 80, 60), Color3.fromRGB(110, 70, 50), Color3.fromRGB(60, 70, 90), Color3.fromRGB(90, 60, 80) }
local NEON = {
	merchant = Color3.fromRGB(57, 255, 20),
	armorer = Color3.fromRGB(255, 138, 0),
	insurer = Color3.fromRGB(0, 229, 255),
	vault = Color3.fromRGB(176, 92, 255),
	bazaar = Color3.fromRGB(255, 46, 196),
	deploy = Color3.fromRGB(255, 59, 59),
	range = Color3.fromRGB(255, 176, 32),
	legends = Color3.fromRGB(0, 229, 255),
	training = Color3.fromRGB(150, 158, 170),
}
local FIRE = Color3.fromRGB(255, 140, 40)

export type StationSpot = {
	key: string,
	counter: CFrame, -- comptoir (face côté joueurs)
	npc: CFrame, -- PNJ derrière le comptoir, tourné vers les joueurs
}

export type Built = {
	folder: Folder,
	stations: { StationSpot },
	spawns: { CFrame },
}

local random = Random.new(2077)

-- Prompt d'une station (attribut Station → écran côté client).
local function prompt(parent: BasePart, key: string)
	local p = Instance.new("ProximityPrompt")
	p:SetAttribute("ActionKey", "station.open")
	p:SetAttribute("ObjectKey", "station." .. key)
	p:SetAttribute("Station", key)
	p.ActionText = "station.open"
	p.ObjectText = "station." .. key
	p.HoldDuration = 0
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p.Parent = parent
end

-- Enseigne néon avec le nom de la station (texte localisé, grésillement occasionnel).
local function sign(parent: Instance, key: string, cframe: CFrame, width: number)
	local color = NEON[key] or NEON.training
	local board = Kit.decor(parent, "Sign_" .. key, Vector3.new(width, 1.8, 0.3), cframe, DARK, Enum.Material.Metal)
	Kit.text(board, Enum.NormalId.Front, "station." .. key, color, Enum.Font.GothamBlack)
	local frame = Kit.decor(
		parent,
		"SignNeon_" .. key,
		Vector3.new(width + 0.3, 0.15, 0.1),
		cframe * CFrame.new(0, -1, -0.2),
		color,
		Enum.Material.Neon,
		{
			tag = "Flicker",
		}
	)
	Kit.light(frame, color, 12, 0.8)
end

-- Lampe suspendue qui se balance.
local function hangingLamp(parent: Instance, position: Vector3, color: Color3, length: number)
	local model = Instance.new("Model")
	model.Name = "HangingLamp"
	local cable = Kit.decor(
		model,
		"Cable",
		Vector3.new(0.1, length, 0.1),
		CFrame.new(position - Vector3.new(0, length / 2, 0)),
		DARK,
		Enum.Material.Metal
	)
	local shade = Kit.decor(
		model,
		"Shade",
		Vector3.new(1.4, 0.6, 1.4),
		CFrame.new(position - Vector3.new(0, length, 0)),
		METAL,
		Enum.Material.CorrodedMetal
	)
	local bulb = Kit.decor(
		model,
		"Bulb",
		Vector3.new(0.6, 0.6, 0.6),
		CFrame.new(position - Vector3.new(0, length + 0.4, 0)),
		color,
		Enum.Material.Neon,
		{
			shape = Enum.PartType.Ball,
		}
	)
	Kit.light(bulb, color, 16, 1.2)
	model.PrimaryPart = cable
	model:SetAttribute("Pivot", position)
	model:SetAttribute("Amplitude", random:NextNumber(3, 7))
	Kit.tag(model, "Sway")
	model.Parent = parent
	local _ = shade
end

-- Bidon de feu (feu, fumée, lueur vacillante).
local function fireBarrel(parent: Instance, position: Vector3)
	local barrel =
		Kit.cylinder(parent, "FireBarrel", 3, 2.4, position + Vector3.new(0, 1.5, 0), RUST, Enum.Material.CorrodedMetal)
	local top = Kit.decor(
		parent,
		"FireCore",
		Vector3.new(1.8, 0.3, 1.8),
		CFrame.new(position + Vector3.new(0, 3.05, 0)),
		FIRE,
		Enum.Material.Neon
	)
	Kit.emitter(top, "Fire", {
		color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 70, 20)),
		rate = 24,
		lifetime = NumberRange.new(0.4, 0.8),
		speed = NumberRange.new(3, 5),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) }),
		lightEmission = 1,
		spread = Vector2.new(12, 12),
		direction = Enum.NormalId.Top,
	})
	Kit.emitter(top, "Smoke", {
		color = ColorSequence.new(Color3.fromRGB(60, 60, 62)),
		rate = 6,
		lifetime = NumberRange.new(2.5, 4),
		speed = NumberRange.new(2, 3),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 4) }),
		transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) }),
		spread = Vector2.new(8, 8),
		direction = Enum.NormalId.Top,
	})
	Kit.light(top, FIRE, 18, 2, true)
	local _ = barrel
end

-- Fuite de vapeur sur un tuyau.
local function steamLeak(parent: BasePart)
	Kit.emitter(parent, "Steam", {
		color = ColorSequence.new(Color3.fromRGB(220, 225, 230)),
		rate = 10,
		lifetime = NumberRange.new(1, 1.8),
		speed = NumberRange.new(4, 7),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 2.5) }),
		transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
		spread = Vector2.new(20, 20),
		direction = Enum.NormalId.Bottom,
	})
end

-- Gouttes d'eau qui tombent du plafond, avec la flaque en dessous.
local function drip(parent: Instance, position: Vector3, ceiling: number)
	local source = Kit.decor(
		parent,
		"Drip",
		Vector3.new(0.4, 0.2, 0.4),
		CFrame.new(position.X, ceiling - 0.2, position.Z),
		DARK,
		Enum.Material.Slate,
		{
			transparency = 0.5,
		}
	)
	Kit.emitter(source, "Drops", {
		color = ColorSequence.new(Color3.fromRGB(150, 180, 200)),
		rate = 3,
		lifetime = NumberRange.new(1.4, 1.6),
		speed = NumberRange.new(0, 0),
		size = NumberSequence.new(0.08),
		transparency = NumberSequence.new(0.2),
		acceleration = Vector3.new(0, -22, 0),
	})
	Kit.decor(
		parent,
		"Puddle",
		Vector3.new(random:NextNumber(3, 6), 0.05, random:NextNumber(3, 6)),
		CFrame.new(position.X, 0.03, position.Z) * CFrame.Angles(0, random:NextNumber(0, math.pi), 0),
		Color3.fromRGB(40, 50, 60),
		Enum.Material.Glass,
		{
			transparency = 0.35,
		}
	)
end

-- Pile de débris (couvert décoratif).
local function debris(parent: Instance, position: Vector3, count: number)
	for index = 1, count do
		local size = Vector3.new(random:NextNumber(0.6, 2.4), random:NextNumber(0.3, 1.2), random:NextNumber(0.6, 2.4))
		local offset = Vector3.new(random:NextNumber(-2, 2), size.Y / 2 - 0.1, random:NextNumber(-2, 2))
		Kit.part(
			parent,
			"Debris" .. index,
			size,
			CFrame.new(position + offset)
				* CFrame.Angles(
					random:NextNumber(-0.4, 0.4),
					random:NextNumber(0, math.pi),
					random:NextNumber(-0.4, 0.4)
				),
			if index % 3 == 0 then RUST else Color3.fromRGB(80, 78, 74),
			if index % 3 == 0 then Enum.Material.CorrodedMetal else Enum.Material.Slate,
			{ query = false }
		)
	end
end

-- Pile de caisses de survivants.
local function crates(parent: Instance, position: Vector3, yaw: number)
	local base = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	Kit.part(
		parent,
		"CrateA",
		Vector3.new(3, 3, 3),
		base * CFrame.new(0, 1.5, 0),
		Color3.fromRGB(104, 82, 56),
		Enum.Material.WoodPlanks
	)
	Kit.part(
		parent,
		"CrateB",
		Vector3.new(2.5, 2.5, 2.5),
		base * CFrame.new(3, 1.25, 0.4) * CFrame.Angles(0, 0.3, 0),
		Color3.fromRGB(90, 72, 50),
		Enum.Material.WoodPlanks
	)
	Kit.part(
		parent,
		"CrateC",
		Vector3.new(2.2, 2.2, 2.2),
		base * CFrame.new(0.4, 4.1, 0) * CFrame.Angles(0, -0.4, 0),
		Color3.fromRGB(70, 90, 70),
		Enum.Material.Metal
	)
end

-- Écran d'AXIOM parasité (grésille).
local function monitor(parent: Instance, cframe: CFrame, textKey: string)
	local frame = Kit.decor(parent, "Monitor", Vector3.new(3.2, 2.2, 0.4), cframe, DARK, Enum.Material.Metal)
	local screen = Kit.decor(
		parent,
		"Screen",
		Vector3.new(2.8, 1.8, 0.05),
		cframe * CFrame.new(0, 0, -0.22),
		Color3.fromRGB(255, 50, 50),
		Enum.Material.Neon,
		{
			transparency = 0.2,
			tag = "Flicker",
		}
	)
	Kit.text(screen, Enum.NormalId.Front, textKey, Color3.fromRGB(20, 0, 0), Enum.Font.Code)
	local _ = frame
end

-- Affiche (propagande d'AXIOM) ou tag de résistance sur un mur.
local function poster(
	parent: Instance,
	cframe: CFrame,
	size: Vector2,
	textKey: string,
	color: Color3,
	background: Color3?,
	rotation: number?
)
	local board = Kit.decor(
		parent,
		"Poster",
		Vector3.new(size.X, size.Y, 0.05),
		cframe,
		background or DARK,
		Enum.Material.SmoothPlastic,
		{
			transparency = if background then 0 else 1,
		}
	)
	Kit.text(
		board,
		Enum.NormalId.Front,
		textKey,
		color,
		if background then Enum.Font.GothamBlack else Enum.Font.Arcade,
		background,
		rotation
	)
end

-- Étal de marché : comptoir, étagères, bâche, lampe, enseigne.
local function stall(parent: Instance, key: string, origin: Vector3, localX: number, tarpIndex: number): StationSpot
	local model = Instance.new("Model")
	model.Name = "Stall_" .. key
	local x = origin.X + localX
	local z = origin.Z + 42
	local y = origin.Y
	local color = NEON[key]
	local counter = Kit.part(
		model,
		"Counter",
		Vector3.new(9, 3.5, 3),
		CFrame.new(x, y + 1.75, z),
		METAL,
		Enum.Material.DiamondPlate
	)
	Kit.decor(model, "CounterTrim", Vector3.new(9.1, 0.2, 3.1), CFrame.new(x, y + 3.55, z), color, Enum.Material.Neon)
	prompt(counter, key)
	-- Étagères du fond et marchandises.
	Kit.part(
		model,
		"Shelf",
		Vector3.new(11, 7, 1.5),
		CFrame.new(x, y + 3.5, z + 10),
		Color3.fromRGB(58, 52, 46),
		Enum.Material.WoodPlanks
	)
	for row = 0, 2 do
		for column = -2, 2 do
			if random:NextNumber() < 0.75 then
				local size = Vector3.new(random:NextNumber(0.6, 1.4), random:NextNumber(0.5, 1.2), 0.8)
				Kit.decor(
					model,
					"Goods",
					size,
					CFrame.new(x + column * 2, y + 1.2 + row * 2.2 + size.Y / 2, z + 9),
					if random:NextNumber() < 0.3 then color else METAL,
					if random:NextNumber() < 0.3 then Enum.Material.Neon else Enum.Material.Metal
				)
			end
		end
	end
	-- Bâche tendue sur des poteaux.
	for _, side in { -1, 1 } do
		Kit.part(
			model,
			"Post",
			Vector3.new(0.6, 11, 0.6),
			CFrame.new(x + side * 6.5, y + 5.5, z - 1.5),
			RUST,
			Enum.Material.CorrodedMetal
		)
	end
	Kit.decor(
		model,
		"Tarp",
		Vector3.new(15, 0.25, 15),
		CFrame.new(x, y + 11.4, z + 5) * CFrame.Angles(math.rad(-10), 0, math.rad(random:NextNumber(-3, 3))),
		TARP[tarpIndex],
		Enum.Material.Fabric
	)
	hangingLamp(model, Vector3.new(x + 2, y + 11, z + 2), Color3.fromRGB(255, 210, 150), 3)
	sign(model, key, CFrame.new(x, y + 9.2, z - 1.6), 8)
	model.Parent = parent
	return {
		key = key,
		counter = counter.CFrame,
		npc = CFrame.lookAt(Vector3.new(x, y, z + 4), Vector3.new(x, y, z - 10)),
	}
end

function TerminusBuilder.build(origin: Vector3): Built
	local folder = Instance.new("Folder")
	folder.Name = "Terminus"
	local stations: { StationSpot } = {}
	local W, D, H = 200, 120, 32
	local function at(x: number, y: number, z: number): Vector3
		return origin + Vector3.new(x, y, z)
	end
	local structure = Instance.new("Folder")
	structure.Name = "Structure"
	structure.Parent = folder
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = folder

	-- Coque de la gare : quai, fosse des voies, murs de brique, voûte.
	Kit.part(structure, "Platform", Vector3.new(W, 2, D - 22), CFrame.new(at(0, -1, 11)), FLOOR, Enum.Material.Concrete)
	Kit.part(
		structure,
		"TrackPit",
		Vector3.new(W, 2, 22),
		CFrame.new(at(0, -4, -49)),
		Color3.fromRGB(40, 36, 34),
		Enum.Material.Ground
	)
	Kit.decor(
		structure,
		"PlatformEdge",
		Vector3.new(W, 0.1, 1),
		CFrame.new(at(0, 0.05, -37.5)),
		Color3.fromRGB(220, 190, 40),
		Enum.Material.SmoothPlastic
	)
	Kit.part(structure, "PitWall", Vector3.new(W, 3, 1), CFrame.new(at(0, -1.5, -38.5)), WALL, Enum.Material.Concrete)
	for _, x in { -94, 94 } do
		Kit.part(
			structure,
			"PitSteps",
			Vector3.new(6, 1.5, 4),
			CFrame.new(at(x, -2.25, -40.5)),
			WALL,
			Enum.Material.Concrete
		)
	end
	Kit.part(
		structure,
		"Ceiling",
		Vector3.new(W, 2, D),
		CFrame.new(at(0, H, 0)),
		Color3.fromRGB(44, 42, 42),
		Enum.Material.Concrete
	)
	Kit.part(
		structure,
		"WallNorth",
		Vector3.new(W, H + 4, 2),
		CFrame.new(at(0, H / 2 - 2, -D / 2)),
		WALL,
		Enum.Material.Brick
	)
	Kit.part(structure, "WallSouth", Vector3.new(W, H, 2), CFrame.new(at(0, H / 2, D / 2)), WALL, Enum.Material.Brick)
	Kit.part(
		structure,
		"WallEast",
		Vector3.new(2, H + 4, D),
		CFrame.new(at(W / 2, H / 2 - 2, 0)),
		WALL,
		Enum.Material.Brick
	)
	Kit.part(
		structure,
		"WallWest",
		Vector3.new(2, H + 4, D),
		CFrame.new(at(-W / 2, H / 2 - 2, 0)),
		WALL,
		Enum.Material.Brick
	)
	-- Nervures de la voûte et piliers rouillés.
	for x = -87.5, 87.5, 25 do
		Kit.decor(structure, "Rib", Vector3.new(1.5, 1.5, D), CFrame.new(at(x, H - 1.5, 0)), DARK, Enum.Material.Metal)
	end
	for _, z in { -36, 28 } do
		for _, x in { -75, -45, -15, 15, 45, 75 } do
			Kit.part(
				structure,
				"Pillar",
				Vector3.new(3, H, 3),
				CFrame.new(at(x, H / 2, z)),
				Color3.fromRGB(76, 72, 68),
				Enum.Material.Concrete
			)
			Kit.decor(
				structure,
				"PillarRust",
				Vector3.new(3.2, 2, 3.2),
				CFrame.new(at(x, 3, z)),
				RUST,
				Enum.Material.CorrodedMetal
			)
		end
	end
	-- Voies et wagons abandonnés.
	for _, offset in { -2.4, 2.4 } do
		Kit.decor(
			structure,
			"Rail",
			Vector3.new(W, 0.4, 0.5),
			CFrame.new(at(0, -2.8, -49 + offset)),
			Color3.fromRGB(90, 70, 60),
			Enum.Material.CorrodedMetal
		)
	end
	for index, x in { -55, 5 } do
		local wagon = Instance.new("Model")
		wagon.Name = "Wagon" .. index
		local base = CFrame.new(at(x, -3, -49))
		local body = Color3.fromRGB(60, 76, 70)
		Kit.part(wagon, "Floor", Vector3.new(50, 1, 9), base * CFrame.new(0, 1.5, 0), DARK, Enum.Material.DiamondPlate)
		Kit.part(wagon, "Roof", Vector3.new(50, 0.6, 9.4), base * CFrame.new(0, 10.3, 0), body, Enum.Material.Metal)
		for _, side in { -1, 1 } do
			Kit.part(
				wagon,
				"SideLow",
				Vector3.new(50, 3.5, 0.4),
				base * CFrame.new(0, 3.75, side * 4.5),
				body,
				Enum.Material.Metal
			)
			Kit.part(
				wagon,
				"SideHigh",
				Vector3.new(50, 2, 0.4),
				base * CFrame.new(0, 9, side * 4.5),
				body,
				Enum.Material.Metal
			)
			for window = -20, 20, 8 do
				Kit.part(
					wagon,
					"Frame",
					Vector3.new(1.2, 3.5, 0.4),
					base * CFrame.new(window, 6.25, side * 4.5),
					body,
					Enum.Material.Metal
				)
			end
			Kit.decor(
				wagon,
				"Stripe",
				Vector3.new(50, 0.4, 0.45),
				base * CFrame.new(0, 5.6, side * 4.5),
				Color3.fromRGB(180, 150, 60),
				Enum.Material.SmoothPlastic
			)
		end
		for _, side in { -1, 1 } do
			Kit.part(
				wagon,
				"EndTop",
				Vector3.new(0.4, 3, 9),
				base * CFrame.new(side * 25, 8.5, 0),
				body,
				Enum.Material.Metal
			)
			for _, z in { -3.25, 3.25 } do
				Kit.part(
					wagon,
					"EndSide",
					Vector3.new(0.4, 6, 2.5),
					base * CFrame.new(side * 25, 5, z),
					body,
					Enum.Material.Metal
				)
			end
		end
		local light = Kit.decor(
			wagon,
			"WagonLight",
			Vector3.new(30, 0.2, 0.4),
			base * CFrame.new(0, 9.9, 0),
			Color3.fromRGB(200, 255, 220),
			Enum.Material.Neon,
			{
				tag = "Flicker",
			}
		)
		Kit.light(light, Color3.fromRGB(180, 255, 210), 14, 0.8)
		crates(wagon, (base * CFrame.new(-15, 2, 1)).Position, 0.3)
		Kit.decor(
			wagon,
			"Mattress",
			Vector3.new(6, 0.5, 3),
			base * CFrame.new(12, 2.25, -2),
			Color3.fromRGB(110, 96, 80),
			Enum.Material.Fabric
		)
		poster(
			wagon,
			base * CFrame.new(0, 7, -4.25) * CFrame.Angles(0, math.pi, 0),
			Vector2.new(4, 2.5),
			"hub.poster." .. index,
			Color3.fromRGB(255, 230, 230),
			Color3.fromRGB(150, 20, 20)
		)
		wagon.Parent = decor
	end

	-- Tuyaux qui fuient le long du mur nord.
	for index, y in { 24, 27 } do
		local pipe = Kit.cylinder(
			decor,
			"Pipe" .. index,
			W - 4,
			1.4,
			at(0, y, -D / 2 + 2),
			Color3.fromRGB(96, 84, 70),
			Enum.Material.CorrodedMetal,
			{
				collide = false,
				query = false,
			}
		)
		pipe.CFrame = CFrame.new(at(0, y, -D / 2 + 2))
	end
	for _, x in { -60, 10, 70 } do
		local leak = Kit.decor(
			decor,
			"Leak",
			Vector3.new(0.6, 0.6, 0.6),
			CFrame.new(at(x, 23.3, -D / 2 + 2.4)),
			METAL,
			Enum.Material.Metal
		)
		steamLeak(leak)
	end

	-- Voûte percée : rais de lumière et poussière.
	for index, hole in { Vector3.new(-30, 0, -8), Vector3.new(40, 0, 6) } do
		local beam = Kit.decor(
			decor,
			"LightShaft" .. index,
			Vector3.new(7, H, 7),
			CFrame.new(at(hole.X, H / 2, hole.Z)),
			Color3.fromRGB(255, 240, 200),
			Enum.Material.Neon,
			{
				transparency = 0.93,
			}
		)
		Kit.decor(
			decor,
			"Hole" .. index,
			Vector3.new(8, 0.3, 8),
			CFrame.new(at(hole.X, H - 1.1, hole.Z)),
			Color3.fromRGB(220, 220, 200),
			Enum.Material.Neon,
			{
				transparency = 0.4,
			}
		)
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Bottom
		spot.Angle = 40
		spot.Range = 40
		spot.Brightness = 2
		spot.Color = Color3.fromRGB(255, 240, 210)
		spot.Parent = beam
		Kit.emitter(beam, "Dust", {
			color = ColorSequence.new(Color3.fromRGB(255, 245, 220)),
			rate = 6,
			lifetime = NumberRange.new(5, 8),
			speed = NumberRange.new(0.2, 0.6),
			size = NumberSequence.new(0.08),
			transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 0.3),
				NumberSequenceKeypoint.new(1, 1),
			}),
			lightEmission = 0.6,
			spread = Vector2.new(180, 180),
		})
		debris(decor, at(hole.X + 2, 0, hole.Z + 1), 7)
	end

	-- Câbles qui pendent de la voûte (en deux segments affaissés).
	for index = 1, 10 do
		local x0 = random:NextNumber(-90, 70)
		local z0 = random:NextNumber(-30, 30)
		local span = random:NextNumber(12, 24)
		local sag = random:NextNumber(3, 7)
		local a, b, c = at(x0, H - 1, z0), at(x0 + span / 2, H - 1 - sag, z0 + 2), at(x0 + span, H - 1, z0 + 4)
		for segment, pair in { { a, b }, { b, c } } do
			local from, to = pair[1], pair[2]
			Kit.decor(
				decor,
				`Cable{index}_{segment}`,
				Vector3.new(0.15, 0.15, (to - from).Magnitude),
				CFrame.lookAt((from + to) / 2, to),
				DARK,
				Enum.Material.Rubber
			)
		end
	end

	-- Néons de récupération au plafond (certains grésillent).
	for index = 1, 8 do
		local color = if index % 3 == 0 then Color3.fromRGB(255, 46, 196) else Color3.fromRGB(0, 229, 255)
		local light = Kit.decor(
			decor,
			"CeilingNeon",
			Vector3.new(10, 0.3, 0.3),
			CFrame.new(at(-87.5 + index * 22, H - 3, -10 + (index % 2) * 20)),
			color,
			Enum.Material.Neon,
			{
				tag = if index % 2 == 0 then "Flicker" else nil,
			}
		)
		Kit.light(light, color, 26, 1.1)
	end

	-- Marché : étals avec un PNJ derrière chaque comptoir.
	local market: { { key: string, x: number } } = {
		{ key = "vault", x = -60 },
		{ key = "merchant", x = -30 },
		{ key = "armorer", x = 0 },
		{ key = "insurer", x = 30 },
		{ key = "bazaar", x = 60 },
	}
	for index, entry in market do
		table.insert(stations, stall(decor, entry.key, origin, entry.x, index % #TARP + 1))
	end
	-- L'établi de l'Armurier (étincelles).
	local anvil =
		Kit.part(decor, "Anvil", Vector3.new(2.5, 2.2, 1.4), CFrame.new(at(6, 1.1, 46)), DARK, Enum.Material.Metal)
	Kit.tag(anvil, "SparkBurst")
	Kit.emitter(anvil, "Sparks", {
		color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 120, 20)),
		rate = 0,
		lifetime = NumberRange.new(0.3, 0.7),
		speed = NumberRange.new(6, 12),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0) }),
		acceleration = Vector3.new(0, -30, 0),
		lightEmission = 1,
		spread = Vector2.new(60, 60),
		direction = Enum.NormalId.Top,
	})

	-- Porte blindée de déploiement (est).
	local gate = Instance.new("Model")
	gate.Name = "DeployGate"
	local gx = W / 2 - 1.5
	Kit.part(gate, "GateFrameTop", Vector3.new(2, 3, 24), CFrame.new(at(gx, 19.5, -10)), DARK, Enum.Material.Metal)
	for _, z in { -22.5, 2.5 } do
		Kit.part(gate, "GateFrameSide", Vector3.new(2, 21, 3), CFrame.new(at(gx, 10.5, z)), DARK, Enum.Material.Metal)
	end
	Kit.part(
		gate,
		"BlastDoor",
		Vector3.new(1, 18, 22),
		CFrame.new(at(gx + 0.5, 9, -10)),
		Color3.fromRGB(70, 72, 76),
		Enum.Material.DiamondPlate
	)
	for stripe = -4, 4 do
		Kit.decor(
			gate,
			"Hazard",
			Vector3.new(0.1, 1, 2.2),
			CFrame.new(at(gx - 0.05, 1, -10 + stripe * 2.4)) * CFrame.Angles(math.rad(35), 0, 0),
			if stripe % 2 == 0 then Color3.fromRGB(230, 190, 20) else DARK,
			Enum.Material.SmoothPlastic
		)
	end
	for _, z in { -24, 4 } do
		local beacon = Kit.decor(
			gate,
			"Beacon",
			Vector3.new(1, 1, 1),
			CFrame.new(at(gx - 1, 22, z)),
			NEON.deploy,
			Enum.Material.Neon,
			{
				tag = "Spin",
				attributes = { Speed = 0.8 },
			}
		)
		Kit.light(beacon, NEON.deploy, 20, 2, true)
	end
	local terminal = Kit.part(
		gate,
		"DeployTerminal",
		Vector3.new(3, 4, 6),
		CFrame.new(at(gx - 9, 2, -10)),
		METAL,
		Enum.Material.Metal
	)
	prompt(terminal, "deploy")
	sign(gate, "deploy", CFrame.new(at(gx - 0.6, 23.5, -10)) * CFrame.Angles(0, math.pi / 2, 0), 12)
	for index = 1, 6 do
		Kit.part(
			gate,
			"Sandbag",
			Vector3.new(2.4, 1, 1.4),
			CFrame.new(at(gx - 14, 0.5 + (index > 3 and 1 or 0), -16 + (index - 1) % 3 * 2.4)),
			Color3.fromRGB(150, 130, 90),
			Enum.Material.Fabric
		)
	end
	gate.Parent = decor
	table.insert(stations, {
		key = "deploy",
		counter = terminal.CFrame,
		npc = CFrame.lookAt(at(gx - 7, 0, -16), at(gx - 20, 0, -16)),
	})

	-- Stand de tir (ouest) et pavé de l'arène d'entraînement.
	local range = Instance.new("Model")
	range.Name = "Range"
	local rangeCounter = Kit.part(
		range,
		"RangeCounter",
		Vector3.new(3, 3.5, 12),
		CFrame.new(at(-84, 1.75, 18)),
		METAL,
		Enum.Material.DiamondPlate
	)
	prompt(rangeCounter, "range")
	for index = 1, 3 do
		local target = Kit.part(
			range,
			"Target",
			Vector3.new(0.4, 4, 3),
			CFrame.new(at(-97, 4, 10 + index * 5)),
			Color3.fromRGB(220, 220, 220),
			Enum.Material.SmoothPlastic
		)
		Kit.decor(
			range,
			"Bullseye",
			Vector3.new(0.05, 1, 1),
			CFrame.new(at(-96.8, 4.6, 10 + index * 5)),
			NEON.range,
			Enum.Material.Neon
		)
		local _ = target
	end
	sign(range, "range", CFrame.new(at(-84, 8.5, 18)) * CFrame.Angles(0, -math.pi / 2, 0), 9)
	range.Parent = decor
	table.insert(stations, {
		key = "range",
		counter = rangeCounter.CFrame,
		npc = CFrame.lookAt(at(-88, 0, 22), at(-70, 0, 22)),
	})
	local pad = Kit.part(
		decor,
		"TrainingPad",
		Vector3.new(8, 0.4, 8),
		CFrame.new(at(-86, 0.2, -12)),
		Color3.fromRGB(50, 54, 60),
		Enum.Material.DiamondPlate
	)
	Kit.decor(
		decor,
		"TrainingRing",
		Vector3.new(0.2, 8.4, 8.4),
		CFrame.new(at(-86, 0.45, -12)) * CFrame.Angles(0, 0, math.rad(90)),
		NEON.training,
		Enum.Material.Neon,
		{
			shape = Enum.PartType.Cylinder,
			transparency = 0.5,
		}
	)
	prompt(pad, "training")
	sign(decor, "training", CFrame.new(at(-86, 7, -17)) * CFrame.Angles(0, math.pi, 0), 9)

	-- Mur des Légendes (face au marché).
	local legends = Instance.new("Model")
	legends.Name = "LegendsWall"
	local wall = Kit.part(
		legends,
		"LegendsBoard",
		Vector3.new(32, 14, 1),
		CFrame.new(at(0, 9, -35)),
		Color3.fromRGB(16, 20, 28),
		Enum.Material.Glass
	)
	Kit.decor(
		legends,
		"LegendsFrame",
		Vector3.new(33, 0.3, 1.2),
		CFrame.new(at(0, 16.1, -35)),
		NEON.legends,
		Enum.Material.Neon,
		{ tag = "Flicker" }
	)
	Kit.decor(
		legends,
		"LegendsFrameLow",
		Vector3.new(33, 0.3, 1.2),
		CFrame.new(at(0, 1.9, -35)),
		NEON.legends,
		Enum.Material.Neon
	)
	-- Titre en haut du tableau ; le top 10 (LeaderboardService) s'affiche dessous.
	local title = Kit.text(wall, Enum.NormalId.Back, "station.legends", NEON.legends, Enum.Font.GothamBlack)
	local titleLabel = title:FindFirstChildOfClass("TextLabel") :: TextLabel
	titleLabel.Position = UDim2.fromScale(0.1, 0.03)
	titleLabel.Size = UDim2.fromScale(0.8, 0.22)
	local legendsBase = Kit.part(
		legends,
		"LegendsConsole",
		Vector3.new(6, 3, 2),
		CFrame.new(at(0, 1.5, -32.5)),
		METAL,
		Enum.Material.Metal
	)
	prompt(legendsBase, "legends")
	legends.Parent = decor
	table.insert(stations, {
		key = "legends",
		counter = legendsBase.CFrame,
		npc = CFrame.lookAt(at(20, 0, -32), at(20, 0, -10)),
	})

	-- Place centrale : feux de bidons, bancs de caisses, tête d'AXIOM renversée.
	for _, position in
		{ Vector3.new(-22, 0, -4), Vector3.new(24, 0, 12), Vector3.new(-56, 0, 14), Vector3.new(58, 0, -14) }
	do
		fireBarrel(decor, at(position.X, 0, position.Z))
		Kit.part(
			decor,
			"Bench",
			Vector3.new(5, 1.4, 1.6),
			CFrame.new(at(position.X + 4, 0.7, position.Z + 1)) * CFrame.Angles(0, 0.4, 0),
			Color3.fromRGB(90, 72, 50),
			Enum.Material.WoodPlanks
		)
	end
	local head = Kit.part(
		decor,
		"FallenAxiomHead",
		Vector3.new(9, 7, 8),
		CFrame.new(at(6, 3, -14)) * CFrame.Angles(0.15, 0.6, 0.35),
		Color3.fromRGB(40, 42, 50),
		Enum.Material.Metal
	)
	local eye = Kit.decor(
		decor,
		"DeadEye",
		Vector3.new(6, 0.6, 0.3),
		head.CFrame * CFrame.new(0, 1, -4.1),
		Color3.fromRGB(255, 40, 40),
		Enum.Material.Neon,
		{
			tag = "Flicker",
		}
	)
	Kit.light(eye, Color3.fromRGB(255, 40, 40), 10, 0.6)
	debris(decor, at(12, 0, -10), 6)

	-- Campement le long du quai : matelas, tentes, marmite fumante.
	for index, x in { -70, -40, 40, 70 } do
		Kit.decor(
			decor,
			"SleepMat" .. index,
			Vector3.new(6, 0.3, 3),
			CFrame.new(at(x, 0.15, -31)),
			Color3.fromRGB(100, 86 + index * 4, 70),
			Enum.Material.Fabric
		)
		Kit.decor(
			decor,
			"Tent" .. index,
			Vector3.new(7, 0.2, 5),
			CFrame.new(at(x, 4, -30)) * CFrame.Angles(math.rad(25), 0, 0),
			TARP[index],
			Enum.Material.Fabric
		)
	end
	local pot = Kit.cylinder(decor, "Pot", 1.6, 2.2, at(-38, 1.1, -26), DARK, Enum.Material.Metal)
	Kit.emitter(pot, "Steam", {
		color = ColorSequence.new(Color3.fromRGB(230, 230, 230)),
		rate = 5,
		lifetime = NumberRange.new(1.5, 2.5),
		speed = NumberRange.new(1, 2),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 2) }),
		transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) }),
		direction = Enum.NormalId.Right,
	})

	-- Caisses, pneus, débris et flaques un peu partout.
	for _, entry in { { -92, 34, 0.2 }, { 88, 30, -0.5 }, { -40, 18, 1.1 }, { 40, -22, 0.7 }, { -8, 30, 2 } } do
		crates(decor, at(entry[1], 0, entry[2]), entry[3])
	end
	for index, position in { Vector3.new(-66, 0, -14), Vector3.new(72, 0, 22), Vector3.new(-12, 0, 18) } do
		for level = 0, 2 do
			Kit.cylinder(
				decor,
				`Tire{index}_{level}`,
				0.9,
				3,
				at(position.X, 0.45 + level * 0.9, position.Z),
				Color3.fromRGB(28, 28, 30),
				Enum.Material.Rubber
			)
		end
	end
	for _, position in
		{ Vector3.new(-80, 0, 0), Vector3.new(80, 0, 8), Vector3.new(-30, 0, 30), Vector3.new(36, 0, -28) }
	do
		debris(decor, at(position.X, 0, position.Z), 5)
	end
	for _, position in
		{ Vector3.new(-48, 0, -10), Vector3.new(14, 0, 20), Vector3.new(52, 0, 4), Vector3.new(-10, 0, -26) }
	do
		drip(decor, at(position.X, 0, position.Z), origin.Y + H - 1)
	end

	-- Écrans d'AXIOM parasités, affiches de propagande, tags de résistance.
	for index, x in { -45, 15, 75 } do
		monitor(decor, CFrame.new(at(x, 10, 26.4)), "hub.monitor." .. index)
	end
	for index, entry in { { -75, -34.4 }, { 45, -34.4 }, { -15, 29.6 } } do
		poster(
			decor,
			CFrame.new(at(entry[1], 6, entry[2])) * CFrame.Angles(0, math.pi, 0),
			Vector2.new(2.8, 3.6),
			"hub.poster." .. (index % 3 + 1),
			Color3.fromRGB(255, 230, 230),
			Color3.fromRGB(140, 20, 20)
		)
	end
	for index, entry in
		{
			{ -70, 12, 58.9, 0 },
			{ 20, 18, 58.9, -6 },
			{ -98.9, 14, -20, 4 },
			{ 98.9, 12, 30, -3 },
			{ 50, 6, 58.9, 3 },
			{ -98.9, 6, 40, -5 },
		}
	do
		local x, y, z, rotation = entry[1], entry[2], entry[3], entry[4]
		local yaw = if math.abs(x) > 98 then (if x > 0 then math.pi / 2 else -math.pi / 2) else 0
		poster(
			decor,
			CFrame.new(at(x, y, z)) * CFrame.Angles(0, yaw, 0),
			Vector2.new(10, 3),
			"hub.graffiti." .. index,
			if index % 2 == 0 then Color3.fromRGB(57, 255, 20) else Color3.fromRGB(255, 46, 196),
			nil,
			rotation
		)
	end

	-- Drones de maintenance et rongeurs mécaniques.
	for index, spec in { { radius = 34, height = 20, speed = 0.12 }, { radius = 52, height = 25, speed = -0.08 } } do
		local drone = Kit.decor(
			decor,
			"Drone" .. index,
			Vector3.new(1.6, 0.6, 1.6),
			CFrame.new(at(0, spec.height, 0)),
			DARK,
			Enum.Material.Metal,
			{
				tag = "Drone",
				attributes = { Center = at(0, spec.height, 0), Radius = spec.radius, Speed = spec.speed },
			}
		)
		local light = Kit.decor(
			decor,
			"DroneEye" .. index,
			Vector3.new(0.4, 0.2, 0.4),
			drone.CFrame * CFrame.new(0, -0.35, 0),
			Color3.fromRGB(255, 40, 40),
			Enum.Material.Neon
		)
		Kit.weld(drone, light)
		light.Anchored = false
		Kit.light(light, Color3.fromRGB(255, 60, 60), 8, 1)
	end
	for index, spec in { { -95, 55, -60, 55 }, { 10, -37, 70, -37 }, { 95, 50, 95, 0 } } do
		Kit.decor(
			decor,
			"Critter" .. index,
			Vector3.new(0.5, 0.35, 0.9),
			CFrame.new(at(spec[1], 0.18, spec[2])),
			Color3.fromRGB(70, 70, 76),
			Enum.Material.Metal,
			{
				tag = "Critter",
				attributes = { PointA = at(spec[1], 0.18, spec[2]), PointB = at(spec[3], 0.18, spec[4]) },
			}
		)
	end

	-- Points d'apparition (place centrale).
	local spawns: { CFrame } = {}
	for index = 1, 6 do
		local cframe = CFrame.new(at(-25 + index * 7, 0.5, 4))
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "HubSpawn" .. index
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Size = Vector3.new(5, 1, 5)
		spawn.CFrame = cframe
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.Parent = folder
		table.insert(spawns, cframe)
	end

	return { folder = folder, stations = stations, spawns = spawns }
end

return TerminusBuilder
