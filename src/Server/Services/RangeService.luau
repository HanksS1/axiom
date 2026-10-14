--!strict
--[[
	RangeService : le stand de tir du Terminus (section 16.4).

	- Cibles d'entraînement : silhouettes mobiles partagées, que tout joueur
	  au stand peut toucher (dégâts affichés, jamais détruites). Attribut
	  `Practice` : pendant SON défi, un joueur ne les voit plus (masquage
	  local, RangeController) ; les autres joueurs continuent de s'en servir.
	- Essai d'une arme du coffre : le joueur reçoit une COPIE de son arme
	  (même modèle, même état, marquée « kit » : sans valeur, jamais
	  conservée) et une réserve de cellules prêtée. Tout est rendu en
	  quittant le stand : l'équipement réel n'est jamais touché.
	- Défi quotidien : arme imposée et suite de cibles identiques pour tous
	  (RangeRules, selon le jour UTC), 30 s, score = dégâts infligés (une
	  touche abat la cible). Les cibles d'un défi n'appartiennent qu'à son
	  joueur. Meilleur score du jour → classement quotidien.

	Le client ne fait que demander (essayer / lancer / arrêter) ; le serveur
	vérifie la présence au stand, la propriété de l'arme et calcule le score
	à partir des seules touches validées par CombatService.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Guard = require(Shared.Util.Guard)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local RangeRules = require(Shared.Progression.RangeRules)
local Types = require(Shared.Types)

local Fighter = require(script.Parent.Parent.Combat.Fighter)
local ItemFactory = require(script.Parent.Parent.Inventory.ItemFactory)
local PlaceRole = require(script.Parent.Parent.Matchmaking.PlaceRole)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local MatchService = require(script.Parent.MatchService)

type Fighter = Fighter.Fighter
type ItemInstance = Types.ItemInstance

local R = Config.Range
local Challenge = R.challenge

local RangeService = {}

local TICK = 1 / 20
local HIDDEN_OFFSET = Vector3.new(0, -40, 0)
local PLATE_COLOR = Color3.fromRGB(214, 210, 198)
local CHALLENGE_COLOR = Color3.fromRGB(255, 176, 32)
local MARK_COLOR = Color3.fromRGB(0, 229, 255)

type Target = {
	model: Model,
	plate: BasePart,
	head: BasePart,
	core: BasePart,
	fighter: Fighter,
	owner: Player?,
	visible: boolean,
	from: Vector3,
	to: Vector3,
	speed: number,
	bornAt: number,
	expiresAt: number,
}

type Session = {
	player: Player,
	fighter: Fighter,
	mode: "test" | "challenge",
	itemId: string,
	kitUid: string, -- copie prêtée : la seule arme qui compte pendant la séance
	savedInventory: Fighter.FighterInventory,
	-- Défi
	day: number,
	startsAt: number,
	endsAt: number,
	score: number,
	hits: number,
	nextSpec: number,
	nextSpawnAt: number,
	specs: { RangeRules.TargetSpec },
	targets: { Target },
}

local sessions: { [Player]: Session } = {}
local targetsByFighter: { [Fighter]: Target } = {}
local practice: { Target } = {}
local lane: BasePart? = nil
local counter: BasePart? = nil

-- Géométrie du stand (construit par HubService après le démarrage des services).
local function findRange(): boolean
	if lane and lane.Parent and counter and counter.Parent then
		return true
	end
	local terminus = Workspace:FindFirstChild("Terminus")
	local foundLane = if terminus then terminus:FindFirstChild("RangeLane", true) else nil
	local foundCounter = if terminus then terminus:FindFirstChild("RangeCounter", true) else nil
	if foundLane and foundLane:IsA("BasePart") and foundCounter and foundCounter:IsA("BasePart") then
		lane, counter = foundLane, foundCounter
		return true
	end
	return false
end

local function atRange(fighter: Fighter): boolean
	local c = counter
	return c ~= nil and (fighter.root.Position - c.Position).Magnitude <= R.maxDistance
end

-- Position dans la zone des cibles : profondeur (0..1), largeur (0..1), hauteur (0..1).
local function lanePoint(depth: number, across: number, height: number): Vector3
	local l = lane :: BasePart
	local size = l.Size
	return (
		l.CFrame
		* Vector3.new(
			(depth - 0.5) * (size.X - 2),
			-size.Y / 2 + 2 + height * (size.Y - 4.5),
			(across - 0.5) * (size.Z - 3)
		)
	)
end

-- Cibles ---------------------------------------------------------------------------

local function targetPart(model: Model, name: string, size: Vector3, color: Color3, material: EnumItem): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
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

local function createTarget(owner: Player?): Target
	local l = lane :: BasePart
	local model = Instance.new("Model")
	model.Name = "RangeTarget"
	local color = if owner then CHALLENGE_COLOR else PLATE_COLOR
	local plate = targetPart(model, "Plate", Vector3.new(2.2, 3, 0.3), color, Enum.Material.SmoothPlastic)
	local head = targetPart(model, "Head", Vector3.new(1.2, 1.2, 0.3), color, Enum.Material.SmoothPlastic)
	-- Cœur de cible néon (repère visuel, sans collision ni requête).
	local core = targetPart(model, "Core", Vector3.new(0.7, 0.7, 0.32), MARK_COLOR, Enum.Material.Neon)
	core.CanQuery = false
	model.PrimaryPart = plate
	model:SetAttribute("RangeTarget", true)
	if owner then
		model:SetAttribute("OwnerId", owner.UserId)
	end
	local home = l.Position + HIDDEN_OFFSET
	plate.CFrame = CFrame.new(home)
	head.CFrame = CFrame.new(home + Vector3.new(0, 2.1, 0))
	core.CFrame = CFrame.new(home + Vector3.new(0, 0.4, 0))
	model.Parent = l.Parent
	local fighter = Fighter.newObject(model, plate, R.practice.health, nil)
	CombatService.register(fighter)
	local target: Target = {
		model = model,
		plate = plate,
		head = head,
		core = core,
		fighter = fighter,
		owner = owner,
		visible = false,
		from = home,
		to = home,
		speed = 0,
		bornAt = 0,
		expiresAt = 0,
	}
	targetsByFighter[fighter] = target
	return target
end

local function destroyTarget(target: Target)
	targetsByFighter[target.fighter] = nil
	CombatService.unregister(target.fighter)
	target.model:Destroy()
end

local function placeAt(target: Target, position: Vector3, parts: { BasePart }, cframes: { CFrame })
	-- Face aux tireurs (le comptoir est à l'est de la zone).
	local c = counter
	local facing = if c then Vector3.new(c.Position.X, position.Y, c.Position.Z) else position + Vector3.xAxis
	local cframe = CFrame.lookAt(position, facing)
	table.insert(parts, target.plate)
	table.insert(cframes, cframe)
	table.insert(parts, target.head)
	table.insert(cframes, cframe * CFrame.new(0, 2.15, 0))
	table.insert(parts, target.core)
	table.insert(cframes, cframe * CFrame.new(0, 0.4, 0))
end

local function hide(target: Target, parts: { BasePart }, cframes: { CFrame })
	target.visible = false
	local home = (lane :: BasePart).Position + HIDDEN_OFFSET
	table.insert(parts, target.plate)
	table.insert(cframes, CFrame.new(home))
	table.insert(parts, target.head)
	table.insert(cframes, CFrame.new(home + Vector3.new(0, 2.1, 0)))
	table.insert(parts, target.core)
	table.insert(cframes, CFrame.new(home + Vector3.new(0, 0.4, 0)))
end

-- Position d'une cible mobile : aller-retour entre `from` et `to`.
local function movingPosition(target: Target, time: number): Vector3
	local distance = (target.to - target.from).Magnitude
	if target.speed <= 0 or distance < 0.1 then
		return target.from
	end
	local travel = ((time - target.bornAt) * target.speed) % (distance * 2)
	local alpha = if travel <= distance then travel / distance else 2 - travel / distance
	return target.from:Lerp(target.to, alpha)
end

local function spawnPractice()
	for index = 1, R.practice.targets do
		local target = createTarget(nil)
		target.model:SetAttribute("Practice", true)
		local depth = (index - 0.5) / R.practice.targets
		target.from = lanePoint(depth, 0, 0.2 + 0.3 * (index % 2))
		target.to = lanePoint(depth, 1, 0.2 + 0.3 * (index % 2))
		target.speed = R.practice.speedMin
			+ (R.practice.speedMax - R.practice.speedMin) * (index - 1) / math.max(1, R.practice.targets - 1)
		target.bornAt = os.clock() + index * 1.7
		target.visible = true
		table.insert(practice, target)
	end
end

-- Séances --------------------------------------------------------------------------

local function sendState(session: Session?, player: Player, extra: { [string]: any }?)
	local state: { [string]: any } = extra or {}
	if session then
		state.mode = session.mode
		state.itemId = session.itemId
		if session.mode == "challenge" then
			state.startsAt = session.startsAt
			state.endsAt = session.endsAt
			state.score = session.score
			state.hits = session.hits
		end
	end
	state.serverTime = os.clock()
	ServerNet.fire("RangeState", player, state)
end

-- Fin de séance : l'équipement réel est rétabli (le sac reste la seule vérité).
local function endSession(player: Player, reason: string)
	local session = sessions[player]
	if session == nil then
		return
	end
	sessions[player] = nil
	for _, target in session.targets do
		destroyTarget(target)
	end
	Fighter.forgetWeaponState(session.kitUid)
	local fighter = session.fighter
	if CombatService.getFighter(player) == fighter and Fighter.isAlive(fighter) then
		fighter.inventory = session.savedInventory
		Fighter.setWeapon(fighter, "ranged", nil)
		CombatService.equipmentChanged(fighter)
		CombatService.publish(fighter)
	end
	if player.Parent ~= Players then
		return
	end
	if session.mode == "challenge" and reason == "finished" then
		LeaderboardService.submitRange(player, session.day, session.score)
		sendState(nil, player, {
			finished = true,
			score = session.score,
			hits = session.hits,
			itemId = session.itemId,
		})
	else
		sendState(nil, player, { ended = reason })
	end
end

local function lend(fighter: Fighter, item: ItemInstance)
	local info = ItemCatalog.get(item.itemId)
	local def = if info then info.def else nil
	fighter.inventory = Fighter.simpleInventory({ [def.cell] = R.reserveCells })
	Fighter.setWeapon(fighter, "ranged", item)
	fighter.activeSlot = "ranged"
	CombatService.publish(fighter)
end

-- Vérifications communes : au stand, hors partie, vivant.
local function eligible(player: Player): Fighter?
	if not findRange() then
		return nil
	end
	local participant = MatchService.participant(player)
	if participant and not participant.finished then
		return nil
	end
	local fighter = CombatService.getFighter(player)
	if fighter == nil or not Fighter.isAlive(fighter) or not atRange(fighter) then
		ServerNet.notify(player, "range.tooFar")
		return nil
	end
	return fighter
end

-- Arme possédée par le joueur (coffre, équipement ou sac du profil).
local function ownedRanged(player: Player, uid: string): ItemInstance?
	local profile = DataService.getProfile(player)
	if profile == nil then
		return nil
	end
	local function check(item: ItemInstance?): ItemInstance?
		if item and item.uid == uid then
			local info = ItemCatalog.get(item.itemId)
			if info and info.category == "ranged" then
				return item
			end
		end
		return nil
	end
	for _, item in profile.vault do
		local found = check(item)
		if found then
			return found
		end
	end
	for _, item in profile.bag do
		local found = check(item)
		if found then
			return found
		end
	end
	return check(profile.loadout.ranged)
end

local function newSession(player: Player, fighter: Fighter, mode: "test" | "challenge", item: ItemInstance): Session
	return {
		player = player,
		fighter = fighter,
		mode = mode,
		itemId = item.itemId,
		kitUid = item.uid,
		savedInventory = fighter.inventory,
		day = 0,
		startsAt = 0,
		endsAt = 0,
		score = 0,
		hits = 0,
		nextSpec = 1,
		nextSpawnAt = 0,
		specs = {},
		targets = {},
	}
end

local function startTest(player: Player, uid: string)
	local current = sessions[player]
	if current and current.mode == "challenge" then
		ServerNet.notify(player, "range.busy")
		return
	end
	local fighter = eligible(player)
	if fighter == nil then
		return
	end
	local owned = ownedRanged(player, uid)
	if owned == nil then
		ServerNet.flag(player, "RangeAction", "arme non possédée")
		return
	end
	endSession(player, "switch")
	-- Copie sans valeur : nouvel identifiant, marquée kit (jamais conservée).
	local copy = ItemFactory.create(owned.itemId, { condition = owned.condition })
	copy.isKit = true
	local session = newSession(player, fighter, "test", copy)
	sessions[player] = session
	lend(fighter, copy)
	sendState(session, player)
end

local function startChallenge(player: Player)
	if sessions[player] and sessions[player].mode == "challenge" then
		return
	end
	local running = 0
	for _, session in sessions do
		if session.mode == "challenge" then
			running += 1
		end
	end
	if running >= Challenge.maxConcurrent then
		ServerNet.notify(player, "range.full")
		return
	end
	local fighter = eligible(player)
	if fighter == nil then
		return
	end
	endSession(player, "switch")
	local day = RangeRules.day(os.time())
	local copy = ItemFactory.create(RangeRules.weaponOfDay(day), { condition = Challenge.condition })
	copy.isKit = true
	local session = newSession(player, fighter, "challenge", copy)
	local now = os.clock()
	session.day = day
	session.specs = RangeRules.targets(day)
	session.startsAt = now + Challenge.countdown
	session.endsAt = session.startsAt + Challenge.duration
	session.nextSpawnAt = session.startsAt
	for _ = 1, Challenge.maxAlive do
		table.insert(session.targets, createTarget(player))
	end
	sessions[player] = session
	lend(fighter, copy)
	sendState(session, player)
end

local function onAction(player: Player, action: string, uid: string?)
	if action == "test" and uid then
		startTest(player, uid)
	elseif action == "challenge" then
		startChallenge(player)
	elseif action == "stop" then
		endSession(player, "stopped")
	end
end

-- Dégâts : verdict pour les cibles du stand (nil = pas une cible du stand).
function RangeService.damageVerdict(attacker: Fighter?, target: Fighter): boolean?
	local entry = targetsByFighter[target]
	if entry == nil then
		return nil
	end
	if attacker == nil or attacker.player == nil or not entry.visible then
		return false
	end
	if entry.owner then
		-- Défi : seule l'arme imposée (la copie prêtée) compte ; pas de mêlée.
		local session = sessions[entry.owner]
		local ranged = attacker.ranged
		return attacker.player == entry.owner
			and session ~= nil
			and os.clock() >= session.startsAt
			and attacker.activeSlot == "ranged"
			and ranged ~= nil
			and ranged.item.uid == session.kitUid
	end
	return atRange(attacker)
end

local function onDamaged(target: Fighter, attacker: Fighter?, amount: number)
	local entry = targetsByFighter[target]
	if entry == nil or attacker == nil or attacker.player == nil then
		return
	end
	-- Les cibles ne meurent jamais : PV remis au maximum.
	target.health = target.maxHealth
	local points = RangeRules.points(amount)
	ServerNet.fire("RangeHit", attacker.player, entry.head.Position, points)
	if entry.owner then
		local session = sessions[entry.owner]
		if session and entry.visible then
			session.score += points
			session.hits += 1
			local parts, cframes = {}, {}
			hide(entry, parts, cframes)
			Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
			sendState(session, session.player)
		end
	end
end

-- Boucle (20 Hz) : déplacement des cibles, apparitions, fin des défis, contrôles.
local function step()
	if not findRange() then
		return
	end
	if #practice == 0 then
		spawnPractice()
	end
	local time = os.clock()
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	-- Cibles d'entraînement immobiles quand personne n'est près du stand (aucune réplication inutile).
	local c = counter :: BasePart
	local anyoneNear = next(sessions) ~= nil
	if not anyoneNear then
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if root and root:IsA("BasePart") and (root.Position - c.Position).Magnitude < R.maxDistance * 4 then
				anyoneNear = true
				break
			end
		end
	end
	if anyoneNear then
		for _, target in practice do
			if time >= target.bornAt then
				placeAt(target, movingPosition(target, time), parts, cframes)
			end
		end
	end
	for player, session in sessions do
		local fighter = session.fighter
		if
			player.Parent ~= Players
			or CombatService.getFighter(player) ~= fighter
			or not Fighter.isAlive(fighter)
			or not atRange(fighter)
			-- L'arme prêtée a été remplacée (équipement modifié) : séance terminée.
			or fighter.ranged == nil
			or fighter.ranged.item.uid ~= session.kitUid
		then
			task.defer(endSession, player, "left")
			continue
		end
		if session.mode ~= "challenge" then
			continue
		end
		if time >= session.endsAt then
			task.defer(endSession, player, "finished")
			continue
		end
		for _, target in session.targets do
			if target.visible and time >= target.expiresAt then
				hide(target, parts, cframes)
			elseif not target.visible and time >= session.nextSpawnAt and session.nextSpec <= #session.specs then
				local spec = session.specs[session.nextSpec]
				session.nextSpec += 1
				session.nextSpawnAt = time + Challenge.respawnDelay
				target.from = lanePoint(spec.depth, spec.from, spec.height)
				target.to = lanePoint(spec.depth, spec.to, spec.height)
				target.speed = spec.speed
				target.bornAt = time
				target.expiresAt = time + Challenge.targetLifetime
				target.visible = true
			end
			if target.visible then
				placeAt(target, movingPosition(target, time), parts, cframes)
			end
		end
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function RangeService.isInSession(player: Player): boolean
	return sessions[player] ~= nil
end

-- Une séance est close avant tout départ en partie.
function RangeService.stop(player: Player)
	endSession(player, "stopped")
end

function RangeService.init()
	ServerNet.onEvent(
		"RangeAction",
		Guard.tuple(Guard.enum({ "test", "challenge", "stop" }), Guard.optional(Guard.uid())),
		onAction
	)
end

function RangeService.start()
	if PlaceRole.isMatchServer() then
		return
	end
	CombatService.FighterDamaged:Connect(onDamaged)
	Players.PlayerRemoving:Connect(function(player)
		endSession(player, "left")
	end)
	MatchService.Started:Connect(function()
		for player in sessions do
			endSession(player, "match")
		end
	end)
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated >= TICK then
			accumulated = 0
			step()
		end
	end)
end

return RangeService
