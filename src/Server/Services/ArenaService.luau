--!strict
--[[
	ArenaService : l'Arène FFA (ancienne arène d'entraînement), voisine du
	Terminus.

	Construite si la place ne contient pas déjà de carte (dossier « Map »
	ou « Arena » dans Workspace), d'après le plan pur Server/Maps/ArenaLayout
	(enceinte fermée, bastions, passerelle, couverts, décor industriel ; testé).
	Mannequins d'entraînement équipés de gilets / casques de différents états.
	L'éclairage est posé par le client du joueur qui s'y trouve
	(ArenaLightingController) : le Terminus voisin garde le sien.

	Bac à sable (hors partie) : aucun risque, aucun gain.
	- Aucune caisse, aucun butin : rien ne peut en être retiré (LootService
	  ne crée ni sac de dépouille ni objet au sol en bac à sable).
	- Un joueur mort dans l'arène y réapparaît après `Dev.arenaRespawnDelay`
	  secondes, équipement intact (copie du profil, voir CharacterService).
	  Le gestionnaire de mort n'est installé que hors partie : MatchService
	  installe le sien pendant une partie et gère lui-même les apparitions.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Zone = require(Shared.Match.Zone)

local Fighter = require(script.Parent.Parent.Combat.Fighter)
local Kit = require(script.Parent.Parent.Hub.Kit)
local ItemFactory = require(script.Parent.Parent.Inventory.ItemFactory)
local ArenaLayout = require(script.Parent.Parent.Maps.ArenaLayout)
local LayoutBuilder = require(script.Parent.Parent.Maps.LayoutBuilder)
local MapRenderer = require(script.Parent.Parent.Maps.MapRenderer)
local PlaceRole = require(script.Parent.Parent.Matchmaking.PlaceRole)
local CombatService = require(script.Parent.CombatService)
local LootService = require(script.Parent.LootService)
local MapService = require(script.Parent.MapService)
local MovementGuardService = require(script.Parent.MovementGuardService)

local Dev = Config.Dev

local ArenaService = {}

local NEON_CYAN = Color3.fromRGB(0, 229, 255)
local DARK = Color3.fromRGB(28, 30, 36)

local function buildArena(): Folder
	local arena = Instance.new("Folder")
	arena.Name = "Arena"
	local layout = ArenaLayout.build(LayoutBuilder.random(Config.Arena.seed))
	-- Pièces créées d'un coup (quelques centaines) : pas d'étalement sur plusieurs
	-- images, pour que l'arène soit complète avant la suite du démarrage.
	for _, spec in layout.parts do
		MapRenderer.createPart(spec, Vector3.zero).Parent = arena
	end
	local markers = Instance.new("Folder")
	markers.Name = "Markers"
	markers.Parent = arena
	for _, marker in layout.markers do
		MapService.placeMarker(markers, marker.tag, marker.cframe, marker.attributes)
	end

	-- Retour au Terminus (les joueurs apparaissent au Terminus hors partie).
	local half = Dev.arenaSize / 2
	local pad = Kit.part(
		arena,
		"HubPad",
		Vector3.new(6, 1, 6),
		CFrame.new(0, 0.5, -half + 8),
		NEON_CYAN,
		Enum.Material.Neon,
		{ transparency = 0.4 }
	)
	local prompt = Instance.new("ProximityPrompt")
	prompt:SetAttribute("ActionKey", "station.open")
	prompt:SetAttribute("ObjectKey", "station.hub")
	prompt:SetAttribute("Station", "hub")
	prompt.ActionText = "station.open"
	prompt.ObjectText = "station.hub"
	prompt.HoldDuration = 0.3
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad
	-- Enseigne « Arène FFA » au-dessus du pavé (texte localisé côté client).
	local sign = Kit.decor(
		arena,
		"ArenaSign",
		Vector3.new(14, 2.4, 0.4),
		CFrame.new(0, 13, -half + 1.4),
		DARK,
		Enum.Material.Metal
	)
	Kit.text(sign, Enum.NormalId.Back, "station.training", NEON_CYAN, Enum.Font.GothamBlack)
	Kit.light(sign, NEON_CYAN, 18, 1.2, true)

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

-- Bac à sable (hors partie) : aucun butin, réapparition dans l'arène.
local sandbox = true
local built = false

-- Délai maximal d'attente du combattant d'un personnage qui vient d'apparaître (s).
local FIGHTER_WAIT = 3

--[[
	Bouclier de réapparition (Config.Arena.spawnShield) pour un joueur qui
	apparaît dans l'arène. Le combattant est créé un peu après le personnage
	(CharacterService) : on l'attend, sans quoi personne ne peut de toute façon
	le toucher. N'agit que dans l'arène (CombatService.grantSpawnShield).
]]
function ArenaService.protect(player: Player)
	local character = player.Character
	task.spawn(function()
		local deadline = os.clock() + FIGHTER_WAIT
		while os.clock() < deadline do
			local fighter = CombatService.getFighter(player)
			if player.Character ~= character or player.Parent ~= Players then
				return
			end
			if fighter and fighter.character == character then
				CombatService.grantSpawnShield(fighter)
				return
			end
			task.wait()
		end
	end)
end

-- Mort hors partie. Dans l'arène : désintégration, puis réapparition sur place
-- après `Dev.arenaRespawnDelay`. Ailleurs : comportement par défaut (le personnage
-- meurt après la désintégration, Roblox le fait réapparaître au Terminus).
local function sandboxDeath(fighter: Fighter.Fighter, _killer: Fighter.Fighter?)
	local player = fighter.player
	if player == nil or not ArenaService.contains(fighter.root.Position) then
		task.delay(Config.Combat.death.disintegrateDuration, function()
			if fighter.humanoid.Parent ~= nil then
				fighter.humanoid.Health = 0
			end
		end)
		return
	end
	local dead = fighter.character
	task.delay(Dev.arenaRespawnDelay, function()
		-- Partie lancée entre-temps, joueur parti ou déjà réapparu : rien à faire.
		if not sandbox or player.Parent ~= Players or player.Character ~= dead then
			return
		end
		player:LoadCharacter()
		local character = player.Character
		local spawns = MapService.deploySpawns()
		if character and #spawns > 0 and sandbox then
			character:PivotTo(spawns[math.random(1, #spawns)].cframe + Vector3.new(0, 3, 0))
			MovementGuardService.reset(player)
			ArenaService.protect(player)
		end
	end)
end

-- Active / désactive le bac à sable (désactivé pendant une partie).
function ArenaService.setSandbox(enabled: boolean)
	sandbox = enabled
	LootService.setSandbox(enabled)
	-- Hors partie, l'arène gère les morts ; en partie, MatchService installe son gestionnaire.
	if enabled and built then
		CombatService.setDeathHandler(sandboxDeath)
	end
end

-- La carte active est-elle l'Arène FFA (petite carte de partie en Studio) ?
function ArenaService.isArena(): boolean
	local root = MapService.root()
	return root ~= nil and root.Name == "Arena"
end

-- Position dans l'Arène FFA (zone de combat hors partie). Bornes : Shared/Match/Zone.
function ArenaService.contains(position: Vector3): boolean
	return Workspace:FindFirstChild("Arena") ~= nil and Zone.inArena(position)
end

function ArenaService.init() end

function ArenaService.start()
	-- Arène FFA (greybox) : en Studio, et sur le hub en ligne tant que le vrai
	-- Terminus n'est pas modélisé. Jamais sur un serveur de partie (les cartes suffisent).
	if PlaceRole.isMatchServer() then
		return
	end
	if not (if RunService:IsStudio() then Dev.testArenaInStudio else Dev.greyboxOnline) then
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
	MapService.setRoot(arena)
	for _, spec in Dev.dummies do
		task.spawn(spawnDummy, arena, spec)
	end
	built = true
	ArenaService.setSandbox(true)

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
