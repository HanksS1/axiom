--!strict
--[[
	MapRuntimeService : carte de la partie en cours (section 12).

	- Chargement : construction greybox (Server/Maps), éclairage propre à la
	  carte, repères actifs (MapService.setRoot). Déchargement en fin de
	  partie sur un serveur qui accueille aussi le Terminus.
	- Zones dangereuses (vérifiées 5 fois par seconde) :
	  · métal en fusion (Forge-7) : mort instantanée ;
	  · radiation (Terres Brûlées) : -5 bouclier/s, puis -3 PV/s.
	- Mécaniques :
	  · Néo-Lumen : effondrements annoncés par des grondements ;
	  · Forge-7 : 1 ou 2 Sentinelles toutes les 3 minutes tant que le panneau
	    de contrôle (300 PV) tient ;
	  · Noyau Zéro : coupures de courant de 20 s toutes les 2 à 3 minutes
	    (vision des robots et des mercenaires réduite).
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Fighter = require(script.Parent.Parent.Combat.Fighter)
local LayoutBuilder = require(script.Parent.Parent.Maps.LayoutBuilder)
local MapRenderer = require(script.Parent.Parent.Maps.MapRenderer)
local Registry = require(script.Parent.Parent.Maps.Registry)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local CombatService = require(script.Parent.CombatService)
local MapService = require(script.Parent.MapService)
local MercenaryService = require(script.Parent.MercenaryService)
local RobotService = require(script.Parent.RobotService)

type Fighter = Fighter.Fighter

local Maps = Config.Maps

local MapRuntimeService = {}

local currentId: string? = nil
local root: Folder? = nil
local layout: LayoutBuilder.Layout? = nil
local savedLighting: { [string]: any }? = nil
local random = Random.new()
local running = false
local accumulator = 0

-- Choix de carte forcé en Studio (panneau DEV) : "random", un identifiant ou "arena".
MapRuntimeService.devChoice = "random"

-- État des mécaniques.
local mechanic: {
	collapses: { LayoutBuilder.Collapse },
	nextCollapseAt: number,
	warned: boolean,
	panel: Fighter?,
	productionStopped: boolean,
	nextProductionAt: number,
	blackoutOn: boolean,
	nextBlackoutAt: number,
	blackoutEndsAt: number,
} =
	{
		collapses = {},
		nextCollapseAt = math.huge,
		warned = false,
		panel = nil,
		productionStopped = false,
		nextProductionAt = math.huge,
		blackoutOn = false,
		nextBlackoutAt = math.huge,
		blackoutEndsAt = 0,
	}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function announce(key: string)
	ServerNet.fireAll("Announce", key)
end

local function between(range: { min: number, max: number }): number
	return random:NextNumber(range.min, range.max)
end

function MapRuntimeService.current(): string?
	return currentId
end

-- Carte d'une nouvelle partie : choix du panneau DEV en Studio, sinon au hasard.
function MapRuntimeService.pick(): string
	local choice = MapRuntimeService.devChoice
	if RunService:IsStudio() and (choice == "arena" or Maps.byId[choice] ~= nil) then
		return choice
	end
	return Maps.list[random:NextInteger(1, #Maps.list)]
end

-- Gardien de la carte chargée (nil dans l'arène de test).
function MapRuntimeService.guardian(): any?
	local id = currentId
	return if id then (Maps.byId :: any)[id].guardian else nil
end

local function applyLighting(settings: any)
	Lighting.Ambient = settings.ambient
	Lighting.OutdoorAmbient = settings.outdoorAmbient
	Lighting.Brightness = settings.brightness
	Lighting.ClockTime = settings.clockTime
	Lighting.FogColor = settings.fogColor
	Lighting.FogEnd = settings.fogEnd
end

function MapRuntimeService.unload()
	MapRuntimeService.stop()
	local existing = root
	root = nil
	layout = nil
	currentId = nil
	if existing then
		existing:Destroy()
	end
	if savedLighting then
		applyLighting(savedLighting)
		savedLighting = nil
	end
	-- Retour aux repères de l'arène de test (bac à sable), s'il y en a une.
	MapService.setRoot(Workspace:FindFirstChild("Arena"))
end

--[[
	Construit la carte `mapId` (peut céder la main quelques images) et en
	fait la carte active. Retourne false si la carte est inconnue.
]]
function MapRuntimeService.load(mapId: string): boolean
	local def = (Maps.byId :: any)[mapId]
	local build = Registry[mapId]
	if def == nil or build == nil then
		return false
	end
	MapRuntimeService.unload()
	local built = build(Random.new(def.seed))
	savedLighting = {
		ambient = Lighting.Ambient,
		outdoorAmbient = Lighting.OutdoorAmbient,
		brightness = Lighting.Brightness,
		clockTime = Lighting.ClockTime,
		fogColor = Lighting.FogColor,
		fogEnd = Lighting.FogEnd,
	}
	applyLighting(def.lighting)
	local folder = MapRenderer.render(built, Workspace, Maps.origin, mapId)
	root = folder
	layout = built
	currentId = mapId
	MapService.setRoot(folder)
	return true
end

-- Zones dangereuses -------------------------------------------------------------

local function insideHazard(hazard: LayoutBuilder.Hazard, position: Vector3): boolean
	local p = position - Maps.origin
	if p.Y < hazard.center.Y - 1 or p.Y > hazard.center.Y + hazard.height then
		return false
	end
	if hazard.radius then
		local dx, dz = p.X - hazard.center.X, p.Z - hazard.center.Z
		return dx * dx + dz * dz <= hazard.radius * hazard.radius
	end
	local size = hazard.size :: Vector3
	return math.abs(p.X - hazard.center.X) <= size.X / 2 and math.abs(p.Z - hazard.center.Z) <= size.Z / 2
end

local function hazardStep(dt: number)
	local current = layout
	if current == nil or #current.hazards == 0 then
		return
	end
	local radiation = (Maps.byId :: any)[currentId :: string].radiation
	for _, fighter in CombatService.allFighters() do
		if fighter.kind == "object" or not Fighter.isAlive(fighter) then
			continue
		end
		local irradiated = false
		for _, hazard in current.hazards do
			if insideHazard(hazard, fighter.root.Position) then
				if hazard.kind == "molten" then
					CombatService.kill(fighter)
					break
				elseif hazard.kind == "radiation" and fighter.kind ~= "robot" and radiation then
					irradiated = true
				end
			end
		end
		if irradiated and Fighter.isAlive(fighter) then
			local amount = if fighter.shield > 0 then radiation.shieldPerSecond * dt else radiation.healthPerSecond * dt
			CombatService.applyDamage(fighter, amount, nil)
		end
		if fighter.character:GetAttribute("Irradiated") ~= irradiated then
			fighter.character:SetAttribute("Irradiated", irradiated)
		end
	end
end

-- Mécaniques ------------------------------------------------------------------

local function collapseStep(time: number)
	local def = (Maps.byId :: any).neo_lumen.collapse
	local site = mechanic.collapses[1]
	if site == nil or root == nil then
		return
	end
	local world = Maps.origin + site.center
	if not mechanic.warned and time >= mechanic.nextCollapseAt - def.warning then
		mechanic.warned = true
		announce("map.neo_lumen.rumble")
		ServerNet.fireAll("MapEvent", "rumble", world)
	end
	if time < mechanic.nextCollapseAt then
		return
	end
	table.remove(mechanic.collapses, 1)
	mechanic.warned = false
	mechanic.nextCollapseAt = time + between(def.interval)
	local folder = root :: Folder
	local groups = folder:FindFirstChild("Groups")
	local model = if groups then groups:FindFirstChild(site.id) else nil
	if model then
		model:Destroy()
	end
	-- Les combattants pris sous l'effondrement sont blessés.
	local half = site.size / 2
	for _, fighter in CombatService.allFighters() do
		local p = fighter.root.Position - world
		if
			fighter.kind ~= "object"
			and Fighter.isAlive(fighter)
			and math.abs(p.X) <= half.X
			and math.abs(p.Z) <= half.Z
			and p.Y <= site.size.Y
		then
			CombatService.applyDamage(fighter, def.damage, nil, { sourcePosition = world })
		end
	end
	local geometry = folder:FindFirstChild("Geometry")
	MapRenderer.renderParts(site.rubble, geometry or folder, Maps.origin, nil)
	ServerNet.fireAll("MapEvent", "collapse", world)
end

local function spawnPanel()
	local current = layout
	if current == nil or current.data.panel == nil or root == nil then
		return
	end
	local spec = current.data.panel
	local def = (Maps.byId :: any).forge_7.production
	local model = Instance.new("Model")
	model.Name = "ControlPanel"
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = spec.size
	body.CFrame = CFrame.new(Maps.origin + spec.position + Vector3.new(0, spec.size.Y / 2, 0))
	body.Color = Color3.fromRGB(40, 44, 52)
	body.Material = Enum.Material.Metal
	body.Anchored = true
	body.Parent = model
	local screen = Instance.new("Part")
	screen.Name = "Screen"
	screen.Size = Vector3.new(spec.size.X * 0.8, spec.size.Y * 0.4, 0.2)
	screen.CFrame = body.CFrame * CFrame.new(0, spec.size.Y * 0.15, -spec.size.Z / 2 - 0.1)
	screen.Color = Color3.fromRGB(255, 138, 0)
	screen.Material = Enum.Material.Neon
	screen.Anchored = true
	screen.CanQuery = false
	screen.Parent = model
	model.PrimaryPart = body
	model.Parent = root
	local fighter = Fighter.newObject(model, body, def.panelHealth, "axiom")
	CombatService.register(fighter)
	mechanic.panel = fighter
end

local function productionStep(time: number)
	if mechanic.productionStopped or time < mechanic.nextProductionAt then
		return
	end
	local def = (Maps.byId :: any).forge_7.production
	mechanic.nextProductionAt = time + def.interval
	local current = layout
	if current == nil or current.data.productionExit == nil then
		return
	end
	local count = random:NextInteger(def.robots.min, def.robots.max)
	count = math.min(count, Config.Robots.density.hardCap - RobotService.count())
	if count <= 0 then
		return
	end
	local exit = Maps.origin + current.data.productionExit
	for index = 1, count do
		RobotService.spawn(def.robotId, exit + Vector3.new(0, 1, (index - 1) * 4), false)
	end
	announce("map.forge_7.production")
end

local function setBlackout(on: boolean)
	local def = (Maps.byId :: any).noyau_zero.blackout
	mechanic.blackoutOn = on
	local multiplier = if on then def.visionMultiplier else 1
	RobotService.setVisionMultiplier(multiplier)
	MercenaryService.setVisionMultiplier(multiplier)
	if root then
		(root :: Folder):SetAttribute("Blackout", on)
	end
	if on then
		announce("map.noyau_zero.blackout")
	end
end

local function blackoutStep(time: number)
	local def = (Maps.byId :: any).noyau_zero.blackout
	if mechanic.blackoutOn then
		if time >= mechanic.blackoutEndsAt then
			setBlackout(false)
			mechanic.nextBlackoutAt = time + between(def.interval)
		end
	elseif time >= mechanic.nextBlackoutAt then
		mechanic.blackoutEndsAt = time + def.duration
		setBlackout(true)
	end
end

-- Démarre les mécaniques de la carte chargée (début de partie).
function MapRuntimeService.startMechanics(matchStart: number)
	MapRuntimeService.stop()
	local id = currentId
	if id == nil then
		return
	end
	random = Random.new()
	local def = (Maps.byId :: any)[id]
	mechanic.collapses = {}
	mechanic.nextCollapseAt = math.huge
	mechanic.nextProductionAt = math.huge
	mechanic.nextBlackoutAt = math.huge
	mechanic.productionStopped = false
	mechanic.warned = false
	if def.collapse and layout then
		mechanic.collapses = LayoutBuilder.shuffle(random, table.clone((layout :: LayoutBuilder.Layout).collapses))
		mechanic.nextCollapseAt = matchStart + def.collapse.firstAfter
	end
	if def.production then
		spawnPanel()
		mechanic.nextProductionAt = matchStart + def.production.interval
	end
	if def.blackout then
		mechanic.nextBlackoutAt = matchStart + between(def.blackout.firstAfter)
	end
	running = true
end

-- Arrête les mécaniques (fin de partie).
function MapRuntimeService.stop()
	running = false
	if mechanic.blackoutOn then
		setBlackout(false)
	end
	mechanic.collapses = {}
	mechanic.nextCollapseAt = math.huge
	mechanic.nextProductionAt = math.huge
	mechanic.nextBlackoutAt = math.huge
	mechanic.panel = nil
end

function MapRuntimeService.init()
	CombatService.FighterDied:Connect(function(fighter)
		if fighter == mechanic.panel then
			mechanic.panel = nil
			mechanic.productionStopped = true
			announce("map.forge_7.panel_destroyed")
		end
	end)
end

function MapRuntimeService.start()
	RunService.Heartbeat:Connect(function(dt)
		if not running then
			return
		end
		accumulator += dt
		if accumulator < Maps.hazardTick then
			return
		end
		local step = accumulator
		accumulator = 0
		hazardStep(step)
		local time = now()
		local id = currentId
		if id == "neo_lumen" then
			collapseStep(time)
		elseif id == "forge_7" then
			productionStep(time)
		elseif id == "noyau_zero" then
			blackoutStep(time)
		end
	end)
end

return MapRuntimeService
