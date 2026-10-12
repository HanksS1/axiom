--!strict
--[[
	TutorialService : le tutoriel obligatoire (section 15.2).

	Une simulation PRIVÉE par joueur (construite loin du Terminus, sur le
	serveur du hub : aucune place supplémentaire à configurer). Une ancienne
	mercenaire guide le joueur par radio : se déplacer, tirer, parer,
	ramasser, se soigner, s'extraire (30 s dans la zone).

	- Lancé automatiquement au premier chargement du profil
	  (`tutorialDone = false`), et rejouable depuis les paramètres.
	- 5 minutes au maximum : passé ce délai, il se termine de lui-même.
	- Récompense : niveau 2 (minimum pour jouer), kit de base, puis retour
	  au Terminus avec une courte cinématique d'arrivée (côté client).
	- Personne ne meurt dans le tutoriel ; personne ne peut y blesser un
	  autre joueur ; l'équipement du tutoriel (kit de base) n'est jamais
	  conservé.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Guard = require(Shared.Util.Guard)
local InventoryLogic = require(Shared.Items.InventoryLogic)
local TutorialRules = require(Shared.Progression.TutorialRules)

local Fighter = require(script.Parent.Parent.Combat.Fighter)
local TutorialBuilder = require(script.Parent.Parent.Hub.TutorialBuilder)
local ItemFactory = require(script.Parent.Parent.Inventory.ItemFactory)
local PlaceRole = require(script.Parent.Parent.Matchmaking.PlaceRole)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local LootService = require(script.Parent.LootService)
local MatchService = require(script.Parent.MatchService)
local MovementGuardService = require(script.Parent.MovementGuardService)
local RangeService = require(script.Parent.RangeService)

type Fighter = Fighter.Fighter
type Step = TutorialRules.Step

local Tutorial = Config.Progression.tutorial

local TutorialService = {}

local TICK = 0.2
local HEAL_ITEM = "nanite_injector"
local EYE_IDLE = Color3.fromRGB(255, 138, 0)
local EYE_ANGRY = Color3.fromRGB(255, 30, 30)

type Session = {
	player: Player,
	slot: number,
	built: TutorialBuilder.Built,
	step: Step,
	startedAt: number,
	replay: boolean,
	-- Entités de l'étape en cours
	targets: { [Fighter]: boolean },
	hits: number,
	dummy: Fighter?,
	dummyEye: BasePart?,
	nextSwingAt: number,
	windUpAt: number?,
	crate: LootService.Container?,
	extractProgress: number,
	lastSentProgress: number,
}

local sessions: { [Player]: Session } = {}
local slots: { [number]: Player } = {}
-- Entités du tutoriel → joueur propriétaire (cibles, robot d'entraînement).
local owners: { [Fighter]: Player } = {}

local function now(): number
	return os.clock()
end

local function fighterOf(session: Session): Fighter?
	local fighter = CombatService.getFighter(session.player)
	return if fighter and Fighter.isAlive(fighter) then fighter else nil
end

local function send(session: Session, extra: { [string]: any }?)
	local state: { [string]: any } = extra or {}
	state.active = true
	state.step = session.step
	state.index = TutorialRules.index(session.step)
	state.total = #TutorialRules.steps
	state.timeLeft = math.max(0, Tutorial.maxDuration - (now() - session.startedAt))
	state.replay = session.replay
	if session.step == "shoot" then
		state.count = session.hits
		state.goal = Tutorial.targets
	elseif session.step == "extract" then
		state.progress = session.extractProgress
		state.goal = Tutorial.extractDuration
	end
	ServerNet.fire("TutorialState", session.player, state)
end

-- Entités ----------------------------------------------------------------------------

local function release(fighter: Fighter)
	owners[fighter] = nil
	CombatService.unregister(fighter)
	if fighter.character.Parent then
		fighter.character:Destroy()
	end
end

local function clearEntities(session: Session)
	for target in session.targets do
		release(target)
	end
	session.targets = {}
	local dummy = session.dummy
	if dummy then
		release(dummy)
		session.dummy = nil
		session.dummyEye = nil
	end
	local crate = session.crate
	if crate then
		LootService.remove(crate)
		session.crate = nil
	end
end

local function simplePart(
	model: Model,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: EnumItem
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material :: any
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

local function spawnTargets(session: Session)
	for _, spot in session.built.targetSpots do
		local model = Instance.new("Model")
		model.Name = "TutorialTarget"
		local plate = simplePart(
			model,
			"Plate",
			Vector3.new(2.4, 3.2, 0.3),
			spot,
			Color3.fromRGB(214, 210, 198),
			Enum.Material.SmoothPlastic
		)
		simplePart(
			model,
			"Head",
			Vector3.new(1.3, 1.3, 0.3),
			spot * CFrame.new(0, 2.3, 0),
			Color3.fromRGB(214, 210, 198),
			Enum.Material.SmoothPlastic
		)
		local core = simplePart(
			model,
			"Core",
			Vector3.new(0.8, 0.8, 0.32),
			spot * CFrame.new(0, 0.4, 0),
			Color3.fromRGB(255, 138, 0),
			Enum.Material.Neon
		)
		core.CanQuery = false
		model.PrimaryPart = plate
		model.Parent = session.built.folder
		local fighter = Fighter.newObject(model, plate, 100000, nil)
		CombatService.register(fighter)
		owners[fighter] = session.player
		session.targets[fighter] = true
	end
end

-- Robot d'entraînement : silhouette d'Exécuteur greybox, frappe au corps à corps.
local function spawnDummy(session: Session)
	local spot = session.built.dummySpot
	local model = Instance.new("Model")
	model.Name = "TrainingBot"
	local metal = Color3.fromRGB(70, 74, 82)
	local torso = simplePart(
		model,
		"Torso",
		Vector3.new(3, 3.4, 1.6),
		spot * CFrame.new(0, 3.6, 0),
		metal,
		Enum.Material.DiamondPlate
	)
	simplePart(model, "Legs", Vector3.new(2.4, 1.9, 1.2), spot * CFrame.new(0, 0.95, 0), metal, Enum.Material.Metal)
	simplePart(model, "Head", Vector3.new(1.6, 1.3, 1.4), spot * CFrame.new(0, 6, 0), metal, Enum.Material.Metal)
	local eye = simplePart(
		model,
		"Eye",
		Vector3.new(1.1, 0.3, 0.2),
		spot * CFrame.new(0, 6.1, -0.71),
		EYE_IDLE,
		Enum.Material.Neon
	)
	eye.CanQuery = false
	for _, side in { -1, 1 } do
		simplePart(
			model,
			"Arm",
			Vector3.new(0.8, 3, 0.8),
			spot * CFrame.new(side * 2, 3.6, -0.3),
			metal,
			Enum.Material.Metal
		)
	end
	model.PrimaryPart = torso
	model.Parent = session.built.folder
	local fighter = Fighter.newObject(model, torso, 100000, nil)
	CombatService.register(fighter)
	owners[fighter] = session.player
	session.dummy = fighter
	session.dummyEye = eye
	session.nextSwingAt = now() + 2
	session.windUpAt = nil
end

-- Le tutoriel fournit toujours de quoi se soigner.
local function ensureHealItem(fighter: Fighter)
	local bag = fighter.bag
	if bag and InventoryLogic.count(bag, HEAL_ITEM) == 0 then
		InventoryLogic.store(bag, ItemFactory.create(HEAL_ITEM, { stack = 1, isKit = true }))
		if fighter.onInventoryChanged then
			fighter.onInventoryChanged()
		end
	end
end

-- Étapes -----------------------------------------------------------------------------

local function showBeacon(session: Session)
	for key, beacon in session.built.beacons do
		beacon.Transparency = if key == session.step or (session.step == "heal" and key == "loot") then 0.55 else 1
	end
end

local finish: (session: Session, reason: string) -> ()

local function enterStep(session: Session, step: Step)
	clearEntities(session)
	session.step = step
	local fighter = fighterOf(session)
	if step == "shoot" then
		session.hits = 0
		spawnTargets(session)
	elseif step == "parry" then
		spawnDummy(session)
	elseif step == "loot" then
		session.crate = LootService.spawnCrate(session.built.crateSpot, "supply")
	elseif step == "heal" then
		-- Décharge d'AXIOM : le joueur doit se soigner.
		if fighter then
			ensureHealItem(fighter)
			CombatService.setHealth(fighter, Tutorial.healTo)
		end
		send(session, { cue = "zap" })
		showBeacon(session)
		return
	elseif step == "extract" then
		session.extractProgress = 0
		session.lastSentProgress = -1
	end
	showBeacon(session)
	send(session)
end

local function advance(session: Session)
	local next: Step? = TutorialRules.next(session.step)
	if next then
		enterStep(session, next :: Step)
	else
		finish(session, "completed")
	end
end

-- Place le personnage dans la simulation, avec le kit de base.
local function placeCharacter(session: Session)
	local player = session.player
	local character = player.Character
	if character == nil then
		return
	end
	-- Attend le combattant du nouveau personnage (créé par CharacterService).
	local fighter: Fighter? = nil
	for _ = 1, 50 do
		local candidate = CombatService.getFighter(player)
		if candidate and candidate.character == character then
			fighter = candidate
			break
		end
		task.wait(0.1)
	end
	if fighter == nil or sessions[player] ~= session then
		return
	end
	local start = session.built.start
	pcall(function()
		player:RequestStreamAroundAsync(start.Position)
	end)
	character:PivotTo(start)
	MovementGuardService.reset(player)
	local loadout, bag = ItemFactory.createBaseKit()
	InventoryService.attach(fighter, InventoryLogic.new(loadout, bag))
	CombatService.setHealth(fighter, fighter.maxHealth)
	if session.step == "heal" then
		ensureHealItem(fighter)
		CombatService.setHealth(fighter, Tutorial.healTo)
	end
	send(session)
end

local function freeSlot(): number?
	for slot = 1, Tutorial.maxSlots do
		if slots[slot] == nil then
			return slot
		end
	end
	return nil
end

local function close(session: Session)
	sessions[session.player] = nil
	slots[session.slot] = nil
	clearEntities(session)
	session.built.folder:Destroy()
end

function finish(session: Session, reason: string)
	if sessions[session.player] ~= session then
		return
	end
	close(session)
	local player = session.player
	if player.Parent ~= Players then
		return
	end
	DataService.update(player, TutorialRules.complete)
	task.spawn(DataService.saveNow, player)
	local profile = DataService.getProfile(player)
	ServerNet.fire("TutorialState", player, {
		done = true,
		reason = reason,
		replay = session.replay,
		level = if profile then profile.level else nil,
	})
	-- Retour au Terminus avec l'équipement réel (le kit du tutoriel disparaît).
	player:LoadCharacter()
end

-- Abandon sans récompense (départ en partie, déconnexion, rejeu interrompu).
local function abort(session: Session)
	if sessions[session.player] ~= session then
		return
	end
	close(session)
	if session.player.Parent == Players then
		ServerNet.fire("TutorialState", session.player, { done = true, reason = "aborted", replay = session.replay })
	end
end

local function begin(player: Player, replay: boolean)
	if sessions[player] or PlaceRole.isMatchServer() then
		return
	end
	local participant = MatchService.participant(player)
	if participant and not participant.finished then
		return
	end
	local slot = freeSlot()
	if slot == nil then
		-- Serveur saturé (ne devrait pas arriver : plus d'emplacements que de joueurs).
		warn("[TutorialService] aucun emplacement libre")
		return
	end
	RangeService.stop(player)
	local origin = Vector3.new(Tutorial.originX + (slot - 1) * Tutorial.slotSpacing, 0, Tutorial.originZ)
	local built = TutorialBuilder.build(origin, Tutorial.extractRadius)
	built.folder.Name = `Tutorial_{player.UserId}`
	built.folder.Parent = Workspace
	local session: Session = {
		player = player,
		slot = slot,
		built = built,
		step = "move",
		startedAt = now(),
		replay = replay,
		targets = {},
		hits = 0,
		dummy = nil,
		dummyEye = nil,
		nextSwingAt = 0,
		windUpAt = nil,
		crate = nil,
		extractProgress = 0,
		lastSentProgress = -1,
	}
	slots[slot] = player
	sessions[player] = session
	showBeacon(session)
	task.spawn(placeCharacter, session)
end

-- Boucle -----------------------------------------------------------------------------

local function stepParry(session: Session, fighter: Fighter, time: number)
	local dummy = session.dummy
	local eye = session.dummyEye
	if dummy == nil or eye == nil then
		return
	end
	local distance = (fighter.root.Position - dummy.root.Position).Magnitude
	local windUpAt = session.windUpAt
	if windUpAt == nil then
		if time >= session.nextSwingAt and distance <= Tutorial.parryRange then
			session.windUpAt = time
			eye.Color = EYE_ANGRY
			send(session, { cue = "windup" })
		end
		return
	end
	if time < windUpAt + Tutorial.parryWindUp then
		return
	end
	session.windUpAt = nil
	session.nextSwingAt = time + Tutorial.parryInterval
	eye.Color = EYE_IDLE
	if distance <= Tutorial.parryRange + 2 then
		CombatService.meleeHit(dummy, fighter, Tutorial.parryDamage)
	end
end

local function tick(dt: number)
	local time = now()
	for player, session in sessions do
		if player.Parent ~= Players then
			continue
		end
		local participant = MatchService.participant(player)
		if participant and not participant.finished then
			task.defer(abort, session)
			continue
		end
		if TutorialRules.timedOut(session.startedAt, time) then
			task.defer(finish, session, "timeout")
			continue
		end
		local fighter = fighterOf(session)
		if fighter == nil then
			continue
		end
		-- Personnage hors de la simulation (chute, téléportation) : retour au départ.
		if (fighter.root.Position - session.built.start.Position).Magnitude > 220 then
			fighter.character:PivotTo(session.built.start)
			MovementGuardService.reset(player)
		end
		local step = session.step
		if step == "move" then
			local flat = fighter.root.Position - session.built.moveBeacon
			if Vector3.new(flat.X, 0, flat.Z).Magnitude <= Tutorial.moveRadius then
				advance(session)
			end
		elseif step == "parry" then
			stepParry(session, fighter, time)
		elseif step == "heal" then
			if fighter.health >= fighter.maxHealth * 0.9 then
				advance(session)
			end
		elseif step == "extract" then
			local flat = fighter.root.Position - session.built.extractCenter
			if Vector3.new(flat.X, 0, flat.Z).Magnitude <= Tutorial.extractRadius then
				session.extractProgress = math.min(Tutorial.extractDuration, session.extractProgress + dt)
			end
			if session.extractProgress >= Tutorial.extractDuration then
				advance(session)
			elseif math.floor(session.extractProgress) ~= session.lastSentProgress then
				session.lastSentProgress = math.floor(session.extractProgress)
				send(session)
			end
		end
	end
end

-- Événements de combat et de loot ------------------------------------------------------

local function onDamaged(target: Fighter, _attacker: Fighter?, _amount: number)
	local owner = owners[target]
	if owner then
		local session = sessions[owner]
		target.health = target.maxHealth
		if session and session.step == "shoot" and session.targets[target] then
			session.targets[target] = nil
			release(target)
			session.hits += 1
			if session.hits >= Tutorial.targets then
				advance(session)
			else
				send(session)
			end
		end
		return
	end
	-- Personne ne meurt dans le tutoriel.
	local player = target.player
	if player and sessions[player] and target.health < Tutorial.minHealth and sessions[player].step ~= "heal" then
		CombatService.setHealth(target, target.maxHealth)
	end
end

local function onParry(defender: Fighter, attacker: Fighter, outcome: string)
	local player = defender.player
	local session = if player then sessions[player] else nil
	if session and session.step == "parry" and attacker == session.dummy and outcome ~= "broken" then
		send(session, { cue = if outcome == "perfect" then "perfect" else "parried" })
		advance(session)
	end
end

local function onItemTaken(player: Player)
	local session = sessions[player]
	if session and session.step == "loot" then
		advance(session)
	end
end

local function onConsumable(fighter: Fighter, itemId: string)
	local player = fighter.player
	local session = if player then sessions[player] else nil
	local def = Config.Equipment.consumables[itemId]
	if session and session.step == "heal" and def and def.effect.heal then
		advance(session)
	end
end

-- Verdict de dégâts (nil = hors tutoriel) : seul le joueur touche ses cibles,
-- seul son robot d'entraînement le frappe, rien d'autre ne passe.
function TutorialService.damageVerdict(attacker: Fighter?, target: Fighter): boolean?
	local owner = owners[target]
	if owner then
		return attacker ~= nil and attacker.player == owner
	end
	local attackerOwner = if attacker then owners[attacker] else nil
	if attackerOwner then
		return target.player == attackerOwner
	end
	local targetPlayer = target.player
	if targetPlayer and sessions[targetPlayer] then
		return false
	end
	local attackerPlayer = if attacker then attacker.player else nil
	if attackerPlayer and sessions[attackerPlayer] then
		return false
	end
	return nil
end

-- Outil de test (Studio) : termine immédiatement le tutoriel en cours.
function TutorialService.finishNow(player: Player)
	local session = sessions[player]
	if session then
		finish(session, "completed")
	end
end

function TutorialService.isInTutorial(player: Player): boolean
	return sessions[player] ~= nil
end

local function onAction(player: Player, action: string)
	local session = sessions[player]
	if action == "restart" then
		if session == nil then
			begin(player, true)
		end
	elseif action == "skip" and session then
		-- Seul un joueur ayant déjà terminé le tutoriel peut le quitter.
		local profile = DataService.getProfile(player)
		if profile and profile.tutorialDone then
			abort(session)
			player:LoadCharacter()
		end
	end
end

function TutorialService.init()
	ServerNet.onEvent("TutorialAction", Guard.tuple(Guard.enum({ "restart", "skip" })), onAction)
end

function TutorialService.start()
	if PlaceRole.isMatchServer() then
		return
	end
	local function onProfile(player: Player)
		local profile = DataService.getProfile(player)
		if profile and not profile.tutorialDone then
			begin(player, false)
		end
	end
	DataService.ProfileLoaded:Connect(onProfile)
	for _, player in Players:GetPlayers() do
		task.spawn(onProfile, player)
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			local session = sessions[player]
			if session then
				task.spawn(placeCharacter, session)
			end
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function()
			local session = sessions[player]
			if session then
				task.spawn(placeCharacter, session)
			end
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session then
			abort(session)
		end
	end)
	CombatService.FighterDamaged:Connect(onDamaged)
	CombatService.ParryResolved:Connect(onParry)
	CombatService.ConsumableUsed:Connect(onConsumable)
	LootService.ItemTaken:Connect(onItemTaken)

	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated >= TICK then
			local elapsed = accumulated
			accumulated = 0
			tick(elapsed)
		end
	end)
end

return TutorialService
