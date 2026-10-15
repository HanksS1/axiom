--!strict
--[[
	MercenaryService : mercenaires IA de remplissage (section 11).

	- Ils complètent les parties incomplètes (16 places) avec un équipement
	  dans la plage de SE du mode et un pseudo généré ; en duo, par paires.
	- IA côté serveur, plus simple que celle d'un joueur :
	  · combat : cible visible la plus proche (joueurs, autres mercenaires,
	    robots), tirs avec une précision qui dépend du mode et de la distance,
	    recharge, soins et batteries, mêlée au contact ;
	  · loot : fouille des caisses et sacs proches (le plus précieux d'abord) ;
	  · extraction : à un moment tiré au hasard, sac plein, ou à l'alerte ;
	    il doit tenir la zone (bloquée par un ennemi) comme un joueur.
	- Pas de réanimation par orbe. À sa mort, son équipement tombe dans un
	  sac de dépouille, comme celui d'un joueur.
]]

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Damage = require(Shared.Combat.Damage)
local InventoryLogic = require(Shared.Items.InventoryLogic)
local Matchmaking = require(Shared.Match.Matchmaking)
local MatchRules = require(Shared.Match.MatchRules)
local RobotBrain = require(Shared.Robots.RobotBrain)
local Types = require(Shared.Types)
local try = require(Shared.Util.Try)
local WeaponLogic = require(Shared.Combat.WeaponLogic)

local Fighter = require(script.Parent.Parent.Combat.Fighter)
local ItemFactory = require(script.Parent.Parent.Inventory.ItemFactory)
local MercenaryGear = require(script.Parent.Parent.Robots.MercenaryGear)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local CharacterService = require(script.Parent.CharacterService)
local CombatService = require(script.Parent.CombatService)
local ExtractionService = require(script.Parent.ExtractionService)
local LootService = require(script.Parent.LootService)
local MapService = require(script.Parent.MapService)

type Fighter = Fighter.Fighter
type ItemInstance = Types.ItemInstance

local Merc = Config.Mercenaries
local AI = Merc.ai

local MercenaryService = {}

export type Partner = {
	teamId: string,
	cframe: CFrame,
	leader: Player,
}

type Mercenary = {
	fighter: Fighter,
	name: string,
	leader: Player?, -- duo aléatoire : joueur que ce mercenaire accompagne
	extractAt: number, -- secondes de partie
	extracting: boolean,
	extractProgress: number,
	target: Fighter?,
	targetSince: number,
	lastKnown: Vector3?,
	lastKnownAt: number,
	goal: LootService.Container?,
	lootStartedAt: number?,
	destination: Vector3?,
	waypoints: { Vector3 },
	waypointIndex: number,
	nextPathAt: number,
	nextUpdate: number,
	nextStrafeAt: number,
	strafeSign: number,
	lastUpdate: number,
}

local mercs: { [Fighter]: Mercenary } = {}
local claimed: { [LootService.Container]: Mercenary } = {}
local folder: Folder? = nil
local random = Random.new()
local modeId = "easy"
local visionMultiplier = 1 -- coupures de courant (Noyau Zéro)
local startTime = 0
local alerted = false

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function mercFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "Mercenaries"
	created.Parent = Workspace
	folder = created
	return created
end

-- Pseudos générés, uniques dans la partie.
local usedNames: { [string]: boolean } = {}
local function generateName(): string
	for _ = 1, 50 do
		local prefixes = Merc.names.prefixes
		local name = prefixes[random:NextInteger(1, #prefixes)]
			.. "_"
			.. random:NextInteger(Merc.names.numberMin, Merc.names.numberMax)
		if not usedNames[name] then
			usedNames[name] = true
			return name
		end
	end
	return "Merc_" .. random:NextInteger(100, 999)
end

-- Déplacement ----------------------------------------------------------------

local function groundAt(position: Vector3): Vector3
	rayParams.FilterDescendantsInstances = { mercFolder() }
	local hit = Workspace:Raycast(position + Vector3.new(0, 20, 0), Vector3.new(0, -200, 0), rayParams)
	return if hit then hit.Position else position
end

local function moveTo(merc: Mercenary, point: Vector3)
	local fighter = merc.fighter
	local root = fighter.root
	local humanoid = fighter.humanoid
	-- En marche, le Humanoid s'oriente lui-même dans le sens du déplacement.
	humanoid.AutoRotate = true
	local orient = root:FindFirstChild("Facing")
	if orient and orient:IsA("AlignOrientation") then
		orient.Enabled = false
	end
	rayParams.FilterDescendantsInstances = { mercFolder() }
	local offset = point - root.Position
	if Workspace:Raycast(root.Position, offset, rayParams) == nil then
		merc.waypoints = {}
		humanoid:MoveTo(point)
		return
	end
	local time = now()
	if time >= merc.nextPathAt then
		merc.nextPathAt = time + AI.pathRefresh
		task.spawn(function()
			local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
			local ok = pcall(function()
				path:ComputeAsync(root.Position, point)
			end)
			if ok and path.Status == Enum.PathStatus.Success and mercs[fighter] == merc then
				local points = {}
				for _, waypoint in path:GetWaypoints() do
					table.insert(points, waypoint.Position)
				end
				merc.waypoints = points
				merc.waypointIndex = 2
			end
		end)
	end
	local nextPoint = merc.waypoints[merc.waypointIndex]
	if nextPoint and (nextPoint - root.Position).Magnitude < 3 then
		merc.waypointIndex += 1
		nextPoint = merc.waypoints[merc.waypointIndex]
	end
	humanoid:MoveTo(nextPoint or point)
end

local function stop(merc: Mercenary)
	merc.fighter.humanoid:MoveTo(merc.fighter.root.Position)
end

-- Tourne le mercenaire vers un point, en continu (contrainte d'orientation, comme
-- les robots) : jamais d'écriture directe du CFrame, qui le ferait tourner par paliers.
local function face(merc: Mercenary, point: Vector3)
	local root = merc.fighter.root
	local flat = Vector3.new(point.X, root.Position.Y, point.Z)
	local orient = root:FindFirstChild("Facing")
	if (flat - root.Position).Magnitude > 0.1 and orient and orient:IsA("AlignOrientation") then
		merc.fighter.humanoid.AutoRotate = false
		orient.CFrame = CFrame.lookAt(root.Position, flat).Rotation
		orient.Enabled = true
	end
end

-- Perception -----------------------------------------------------------------

local function headOf(fighter: Fighter): Vector3
	local head = fighter.character:FindFirstChild("Head")
	return if head and head:IsA("BasePart") then head.Position else fighter.root.Position + Vector3.new(0, 1.5, 0)
end

local function hasLineOfSight(from: Fighter, to: Fighter): boolean
	rayParams.FilterDescendantsInstances = { from.character, to.character }
	local origin = headOf(from)
	return Workspace:Raycast(origin, to.root.Position - origin, rayParams) == nil
end

-- Ennemi visible le plus proche (au plus quelques lancers de rayon par mise à jour).
local function perceive(merc: Mercenary): Fighter?
	local fighter = merc.fighter
	local position = fighter.root.Position
	local forward = fighter.root.CFrame.LookVector
	local candidates: { { fighter: Fighter, distance: number } } = {}
	for _, other in CombatService.allFighters() do
		if other == fighter or other.kind == "object" or not Fighter.isAlive(other) then
			continue
		end
		if Fighter.sameTeam(fighter, other) then
			continue
		end
		local offset = other.root.Position - position
		local distance = offset.Magnitude
		if distance > AI.visionRange * visionMultiplier then
			continue
		end
		-- Gardien enfoui / intangible : invisible.
		if other.character:GetAttribute("Hidden") == true then
			continue
		end
		if distance > AI.closeAwareness and not RobotBrain.inCone(forward, offset, AI.visionAngle) then
			continue
		end
		table.insert(candidates, { fighter = other, distance = distance })
	end
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)
	for index = 1, math.min(#candidates, AI.maxRaycastsPerUpdate) do
		local candidate = candidates[index].fighter
		if hasLineOfSight(fighter, candidate) then
			return candidate
		end
	end
	return nil
end

-- Combat ---------------------------------------------------------------------

local function shoot(merc: Mercenary, target: Fighter, distance: number, time: number)
	local fighter = merc.fighter
	local ranged = fighter.ranged
	if ranged == nil then
		return
	end
	local def = ranged.def
	local state = ranged.state
	CombatService.finishReload(fighter)
	local cells = fighter.inventory:countCells(def.cell)
	local canFire, block = WeaponLogic.canFire(def, state, time, cells)
	if not canFire then
		if block == "empty" and WeaponLogic.canReload(def, state, cells) then
			WeaponLogic.startReload(def, state, time)
			CombatService.publish(fighter) -- animation de recharge
		end
		return
	end
	local fired = WeaponLogic.fire(def, state, time)
	if fired.cellsConsumed > 0 then
		fighter.inventory:takeCells(def.cell, fired.cellsConsumed)
	end
	local origin = headOf(fighter)
	-- L'arme pointe vers la cible (posture vue par les joueurs).
	local aim = target.root.Position - origin
	if aim.Magnitude > 0.1 then
		fighter.character:SetAttribute("AimPitch", math.round(math.deg(math.asin(math.clamp(aim.Unit.Y, -1, 1)))))
	end
	CombatService.NoiseMade:Fire(origin, def.noiseRadius)

	-- Précision : selon le mode, baisse avec la distance (au-delà de la portée efficace).
	local accuracy = (AI.accuracy :: any)[modeId] or AI.accuracy.easy
	accuracy *= math.clamp(1.25 - distance / math.max(1, def.effectiveRange) * 0.5, 0.25, 1.1)
	local condition = ranged.item.condition :: number
	local total, head = 0, false
	local endpoints = {}
	for _ = 1, fired.projectiles do
		if random:NextNumber() < accuracy then
			local isHead = random:NextNumber() < AI.headshotChance
			head = head or isHead
			total += Damage.ranged({
				def = def,
				condition = condition,
				distance = distance,
				isHead = isHead,
				helmet = target.helmet,
				targetKind = target.kind,
			})
			table.insert(endpoints, target.root.Position)
		else
			table.insert(
				endpoints,
				target.root.Position
					+ Vector3.new(
						random:NextNumber(-1, 1) * AI.missSpread,
						random:NextNumber(-0.5, 1) * AI.missSpread,
						random:NextNumber(-1, 1) * AI.missSpread
					)
			)
		end
	end
	if total > 0 then
		CombatService.rangedHit(target, total, fighter, {
			sourcePosition = origin,
			isHead = head,
			itemId = ranged.item.itemId,
		})
	end
	-- Tracés : quelques points suffisent (plombs d'un fusil à pompe).
	while #endpoints > 4 do
		table.remove(endpoints)
	end
	ServerNet.fireAll("ShotFired", nil, ranged.item.itemId, origin, endpoints, fighter.character)
	if state.ammo <= 0 and def.capacity then
		local remaining = fighter.inventory:countCells(def.cell)
		if WeaponLogic.canReload(def, state, remaining) then
			WeaponLogic.startReload(def, state, time)
			CombatService.publish(fighter)
		end
	end
end

local function melee(merc: Mercenary, target: Fighter, time: number)
	local fighter = merc.fighter
	local weapon = fighter.melee
	if weapon == nil or time - weapon.lastAttackAt < 1 / weapon.def.attacksPerSecond then
		return
	end
	weapon.lastAttackAt = time
	ServerNet.fireAll("MeleeSwing", nil, weapon.item.itemId, fighter.character)
	CombatService.meleeHit(fighter, target, Damage.melee(weapon.def, weapon.item.condition :: number), {
		breaksParry = weapon.def.breaksParry,
		parryBreakStun = weapon.def.parryBreakStun,
		shieldIgnore = weapon.def.shieldIgnore,
	})
end

local function setSlot(fighter: Fighter, slot: Fighter.WeaponSlot)
	if fighter.activeSlot ~= slot and (if slot == "ranged" then fighter.ranged else fighter.melee) ~= nil then
		fighter.activeSlot = slot
		CombatService.publish(fighter)
	end
end

-- Soins et batteries quand il le faut (hors tir en cours).
local function selfCare(merc: Mercenary)
	local fighter = merc.fighter
	local bag = fighter.bag
	if bag == nil or fighter.usingItemId ~= nil then
		return
	end
	if fighter.health < fighter.maxHealth * AI.healBelow and InventoryLogic.count(bag, "nanite_injector") > 0 then
		CombatService.useConsumable(fighter, "nanite_injector")
	elseif
		fighter.maxShield > 0
		and fighter.shield < fighter.maxShield * AI.shieldBelow
		and InventoryLogic.count(bag, "shield_battery") > 0
	then
		CombatService.useConsumable(fighter, "shield_battery")
	end
end

local function fight(merc: Mercenary, target: Fighter, time: number)
	local fighter = merc.fighter
	local distance = (target.root.Position - fighter.root.Position).Magnitude
	face(merc, target.root.Position)
	local meleeRange = if fighter.melee then fighter.melee.def.range else 0
	local useMelee = fighter.melee ~= nil
		and (
			fighter.ranged == nil
			or distance <= meleeRange + 1
			or target.kind == "robot" and distance <= meleeRange + 2
		)
	if useMelee then
		setSlot(fighter, "melee")
		if distance > meleeRange then
			moveTo(merc, target.root.Position)
		else
			stop(merc)
			melee(merc, target, time)
		end
		return
	end
	local ranged = fighter.ranged
	if ranged == nil then
		return
	end
	setSlot(fighter, "ranged")
	local range = ranged.def.effectiveRange
	if distance > range * 1.1 then
		moveTo(merc, target.root.Position)
	elseif time >= merc.nextStrafeAt then
		-- Pas de côté pour ne pas être une cible immobile.
		merc.nextStrafeAt = time + AI.strafeInterval
		merc.strafeSign = -merc.strafeSign
		local side = fighter.root.CFrame.RightVector * AI.strafeDistance * merc.strafeSign
		fighter.humanoid:MoveTo(fighter.root.Position + side)
	end
	if time - merc.targetSince >= AI.reactionTime then
		shoot(merc, target, distance, time)
	end
end

-- Loot et extraction ---------------------------------------------------------

local function bagFull(merc: Mercenary): boolean
	local bag = merc.fighter.bag
	return bag == nil or InventoryLogic.free(bag) < AI.fullBagFreeUp
end

local function releaseGoal(merc: Mercenary)
	local goal = merc.goal
	if goal and claimed[goal] == merc then
		claimed[goal] = nil
	end
	merc.goal = nil
	merc.lootStartedAt = nil
end

local function chooseLoot(merc: Mercenary): LootService.Container?
	local position = merc.fighter.root.Position
	local best, bestDistance = nil, AI.lootRadius
	for _, container in LootService.lootables() do
		local owner = claimed[container]
		if owner and owner ~= merc and mercs[owner.fighter] == owner then
			continue
		end
		local distance = (LootService.positionOf(container) - position).Magnitude
		if distance < bestDistance then
			best, bestDistance = container, distance
		end
	end
	return best
end

local function nearestZone(position: Vector3): Vector3?
	local best, bestDistance = nil, math.huge
	for _, zone in ExtractionService.openZones() do
		local distance = (zone - position).Magnitude
		if distance < bestDistance then
			best, bestDistance = zone, distance
		end
	end
	return best
end

-- Ennemis vivants (d'une autre équipe) dans un rayon autour d'un point.
local function enemiesNear(merc: Mercenary, point: Vector3, radius: number): number
	local count = 0
	for _, other in CombatService.allFighters() do
		if
			other ~= merc.fighter
			and other.kind ~= "object"
			and Fighter.isAlive(other)
			and not Fighter.sameTeam(other, merc.fighter)
			and (other.root.Position - point).Magnitude <= radius
		then
			count += 1
		end
	end
	return count
end

local function remove(merc: Mercenary)
	releaseGoal(merc)
	mercs[merc.fighter] = nil
	if merc.fighter.character.Parent then
		merc.fighter.character:Destroy()
	end
end

local function extractStep(merc: Mercenary, dt: number)
	local position = merc.fighter.root.Position
	local zone = nearestZone(position)
	if zone == nil then
		return
	end
	local radius = Config.Match.extraction.radius
	local flat = Vector3.new(zone.X - position.X, 0, zone.Z - position.Z).Magnitude
	if flat > radius * 0.6 then
		CombatService.setBotMovement(merc.fighter, true)
		moveTo(merc, zone)
		merc.extractProgress = 0
		return
	end
	stop(merc)
	CombatService.setBotMovement(merc.fighter, false)
	local progress, status = MatchRules.stepExtraction(merc.extractProgress, dt, 1, 1, enemiesNear(merc, zone, radius))
	merc.extractProgress = progress
	if status == "done" then
		remove(merc)
	end
end

local function wander(merc: Mercenary)
	local position = merc.fighter.root.Position
	if merc.destination == nil or (merc.destination :: Vector3 - position).Magnitude < 5 then
		local spawns = MapService.crateSpawns()
		if #spawns > 0 and random:NextNumber() < 0.6 then
			merc.destination = spawns[random:NextInteger(1, #spawns)].cframe.Position
		else
			local angle = random:NextNumber(0, math.pi * 2)
			local distance = random:NextNumber(10, AI.wanderRadius)
			merc.destination = groundAt(position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance)
		end
	end
	moveTo(merc, merc.destination :: Vector3)
end

local function update(merc: Mercenary, time: number)
	local fighter = merc.fighter
	local dt = math.min(1, time - merc.lastUpdate)
	merc.lastUpdate = time
	if not Fighter.isAlive(fighter) then
		return
	end
	if CombatService.isStunned(fighter) then
		stop(merc)
		return
	end

	-- Cible : visible, ou celui qui vient de le blesser.
	local seen = perceive(merc)
	local attacker = fighter.lastAttacker
	if seen == nil and attacker and Fighter.isAlive(attacker) and not Fighter.sameTeam(attacker, fighter) then
		merc.lastKnown = attacker.root.Position
		merc.lastKnownAt = time
		fighter.lastAttacker = nil
	end
	if seen then
		if merc.target ~= seen then
			merc.target = seen
			merc.targetSince = time
		end
		merc.lastKnown = seen.root.Position
		merc.lastKnownAt = time
		CombatService.setBotMovement(fighter, false)
		selfCare(merc)
		fight(merc, seen, time)
		return
	end
	merc.target = nil
	selfCare(merc)

	-- Poursuite brève de la dernière position connue.
	local lastKnown = merc.lastKnown
	if lastKnown and time - merc.lastKnownAt < AI.memory and not merc.extracting then
		CombatService.setBotMovement(fighter, false)
		moveTo(merc, lastKnown)
		return
	end
	merc.lastKnown = nil

	-- Coéquipier d'un joueur : il le suit ; sans lui (extrait, mort, parti), il s'extrait.
	local leader = merc.leader
	if leader and not merc.extracting then
		local leaderFighter = CombatService.getFighter(leader)
		if leaderFighter == nil or not Fighter.isAlive(leaderFighter) then
			merc.leader = nil
			merc.extracting = true
			releaseGoal(merc)
		else
			local gap = (leaderFighter.root.Position - fighter.root.Position).Magnitude
			if gap > AI.followDistance then
				releaseGoal(merc)
				CombatService.setBotMovement(fighter, gap > AI.followDistance * 2)
				moveTo(merc, leaderFighter.root.Position)
				return
			end
		end
	end

	local elapsed = time - startTime
	if not merc.extracting and (alerted or elapsed >= merc.extractAt or bagFull(merc)) then
		merc.extracting = true
		releaseGoal(merc)
	end
	if merc.extracting then
		extractStep(merc, dt)
		return
	end

	-- Loot : rejoindre le conteneur choisi, le fouiller quelques secondes.
	local goal = merc.goal
	if goal == nil or LootService.get(goal.id) ~= goal then
		releaseGoal(merc)
		goal = chooseLoot(merc)
		if goal then
			merc.goal = goal
			claimed[goal] = merc
		end
	end
	if goal then
		local target = LootService.positionOf(goal)
		if (target - fighter.root.Position).Magnitude > 5 then
			CombatService.setBotMovement(fighter, (target - fighter.root.Position).Magnitude > 25)
			moveTo(merc, target)
			merc.lootStartedAt = nil
			return
		end
		stop(merc)
		CombatService.setBotMovement(fighter, false)
		if merc.lootStartedAt == nil then
			merc.lootStartedAt = time
		elseif time - (merc.lootStartedAt :: number) >= AI.lootTime then
			if fighter.bag then
				LootService.botLoot(goal, fighter.bag)
				Fighter.syncEquipment(fighter)
			end
			releaseGoal(merc)
		end
		return
	end
	CombatService.setBotMovement(fighter, false)
	wander(merc)
end

-- Apparition -----------------------------------------------------------------

local function spawnMercenary(teamId: string, cframe: CFrame, leader: Player?)
	local ok, model = pcall(function()
		local description = Instance.new("HumanoidDescription")
		local tone =
			Color3.fromHSV(random:NextNumber(0.02, 0.1), random:NextNumber(0.2, 0.6), random:NextNumber(0.35, 0.9))
		description.HeadColor = tone
		description.LeftArmColor = tone
		description.RightArmColor = tone
		description.TorsoColor = Color3.fromHSV(random:NextNumber(), 0.3, random:NextNumber(0.2, 0.5))
		description.LeftLegColor = Color3.fromRGB(40, 42, 48)
		description.RightLegColor = Color3.fromRGB(40, 42, 48)
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or model == nil then
		warn(`[MercenaryService] mercenaire non créé : {model}`)
		return
	end
	local character = model :: Model
	local name = generateName()
	character.Name = name
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.DisplayName = name
	humanoid.MaxHealth = Config.Combat.maxHealth
	humanoid.Health = Config.Combat.maxHealth
	humanoid.UseJumpPower = false
	root.CanQuery = false
	local health = character:FindFirstChild("Health")
	if health then
		health:Destroy()
	end
	character:PivotTo(cframe)
	-- Orientation lissée (désactivée en marche, voir face / moveTo).
	local attachment = Instance.new("Attachment")
	attachment.Name = "AlignAttachment"
	attachment.Parent = root
	local orient = Instance.new("AlignOrientation")
	orient.Name = "Facing"
	orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orient.Attachment0 = attachment
	orient.MaxTorque = math.huge
	orient.MaxAngularVelocity = Config.Robots.ai.turnRate
	orient.Responsiveness = Config.Robots.ai.turnResponsiveness
	orient.CFrame = cframe.Rotation
	orient.Enabled = false
	orient.Parent = root
	character.Parent = mercFolder()
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	local loadout, bagItems = MercenaryGear.build(modeId, random, ItemFactory.create)
	local bag = InventoryLogic.new(loadout, bagItems)
	local fighter = Fighter.new("bot", nil, character, humanoid, root, {
		ranged = loadout.ranged,
		melee = loadout.melee,
		helmet = loadout.helmet,
		vest = loadout.vest,
	}, Fighter.simpleInventory({}))
	fighter.teamId = teamId
	fighter.bag = bag
	fighter.inventory = Fighter.bagInventory(fighter)
	CombatService.register(fighter)
	CharacterService.attachVisuals(fighter)

	local time = now()
	mercs[fighter] = {
		fighter = fighter,
		name = name,
		leader = leader,
		extractAt = random:NextNumber(AI.extractAfter.min, AI.extractAfter.max),
		extracting = false,
		extractProgress = 0,
		target = nil,
		targetSince = 0,
		lastKnown = nil,
		lastKnownAt = 0,
		goal = nil,
		lootStartedAt = nil,
		destination = nil,
		waypoints = {},
		waypointIndex = 1,
		nextPathAt = 0,
		nextUpdate = time + random:NextNumber(0, 1 / AI.updateRate),
		nextStrafeAt = 0,
		strafeSign = 1,
		lastUpdate = time,
	}
end

--[[
	Déploie `count` mercenaires (par paires en duo) sur les points de départ
	donnés, au début d'une partie.
]]
function MercenaryService.deploy(
	newModeId: string,
	format: Matchmaking.Format,
	count: number,
	spawns: { CFrame },
	matchStart: number
)
	modeId = newModeId
	startTime = matchStart
	alerted = false
	if #spawns == 0 then
		spawns = { CFrame.new(0, 5, 0) }
	end
	for index, size in Matchmaking.botTeams(format, count) do
		local base = spawns[(index - 1) % #spawns + 1]
		for member = 1, size do
			task.spawn(spawnMercenary, "m" .. index, base * CFrame.new((member - 1) * 4 + 2, 0, 3))
		end
	end
end

-- Duo aléatoire impair : un mercenaire rejoint l'équipe d'un joueur seul.
function MercenaryService.deployPartners(newModeId: string, partners: { Partner }, matchStart: number)
	modeId = newModeId
	startTime = matchStart
	for _, partner in partners do
		task.spawn(spawnMercenary, partner.teamId, partner.cframe, partner.leader)
	end
end

-- Alerte de 12:00 : tous les mercenaires partent vers les extractions.
function MercenaryService.alert()
	alerted = true
end

function MercenaryService.clear()
	for _, merc in mercs do
		remove(merc)
	end
	table.clear(mercs)
	table.clear(claimed)
	table.clear(usedNames)
	alerted = false
end

function MercenaryService.count(): number
	local count = 0
	for fighter in mercs do
		if Fighter.isAlive(fighter) then
			count += 1
		end
	end
	return count
end

function MercenaryService.setVisionMultiplier(multiplier: number)
	visionMultiplier = math.clamp(multiplier, 0.1, 1)
end

function MercenaryService.isMercenary(fighter: Fighter): boolean
	return mercs[fighter] ~= nil
end

function MercenaryService.init()
	-- Mort : l'équipement tombe dans un sac de dépouille.
	CombatService.FighterDied:Connect(function(fighter)
		local merc = mercs[fighter]
		if merc == nil then
			return
		end
		releaseGoal(merc)
		local bag = fighter.bag
		fighter.bag = nil
		if bag then
			LootService.spawnDeathBag(fighter.root.Position, InventoryLogic.drainAll(bag), merc.name)
		end
		mercs[fighter] = nil
		-- Sans gestionnaire de partie, le corps disparaît après la désintégration.
		task.delay(Config.Combat.death.disintegrateDuration + 0.5, function()
			if fighter.character.Parent then
				fighter.character:Destroy()
			end
		end)
	end)
end

function MercenaryService.start()
	RunService.Heartbeat:Connect(function()
		if next(mercs) == nil then
			return
		end
		local time = now()
		for _, merc in mercs do
			if time >= merc.nextUpdate then
				merc.nextUpdate = time + 1 / AI.updateRate
				local ok, err = try(update, merc, time)
				if not ok then
					warn(`[MercenaryService] {merc.name} : {err}`)
				end
			end
		end
	end)
end

return MercenaryService
