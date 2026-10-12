--!strict
--[[
	ExtractionService : points d'extraction (section 13).

	- Cercle lumineux orange au sol + balise verticale visible de loin.
	- 2 points sur 3 ouverts au départ (tirés au hasard), le 3e à l'alerte.
	- 30 s dans la zone ; en duo, les deux coéquipiers vivants doivent y être.
	  Pause (jaune) si un coéquipier vivant sort, blocage (rouge) tant qu'un
	  ennemi (joueur, mercenaire IA ou robot) s'y trouve. Pas de retour à zéro.
	- Pas de limite au nombre d'équipes qui s'extraient.

	Le serveur calcule tout ; chaque joueur concerné reçoit l'état de son
	extraction (ExtractionState) pour l'affichage.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MatchRules = require(Shared.Match.MatchRules)
local Signal = require(Shared.Util.Signal)

local Fighter = require(script.Parent.Parent.Combat.Fighter)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local CombatService = require(script.Parent.CombatService)
local MapService = require(script.Parent.MapService)

type Fighter = Fighter.Fighter

local E = Config.Match.extraction

local ExtractionService = {}

-- (zoneId, teamId, joueurs extraits) : une équipe a terminé son extraction.
ExtractionService.TeamExtracted = Signal.new() :: Signal.Signal<string, string, { Player }>

type Zone = {
	id: string,
	position: Vector3,
	nameKey: string,
	open: boolean,
	model: Model,
	progress: { [string]: number }, -- par équipe
}

local zones: { Zone } = {}
local active = false
local folder: Folder?
local lastSent: { [Player]: string } = {}

-- Équipes encore en jeu : fonction fournie par MatchService
-- (teamId → joueurs vivants, hors orbes et morts).
local aliveMembers: (teamId: string) -> { Player } = function(_teamId: string)
	return {}
end

local ORANGE = Color3.fromRGB(255, 138, 0)
local CLOSED = Color3.fromRGB(80, 84, 92)

local function buildZoneModel(position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Extraction"
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.3, E.radius * 2, E.radius * 2)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.55
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Parent = model
	local beacon = Instance.new("Part")
	beacon.Name = "Beacon"
	beacon.Size = Vector3.new(1.2, 400, 1.2)
	beacon.CFrame = CFrame.new(position + Vector3.new(0, 200, 0))
	beacon.Material = Enum.Material.Neon
	beacon.Transparency = 0.6
	beacon.Anchored = true
	beacon.CanCollide = false
	beacon.CanQuery = false
	beacon.CanTouch = false
	beacon.CastShadow = false
	beacon.Parent = model
	model.PrimaryPart = ring
	return model
end

local function paint(zone: Zone)
	local ring = zone.model:FindFirstChild("Ring") :: BasePart
	local beacon = zone.model:FindFirstChild("Beacon") :: BasePart
	ring.Color = if zone.open then ORANGE else CLOSED
	ring.Transparency = if zone.open then 0.45 else 0.85
	beacon.Color = ORANGE
	beacon.Transparency = if zone.open then 0.6 else 1
	-- Lu par les clients (boussole, directions des extractions ouvertes).
	zone.model:SetAttribute("Open", zone.open)
	zone.model:SetAttribute("ZoneId", zone.id)
	zone.model:SetAttribute("NameKey", zone.nameKey)
end

local function inside(zone: Zone, position: Vector3): boolean
	local offset = position - zone.position
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= E.radius and math.abs(offset.Y) <= E.verticalTolerance
end

-- Prépare les zones de la carte et ouvre `openAtStart` points au hasard.
function ExtractionService.setup(random: Random, membersOf: (teamId: string) -> { Player })
	ExtractionService.clear()
	aliveMembers = membersOf
	local container = Instance.new("Folder")
	container.Name = "Extractions"
	container.Parent = Workspace
	folder = container
	for index, marker in MapService.extractionPoints() do
		local zone: Zone = {
			id = "z" .. index,
			position = marker.position,
			nameKey = marker.attributes.NameKey or "extraction.generic",
			open = false,
			model = buildZoneModel(marker.position),
			progress = {},
		}
		zone.model.Parent = container
		table.insert(zones, zone)
	end
	-- Ouverture aléatoire de 2 points sur 3.
	local order = {}
	for index in zones do
		table.insert(order, index)
	end
	for index = #order, 2, -1 do
		local swap = random:NextInteger(1, index)
		order[index], order[swap] = order[swap], order[index]
	end
	for rank, index in order do
		zones[index].open = rank <= E.openAtStart
		paint(zones[index])
	end
	active = true
end

-- Alerte de 12:00 : tous les points s'ouvrent.
function ExtractionService.openAll()
	for _, zone in zones do
		zone.open = true
		paint(zone)
	end
end

function ExtractionService.clear()
	active = false
	table.clear(zones)
	table.clear(lastSent)
	if folder then
		folder:Destroy()
		folder = nil
	end
end

function ExtractionService.openZones(): { Vector3 }
	local list = {}
	for _, zone in zones do
		if zone.open then
			table.insert(list, zone.position)
		end
	end
	return list
end

local function send(player: Player, zoneId: string?, progress: number, status: string)
	local key = `{zoneId}:{math.floor(progress * 4)}:{status}`
	if lastSent[player] == key then
		return
	end
	lastSent[player] = key
	ServerNet.fire("ExtractionState", player, zoneId, progress, status)
end

local function update(dt: number)
	if not active then
		return
	end
	local shown: { [Player]: boolean } = {}
	for _, zone in zones do
		if not zone.open then
			continue
		end
		-- Combattants vivants dans la zone, par équipe.
		local insideByTeam: { [string]: { Player } } = {}
		local fightersInside: { Fighter } = {}
		for _, player in Players:GetPlayers() do
			local fighter = CombatService.getFighter(player)
			if fighter and Fighter.isAlive(fighter) and inside(zone, fighter.root.Position) then
				table.insert(fightersInside, fighter)
				local team = Fighter.teamOf(fighter)
				if team then
					insideByTeam[team] = insideByTeam[team] or {}
					table.insert(insideByTeam[team], player)
				end
			end
		end
		for _, other in CombatService.allFighters() do
			if
				other.player == nil
				and other.kind ~= "object"
				and Fighter.isAlive(other)
				and inside(zone, other.root.Position)
			then
				table.insert(fightersInside, other)
			end
		end

		for team, members in insideByTeam do
			local alive = aliveMembers(team)
			local enemies = 0
			for _, fighter in fightersInside do
				if Fighter.teamOf(fighter) ~= team then
					enemies += 1
				end
			end
			local progress, status = MatchRules.stepExtraction(zone.progress[team] or 0, dt, #members, #alive, enemies)
			zone.progress[team] = progress
			for _, member in members do
				shown[member] = true
				send(member, zone.id, progress, status)
			end
			if status == "done" then
				zone.progress[team] = nil
				ExtractionService.TeamExtracted:Fire(zone.id, team, members)
			end
		end
	end
	-- Joueurs sortis de toute zone : on efface leur affichage.
	for player in lastSent do
		if not shown[player] then
			lastSent[player] = nil
			ServerNet.fire("ExtractionState", player, nil, 0, "idle")
		end
	end
end

function ExtractionService.init() end

function ExtractionService.start()
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < E.updateInterval then
			return
		end
		local step = accumulator
		accumulator = 0
		update(step)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastSent[player] = nil
	end)
end

return ExtractionService
