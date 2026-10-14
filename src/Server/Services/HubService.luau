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
	Les cibles du stand de tir suivent leurs propres règles (RangeService).
]]

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local Fighter = require(script.Parent.Parent.Combat.Fighter)
local HubNpcs = require(script.Parent.Parent.Hub.HubNpcs)
local TerminusBuilder = require(script.Parent.Parent.Hub.TerminusBuilder)
local PlaceRole = require(script.Parent.Parent.Matchmaking.PlaceRole)
local ArenaService = require(script.Parent.ArenaService)
local CombatService = require(script.Parent.CombatService)
local MapRuntimeService = require(script.Parent.MapRuntimeService)
local MapService = require(script.Parent.MapService)
local MatchService = require(script.Parent.MatchService)
local MovementGuardService = require(script.Parent.MovementGuardService)
local RangeService = require(script.Parent.RangeService)
local TutorialService = require(script.Parent.TutorialService)

local HubService = {}

local HUB_ORIGIN = Vector3.new(0, 0, 400)

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
	-- Éclairage du lobby fixé par le code (Config.Maps.hub), remis au retour de partie.
	MapRuntimeService.applyHubLighting()
	local greybox = if RunService:IsStudio() then Config.Dev.testArenaInStudio else Config.Dev.greyboxOnline
	if greybox and Workspace:FindFirstChild("Terminus") == nil then
		local built = TerminusBuilder.build(HUB_ORIGIN)
		built.folder.Parent = Workspace
		-- Les survivants derrière les comptoirs.
		local npcs = Instance.new("Folder")
		npcs.Name = "Npcs"
		npcs.Parent = built.folder
		for _, spot in built.stations do
			task.spawn(HubNpcs.spawn, npcs, spot.key, spot.npc)
		end
	end

	CombatService.setDamageFilter(function(attacker, target)
		-- Cibles du stand de tir : règles propres (joueur au stand, propriétaire du défi).
		local range = RangeService.damageVerdict(attacker, target)
		if range ~= nil then
			return range
		end
		-- Tutoriel : simulation privée (seuls le joueur et ses entités d'entraînement).
		local tutorial = TutorialService.damageVerdict(attacker, target)
		if tutorial ~= nil then
			return tutorial
		end
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
	return CFrame.new(HUB_ORIGIN + Vector3.new(0, 4, 4))
end

return HubService
