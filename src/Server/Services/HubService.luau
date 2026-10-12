--!strict
--[[
	HubService : le Terminus, hub social (sections 2.3, 16.4).

	Un Terminus greybox est construit à côté de l'arène s'il n'en existe pas
	déjà un (dossier « Terminus » dans Workspace) : en Studio, et en ligne
	tant que le vrai Terminus n'est pas modélisé (Config.Dev.greyboxOnline).
	Le vrai Terminus portera les mêmes attributs `Station`.

	Zone sans combat : hors partie, les joueurs ne peuvent se blesser que
	dans l'arène d'entraînement.

	Stations (ProximityPrompt, attribut Station → panneau côté client) :
	merchant, armorer, insurer, vault, bazaar, deploy, range, legends.
	Le pavé « training » téléporte vers l'arène d'entraînement (bac à sable).
]]

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local Fighter = require(script.Parent.Parent.Combat.Fighter)
local PlaceRole = require(script.Parent.Parent.Matchmaking.PlaceRole)
local ArenaService = require(script.Parent.ArenaService)
local CombatService = require(script.Parent.CombatService)
local MapService = require(script.Parent.MapService)
local MatchService = require(script.Parent.MatchService)
local MovementGuardService = require(script.Parent.MovementGuardService)

local HubService = {}

local HUB_ORIGIN = Vector3.new(0, 0, 400)
local FLOOR = Color3.fromRGB(44, 46, 54)
local WALL = Color3.fromRGB(58, 60, 68)
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

-- Néon défaillant (décoratif uniquement, jamais sur une information importante).
local function flicker(neon: BasePart)
	neon:SetAttribute("Flicker", true)
end

local function station(parent: Instance, key: string, position: Vector3, facing: Vector3)
	local model = Instance.new("Model")
	model.Name = "Station_" .. key
	local cframe = CFrame.lookAt(position, position + facing)
	local counter =
		part(model, "Counter", Vector3.new(8, 3.5, 3), cframe * CFrame.new(0, 1.75, 0), WALL, Enum.Material.Metal)
	local sign =
		part(model, "Sign", Vector3.new(7, 1.2, 0.3), cframe * CFrame.new(0, 7, 1.2), NEON[key], Enum.Material.Neon)
	sign.CanCollide = false
	flicker(sign)
	model.PrimaryPart = counter
	local prompt = Instance.new("ProximityPrompt")
	prompt:SetAttribute("ActionKey", "station.open")
	prompt:SetAttribute("ObjectKey", "station." .. key)
	prompt:SetAttribute("Station", key)
	prompt.ActionText = "station.open"
	prompt.ObjectText = "station." .. key
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter
	model.Parent = parent
end

