--!strict
--[[
	ArenaService : arène de test greybox (Studio uniquement, phase P1).

	Construite si la place ne contient pas déjà de carte (dossier « Map »
	ou « Arena » dans Workspace). Contient des couverts pleins, des couverts
	légers (tag « LightCover ») et des mannequins d'entraînement équipés de
	gilets / casques de différents états pour tester bouclier et tirs à la tête.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Fighter = require(script.Parent.Parent.Combat.Fighter)
local ItemFactory = require(script.Parent.Parent.Inventory.ItemFactory)
local CombatService = require(script.Parent.CombatService)
local LootService = require(script.Parent.LootService)
local MapService = require(script.Parent.MapService)

local Dev = Config.Dev

local ArenaService = {}

local CONCRETE = Color3.fromRGB(70, 74, 82)
local RUST = Color3.fromRGB(120, 72, 46)
local NEON_CYAN = Color3.fromRGB(0, 229, 255)

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: EnumItem
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function buildArena(): Folder
	local arena = Instance.new("Folder")
	arena.Name = "Arena"
	local size = Dev.arenaSize
	local half = size / 2

	part(arena, "Floor", Vector3.new(size, 2, size), CFrame.new(0, -1, 0), CONCRETE, Enum.Material.Concrete)
	for index, offset in
		{ Vector3.new(half, 0, 0), Vector3.new(-half, 0, 0), Vector3.new(0, 0, half), Vector3.new(0, 0, -half) }
	do
		local alongX = offset.X == 0
		local wall = part(
			arena,
			"Wall" .. index,
			if alongX then Vector3.new(size, 16, 2) else Vector3.new(2, 16, size),
			CFrame.new(offset + Vector3.new(0, 8, 0)),
			CONCRETE,
			Enum.Material.Concrete
		)
		local strip = part(
			arena,
			"Neon" .. index,
			if alongX then Vector3.new(size, 0.4, 0.2) else Vector3.new(0.2, 0.4, size),
			wall.CFrame * CFrame.new(0, 6, 0) * CFrame.new(-offset.Unit * 1.1),
			NEON_CYAN,
			Enum.Material.Neon
		)
		strip.CanCollide = false
	end

	-- Couverts pleins (béton) répartis dans l'arène.
	local random = Random.new(7)
	for index = 1, 18 do
		local x = random:NextInteger(-half + 12, half - 12)
		local z = random:NextInteger(-half + 12, half - 12)
		if math.abs(x) < 20 and math.abs(z) < 40 then
			continue -- zone des mannequins dégagée
		end
		local height = random:NextInteger(3, 8)
		part(
			arena,
			"Cover" .. index,
			Vector3.new(random:NextInteger(4, 10), height, random:NextInteger(2, 6)),
			CFrame.new(x, height / 2, z) * CFrame.Angles(0, math.rad(random:NextInteger(0, 90)), 0),
			CONCRETE,
			Enum.Material.Concrete
		)
	end

	-- Couverts légers (tôle, planches) : traversés par le Canon à rayons X.
	for index = 1, 6 do
		local angle = index / 6 * math.pi * 2
		local plank = part(
			arena,
			"LightCover" .. index,
			Vector3.new(8, 6, 0.4),
			CFrame.new(math.cos(angle) * 45, 3, math.sin(angle) * 45) * CFrame.Angles(0, -angle, 0),
			RUST,
			Enum.Material.CorrodedMetal
		)
		CollectionService:AddTag(plank, "LightCover")
	end

	-- Plateforme surélevée (test de hauteur, de chute et de saut).
	part(arena, "Platform", Vector3.new(20, 1, 20), CFrame.new(50, 8, 50), CONCRETE, Enum.Material.DiamondPlate)
	local ramp = part(
		arena,
		"Ramp",
		Vector3.new(6, 1, 24),
		CFrame.new(50, 4, 28) * CFrame.Angles(math.rad(19), 0, 0),
		CONCRETE,
		Enum.Material.DiamondPlate
	)
	ramp.Name = "Ramp"

	-- Points d'apparition en bordure.
	for index = 1, 8 do
		local angle = index / 8 * math.pi * 2
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "Spawn" .. index
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Size = Vector3.new(6, 1, 6)
		spawn.CFrame = CFrame.new(math.cos(angle) * (half - 12), 0.5, math.sin(angle) * (half - 12))
		spawn.Color = NEON_CYAN
		spawn.Material = Enum.Material.Neon
		spawn.Transparency = 0.6
		spawn.Parent = arena
	end

	arena.Parent = Workspace
	return arena
end

-- Mannequin d'entraînement : un combattant immobile (type « bot »).
local function spawnDummy(arena: Instance, spec: any)
	local ok, model = pcall(function()
		local description = Instance.new("HumanoidDescription")
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or model == nil then
		warn(`[ArenaService] mannequin non créé : {model}`)
		return
	end
	local character = model :: Model
	character.Name = "Dummy"
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.MaxHealth = Config.Combat.maxHealth
	humanoid.Health = Config.Combat.maxHealth
	root.CanQuery = false
	character:PivotTo(CFrame.new(spec.position) * CFrame.Angles(0, math.pi, 0))
	root.Anchored = true
	character.Parent = arena

	local equipment: Fighter.Equipment = {
		melee = ItemFactory.create("shock_crowbar", { condition = 1 }),
	}
	if spec.vestCondition > 0 then
		equipment.vest = ItemFactory.create("vest", { condition = spec.vestCondition })
	end
	if spec.helmetCondition > 0 then
		equipment.helmet = ItemFactory.create("helmet", { condition = spec.helmetCondition })
	end
	local fighter = Fighter.new("bot", nil, character, humanoid, root, equipment, Fighter.simpleInventory({}))
	CombatService.register(fighter)
end

-- Caisses de test : 6 de ravitaillement, 3 coffres militaires, 1 casier d'AXIOM.
local CRATES: { { position: Vector3, crateType: string } } = {
	{ position = Vector3.new(25, 0, 10), crateType = "supply" },
	{ position = Vector3.new(-25, 0, 10), crateType = "supply" },
	{ position = Vector3.new(0, 0, 30), crateType = "supply" },
	{ position = Vector3.new(60, 0, -20), crateType = "supply" },
	{ position = Vector3.new(-60, 0, -20), crateType = "supply" },
	{ position = Vector3.new(-40, 0, 55), crateType = "supply" },
	{ position = Vector3.new(45, 8.5, 50), crateType = "military" },
	{ position = Vector3.new(-65, 0, 60), crateType = "military" },
	{ position = Vector3.new(65, 0, -60), crateType = "military" },
	{ position = Vector3.new(0, 0, 70), crateType = "axiom_locker" },
}

-- Bac à sable (hors partie) : caisses qui réapparaissent, réapparition des joueurs.
local sandbox = true

local function spawnCrate(cframe: CFrame, crateType: string)
	if not sandbox then
		return
	end
	local container = LootService.spawnCrate(cframe, crateType)
	-- La caisse ouverte est remplacée par une neuve après un délai.
	container.model:GetAttributeChangedSignal("Opened"):Once(function()
		task.delay(Config.Loot.arenaRespawnDelay, function()
			if not sandbox then
				return
			end
			LootService.remove(container)
			spawnCrate(cframe, crateType)
		end)
	end)
end

-- Remplit l'arène de caisses de bac à sable à partir des repères.
function ArenaService.spawnSandboxCrates()
	for _, marker in MapService.crateSpawns() do
		spawnCrate(marker.cframe, marker.attributes.CrateType or "supply")
	end
end

-- Active / désactive le bac à sable (désactivé pendant une partie).
function ArenaService.setSandbox(enabled: boolean)
	sandbox = enabled
end

function ArenaService.isSandbox(): boolean
	return sandbox
end

-- Repères de partie : points de départ, extractions, accélérateurs, caisses.
local function placeMarkers(arena: Instance)
	local half = Dev.arenaSize / 2
	for index = 1, 8 do
		local angle = index / 8 * math.pi * 2 + math.pi / 8
		MapService.placeMarker(
			arena,
			"DeploySpawn",
			CFrame.new(math.cos(angle) * (half - 10), 3, math.sin(angle) * (half - 10))
		)
	end
	local extractions = {
		{ position = Vector3.new(0, 0.2, -70), name = "extraction.arena.north" },
		{ position = Vector3.new(65, 0.2, 35), name = "extraction.arena.east" },
		{ position = Vector3.new(-65, 0.2, 35), name = "extraction.arena.west" },
	}
	for _, spec in extractions do
		MapService.placeMarker(arena, "ExtractionPoint", CFrame.new(spec.position), { NameKey = spec.name })
	end
	for index = 1, 6 do
		local angle = index / 6 * math.pi * 2
		MapService.placeMarker(arena, "AcceleratorSpot", CFrame.new(math.cos(angle) * 60, 0.2, math.sin(angle) * 60))
	end
	for _, spec in CRATES do
		MapService.placeMarker(arena, "CrateSpawn", CFrame.new(spec.position), { CrateType = spec.crateType })
	end
	-- Zones à risque (garnisons, Gardien) et points de patrouille des robots.
	MapService.placeMarker(arena, "RiskZone", CFrame.new(0, 1, 62), { Main = true, Radius = 14 })
	MapService.placeMarker(arena, "RiskZone", CFrame.new(50, 9, 50), { Main = false, Radius = 8 })
	for index = 1, 4 do
		local angle = index / 4 * math.pi * 2 + math.pi / 4
		MapService.placeMarker(arena, "RobotSpawn", CFrame.new(math.cos(angle) * 55, 1, math.sin(angle) * 55), {
			Garrison = false,
		})
	end
end

-- L'arène de test est-elle la carte courante ?
function ArenaService.isArena(): boolean
	return Workspace:FindFirstChild("Arena") ~= nil
end

function ArenaService.init() end

function ArenaService.start()
	if not (RunService:IsStudio() and Dev.testArenaInStudio) then
		return
	end
	if Workspace:FindFirstChild("Map") or Workspace:FindFirstChild("Arena") then
		return
	end
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	local arena = buildArena()
	for _, spec in Dev.dummies do
		task.spawn(spawnDummy, arena, spec)
	end
	placeMarkers(arena)
	ArenaService.spawnSandboxCrates()

	-- Les mannequins détruits réapparaissent.
	CombatService.FighterDied:Connect(function(fighter)
		if fighter.kind ~= "bot" or fighter.player ~= nil then
			return
		end
		local position = fighter.root.Position
		task.delay(Dev.dummyRespawnDelay, function()
			fighter.character:Destroy()
			for _, spec in Dev.dummies do
				if (spec.position - position).Magnitude < 4 then
					spawnDummy(arena, spec)
				end
			end
		end)
	end)
end

return ArenaService