local function build(): Folder
	local hub = Instance.new("Folder")
	hub.Name = "Terminus"
	local origin = CFrame.new(HUB_ORIGIN)

	-- Ancienne gare souterraine : quai, voûte, néons de récupération.
	part(hub, "Floor", Vector3.new(140, 2, 90), origin * CFrame.new(0, -1, 0), FLOOR, Enum.Material.Concrete)
	part(hub, "Ceiling", Vector3.new(140, 2, 90), origin * CFrame.new(0, 24, 0), WALL, Enum.Material.Concrete)
	part(hub, "WallNorth", Vector3.new(140, 24, 2), origin * CFrame.new(0, 12, -45), WALL, Enum.Material.Brick)
	part(hub, "WallSouth", Vector3.new(140, 24, 2), origin * CFrame.new(0, 12, 45), WALL, Enum.Material.Brick)
	part(hub, "WallEast", Vector3.new(2, 24, 90), origin * CFrame.new(70, 12, 0), WALL, Enum.Material.Brick)
	part(hub, "WallWest", Vector3.new(2, 24, 90), origin * CFrame.new(-70, 12, 0), WALL, Enum.Material.Brick)
	-- Voies désaffectées.
	for index = -1, 1, 2 do
		local rail = part(
			hub,
			"Rail",
			Vector3.new(130, 0.4, 0.6),
			origin * CFrame.new(0, 0.2, index * 3 - 30),
			Color3.fromRGB(90, 70, 60),
			Enum.Material.CorrodedMetal
		)
		rail.CanCollide = false
	end
	for index = 1, 6 do
		local light = part(
			hub,
			"Neon",
			Vector3.new(10, 0.3, 0.3),
			origin * CFrame.new(-60 + index * 20, 22.5, 0),
			NEON.insurer,
			Enum.Material.Neon
		)
		light.CanCollide = false
		if index % 2 == 0 then
			flicker(light)
		end
		local glow = Instance.new("PointLight")
		glow.Color = light.Color
		glow.Range = 24
		glow.Brightness = 1.2
		glow.Parent = light
	end

	-- Stations.
	station(hub, "vault", HUB_ORIGIN + Vector3.new(-50, 0, 30), Vector3.new(0, 0, -1))
	station(hub, "merchant", HUB_ORIGIN + Vector3.new(-25, 0, 30), Vector3.new(0, 0, -1))
	station(hub, "armorer", HUB_ORIGIN + Vector3.new(0, 0, 30), Vector3.new(0, 0, -1))
	station(hub, "insurer", HUB_ORIGIN + Vector3.new(25, 0, 30), Vector3.new(0, 0, -1))
	station(hub, "bazaar", HUB_ORIGIN + Vector3.new(50, 0, 30), Vector3.new(0, 0, -1))
	station(hub, "deploy", HUB_ORIGIN + Vector3.new(55, 0, -20), Vector3.new(-1, 0, 0))
	station(hub, "range", HUB_ORIGIN + Vector3.new(-55, 0, -20), Vector3.new(1, 0, 0))
	station(hub, "legends", HUB_ORIGIN + Vector3.new(0, 0, -38), Vector3.new(0, 0, 1))
	station(hub, "training", HUB_ORIGIN + Vector3.new(-55, 0, 5), Vector3.new(1, 0, 0))

	-- Points d'apparition du Terminus.
	for index = 1, 6 do
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "HubSpawn" .. index
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Size = Vector3.new(5, 1, 5)
		spawn.CFrame = origin * CFrame.new(-25 + index * 8, 0.5, 0)
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.Parent = hub
	end

	hub.Parent = Workspace
	return hub
end

-- Téléporte un joueur (hors partie) vers une position, en prévenant le contrôle de mouvement.
local function teleport(player: Player, cframe: CFrame)
	local character = player.Character
	if character == nil then
		return
	end
	character:PivotTo(cframe)
	MovementGuardService.reset(player)
end

function HubService.init() end

-- Un combattant peut-il se battre ici ? (en partie, ou dans l'arène d'entraînement)
local function inCombatArea(fighter: Fighter.Fighter): boolean
	local player = fighter.player
	if player == nil then
		return true -- robots, mercenaires, mannequins, objets
	end
	local participant = MatchService.participant(player)
	if participant and not participant.finished then
		return true
	end
	return ArenaService.contains(fighter.root.Position)
end

function HubService.start()
	if PlaceRole.isMatchServer() then
		return
	end
	local greybox = if RunService:IsStudio() then Config.Dev.testArenaInStudio else Config.Dev.greyboxOnline
	if greybox and Workspace:FindFirstChild("Terminus") == nil then
		build()
	end

	CombatService.setDamageFilter(function(attacker, target)
		if not inCombatArea(target) then
			return false
		end
		return attacker == nil or inCombatArea(attacker)
	end)

	-- Pavés « arène d'entraînement » ↔ « retour au Terminus » (bac à sable de Studio).
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		local key = prompt:GetAttribute("Station")
		if MatchService.isRunning() then
			return
		end
		if key == "training" then
			local spawns = MapService.deploySpawns()
			if #spawns > 0 then
				teleport(player, spawns[math.random(1, #spawns)].cframe)
			end
		elseif key == "hub" then
			teleport(player, HubService.spawnCFrame())
		end
	end)
end

-- Position d'arrivée au Terminus (retour de partie).
function HubService.spawnCFrame(): CFrame
	return CFrame.new(HUB_ORIGIN + Vector3.new(0, 4, 0))
end

return HubService
