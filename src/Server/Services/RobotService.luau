--!strict
--[[
	RobotService : les robots d'AXIOM (section 10).

	- Population initiale : de 20 à 28 robots (60 % en garnison dans les
	  zones à risque, 40 % en patrouilles légères), un Gardien dans la zone
	  principale. Pas de réapparition (sauf vague d'alerte et mécaniques de carte).
	- IA côté serveur, 8 mises à jour par seconde (étalées), logique coupée
	  sans joueur à moins de 150 studs. Machine à états : RobotBrain.
	- Perception : cône de 90°, portée selon le type, ligne de vue (les murs
	  et la fumée bloquent). Audition : tirs (rayon de l'arme), alarmes.
	- La Mouche alerte les robots à moins de 40 studs.
	- Multiplicateurs du mode : PV, dégâts, précision, temps de réaction.
	- Loot à la destruction (LootGenerator.robot), points de score.
	- Vague d'alerte à 12:00 : 6 à 10 robots convergent vers les extractions.
]]

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local RobotBrain = require(Shared.Robots.RobotBrain)
local try = require(Shared.Util.Try)

local Fighter = require(script.Parent.Parent.Combat.Fighter)
local ItemFactory = require(script.Parent.Parent.Inventory.ItemFactory)
local LootGenerator = require(script.Parent.Parent.Loot.LootGenerator)
local RobotFactory = require(script.Parent.Parent.Robots.RobotFactory)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local CombatService = require(script.Parent.CombatService)
local ExtractionService = require(script.Parent.ExtractionService)
local LootService = require(script.Parent.LootService)
local MapService = require(script.Parent.MapService)

type Fighter = Fighter.Fighter

local AI = Config.Robots.ai
local Density = Config.Robots.density

local RobotService = {}

type Robot = {
	fighter: Fighter,
	def: any,
	brain: RobotBrain.Brain,
	home: Vector3,
	garrison: boolean,
	destination: Vector3?,
	waypoints: { Vector3 },
	waypointIndex: number,
	nextPathAt: number,
	nextAttackAt: number,
	burstLeft: number,
	nextUpdate: number,
	noise: Vector3?,
	alertedAt: Vector3?,
	wave: Vector3?, -- vague d'alerte : extraction visée
	eye: BasePart,
	stationary: boolean, -- tourelle, bras fixé au plafond : ne se déplace jamais
	behavior: string?, -- Gardiens : "burrow" (s'enfouit), "phase" (devient intangible)
	dormantRadius: number?, -- Exécuteur de la chaîne : inactif tant que personne n'approche
	nextSpecialAt: number,
	hiddenUntil: number,
	partState: { [BasePart]: { transparency: number, query: boolean } }?,
}

export type SpawnOptions = {
	override: { [string]: any }?, -- valeurs remplaçant celles de la config (Gardien d'une carte)
	behavior: string?,
	dormantRadius: number?,
}

local robots: { [Fighter]: Robot } = {}
local folder: Folder?
local random = Random.new()
local modeId = "easy"
local visionMultiplier = 1 -- coupures de courant (Noyau Zéro)

local visionParams = RaycastParams.new()
visionParams.FilterType = Enum.RaycastFilterType.Exclude
visionParams.IgnoreWater = true

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function robotFolder(): Folder
	if folder == nil or folder.Parent == nil then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "Robots"
		newFolder.Parent = Workspace
		folder = newFolder
	end
	return folder :: Folder
end

local function mode(): any
	return Config.Modes.byId[modeId]
end

-- Point au sol sous une position (les robots apparaissent posés).
local function groundAt(position: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { robotFolder() }
	-- Depuis juste au-dessus du point : un étage supérieur ne doit pas être pris pour le sol.
	local hit = Workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -80, 0), params)
	return if hit then hit.Position else position
end

local function weightedPick(weights: { [string]: number }): string
	local ids = {}
	local total = 0
	for id, weight in weights do
		table.insert(ids, id)
		total += weight
	end
	table.sort(ids)
	local roll = random:NextNumber(0, total)
	for _, id in ids do
		roll -= weights[id]
		if roll < 0 then
			return id
		end
	end
	return ids[#ids]
end

-- La fumée bloque la vision (intersection segment / sphère).
local function blockedBySmoke(from: Vector3, to: Vector3): boolean
	local segment = to - from
	local length = segment.Magnitude
	if length < 1e-3 then
		return false
	end
	local direction = segment / length
	for _, smoke in CollectionService:GetTagged("Smoke") do
		if smoke:IsA("BasePart") then
			local radius = smoke:GetAttribute("Radius")
			local r = if type(radius) == "number" then radius else smoke.Size.X / 2
			local toCenter = smoke.Position - from
			local along = math.clamp(toCenter:Dot(direction), 0, length)
			if (from + direction * along - smoke.Position).Magnitude <= r then
				return true
			end
		end
	end
	return false
end

-- Cibles vivantes (joueurs, mercenaires IA) visibles par le robot.
local function perceive(robot: Robot): { RobotBrain.VisibleTarget }
	local fighter = robot.fighter
	local eyePosition = robot.eye.Position
	local forward = fighter.root.CFrame.LookVector
	local visible = {}
	for _, other in CombatService.allFighters() do
		if (other.kind == "player" or other.kind == "bot") and Fighter.isAlive(other) then
			local offset = other.root.Position - eyePosition
			local distance = offset.Magnitude
			if distance <= robot.def.visionRange * visionMultiplier then
				-- Très près : perçu même hors du cône (bruit de pas, contact).
				if distance < 8 or RobotBrain.inCone(forward, offset, AI.visionAngle) then
					visionParams.FilterDescendantsInstances = { robotFolder(), other.character }
					local hit = Workspace:Raycast(eyePosition, offset, visionParams)
					if hit == nil and not blockedBySmoke(eyePosition, other.root.Position) then
						table.insert(visible, { id = other, position = other.root.Position, distance = distance })
					end
				end
			end
		end
	end
	return visible
end

local function nearestPlayerDistance(position: Vector3): number
	local best = math.huge
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if root and root:IsA("BasePart") then
			best = math.min(best, (root.Position - position).Magnitude)
		end
	end
	return best
end

local function face(robot: Robot, point: Vector3)
	local root = robot.fighter.root
	local flat = Vector3.new(point.X, root.Position.Y, point.Z)
	if (flat - root.Position).Magnitude < 0.1 then
		return
	end
	if robot.def.flying then
		local orient = root:FindFirstChild("Facing")
		if orient and orient:IsA("AlignOrientation") then
			orient.CFrame = CFrame.lookAt(root.Position, flat).Rotation
		end
	else
		robot.fighter.humanoid.AutoRotate = false
		root.CFrame = CFrame.lookAt(root.Position, flat)
	end
end

-- Déplacement : direct si la voie est libre, sinon chemin calculé (limité dans le temps).
local function moveTo(robot: Robot, point: Vector3)
	if robot.stationary then
		return
	end
	local root = robot.fighter.root
	if robot.def.flying then
		local hover = root:FindFirstChild("Hover")
		if hover and hover:IsA("AlignPosition") then
			local altitude = groundAt(point).Y + 8
			local target = Vector3.new(point.X, altitude, point.Z)
			local offset = target - root.Position
			local step = math.min(offset.Magnitude, robot.def.speed / AI.updateRate * 1.5)
			hover.Position = if offset.Magnitude > 0.1 then root.Position + offset.Unit * step else target
		end
		return
	end
	local humanoid = robot.fighter.humanoid
	humanoid.AutoRotate = true
	local time = now()
	visionParams.FilterDescendantsInstances = { robotFolder() }
	local clear = Workspace:Raycast(root.Position, point - root.Position, visionParams) == nil
	if clear then
		robot.waypoints = {}
		humanoid:MoveTo(point)
		return
	end
	if time >= robot.nextPathAt then
		robot.nextPathAt = time + AI.pathRefresh
		task.spawn(function()
			local path = PathfindingService:CreatePath({
				AgentRadius = robot.def.size.X / 2,
				AgentHeight = robot.def.size.Y,
				AgentCanJump = false,
			})
			local ok = pcall(function()
				path:ComputeAsync(root.Position, point)
			end)
			if ok and path.Status == Enum.PathStatus.Success then
				local points = {}
				for _, waypoint in path:GetWaypoints() do
					table.insert(points, waypoint.Position)
				end
				robot.waypoints = points
				robot.waypointIndex = 2
			end
		end)
	end
	local nextPoint = robot.waypoints[robot.waypointIndex]
	if nextPoint then
		if (nextPoint - root.Position).Magnitude < 3 then
			robot.waypointIndex += 1
			nextPoint = robot.waypoints[robot.waypointIndex]
		end
		if nextPoint then
			humanoid:MoveTo(nextPoint)
		end
	end
end

local function stop(robot: Robot)
	if robot.stationary then
		return
	end
	if robot.def.flying then
		local hover = robot.fighter.root:FindFirstChild("Hover")
		if hover and hover:IsA("AlignPosition") then
			hover.Position = robot.fighter.root.Position
		end
	else
		robot.fighter.humanoid:MoveTo(robot.fighter.root.Position)
	end
end

local function shoot(robot: Robot, target: Fighter)
	local m = mode()
	local origin = robot.eye.Position
	local damage = (robot.def.rangedDamage or robot.def.damage) * m.robots.damage
	local hit = random:NextNumber() < m.robots.accuracy
	local endpoint = target.root.Position
	if hit then
		CombatService.applyDamage(target, damage, robot.fighter, { sourcePosition = origin })
	else
		endpoint += Vector3.new(
			random:NextNumber(-1, 1) * AI.missSpread,
			random:NextNumber(-0.5, 1) * AI.missSpread,
			random:NextNumber(-1, 1) * AI.missSpread
		)
	end
	ServerNet.fireAll("ShotFired", nil, "robot_" .. robot.def.id, origin, { endpoint })
end

local function attack(robot: Robot, target: Fighter, distance: number, time: number)
	if not RobotBrain.canAttack(robot.brain, time) or time < robot.nextAttackAt then
		return
	end
	local def = robot.def
	local meleeRange = def.meleeRange
	if meleeRange and distance <= meleeRange + 1.5 and (def.attack == "melee" or def.attack == "hybrid") then
		robot.nextAttackAt = time + (def.meleeInterval :: number)
		ServerNet.fireAll("MeleeSwing", nil, "robot_" .. def.id)
		CombatService.meleeHit(robot.fighter, target, def.damage * mode().robots.damage, {})
		return
	end
	if def.attack == "melee" or distance > def.attackRange then
		return
	end
	-- Tir (le Bastion tire en rafales).
	if def.burst then
		if robot.burstLeft <= 0 then
			robot.burstLeft = def.burst
		end
		robot.burstLeft -= 1
		robot.nextAttackAt = time + (if robot.burstLeft <= 0 then 1.2 else def.fireInterval)
	else
		robot.nextAttackAt = time + def.fireInterval
	end
	shoot(robot, target)
end

local function patrolPoint(robot: Robot): Vector3
	local radius = if robot.garrison then AI.garrisonRadius else AI.patrolRadius
	local angle = random:NextNumber(0, math.pi * 2)
	local distance = random:NextNumber(radius * 0.3, radius)
	return robot.home + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

-- Gardiens : rend le robot invisible / intangible (enfoui, projection instable).
local function setHidden(robot: Robot, hidden: boolean, transparency: number)
	local state = robot.partState
	if state == nil then
		local created = {}
		for _, descendant in robot.fighter.character:GetDescendants() do
			if descendant:IsA("BasePart") and descendant ~= robot.fighter.root then
				created[descendant] = { transparency = descendant.Transparency, query = descendant.CanQuery }
			end
		end
		robot.partState = created
		state = created
	end
	robot.fighter.character:SetAttribute("Hidden", hidden)
	for part, original in state :: { [BasePart]: { transparency: number, query: boolean } } do
		if part.Parent then
			part.Transparency = if hidden then math.max(original.transparency, transparency) else original.transparency
			part.CanQuery = if hidden then false else original.query
		end
	end
end

local function nearestTargetDistance(position: Vector3): number
	local best = math.huge
	for _, other in CombatService.allFighters() do
		if (other.kind == "player" or other.kind == "bot") and Fighter.isAlive(other) then
			best = math.min(best, (other.root.Position - position).Magnitude)
		end
	end
	return best
end

--[[
	Comportement spécial des Gardiens, à intervalles réguliers face à une cible :
	- burrow : s'enfouit, puis surgit sous la cible (dégâts de zone) ;
	- phase : devient intangible et se déplace par à-coups.
	Retourne true si le robot est caché (la suite de sa logique est sautée).
]]
local function special(robot: Robot, target: Fighter?, time: number): boolean
	local behavior = robot.behavior
	if behavior ~= "burrow" and behavior ~= "phase" then
		return false
	end
	local params = (Config.Maps.guardianBehaviors :: any)[behavior]
	if robot.hiddenUntil > 0 then
		if time < robot.hiddenUntil then
			return true
		end
		-- Réapparition.
		robot.hiddenUntil = 0
		local fighter = robot.fighter
		local anchor = if target then target.root.Position else fighter.root.Position
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = if behavior == "burrow" then 4 else params.jump
		local spot = groundAt(anchor + Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance)
		fighter.character:PivotTo(CFrame.new(spot + Vector3.new(0, robot.def.size.Y / 2 + 0.2, 0)))
		setHidden(robot, false, 0)
		if behavior == "burrow" then
			for _, other in CombatService.allFighters() do
				if
					other ~= fighter
					and other.kind ~= "robot"
					and Fighter.isAlive(other)
					and (other.root.Position - spot).Magnitude <= params.surfaceRadius
				then
					CombatService.applyDamage(other, params.surfaceDamage * mode().robots.damage, fighter, {
						sourcePosition = spot,
					})
				end
			end
			ServerNet.fireAll("MapEvent", "surface", spot)
		end
		return false
	end
	if target and time >= robot.nextSpecialAt then
		local distance = (target.root.Position - robot.fighter.root.Position).Magnitude
		if behavior == "phase" or distance >= params.minDistance then
			robot.nextSpecialAt = time + params.every
			robot.hiddenUntil = time + params.hidden
			setHidden(robot, true, if behavior == "burrow" then 1 else 0.75)
			stop(robot)
			return true
		end
	end
	return false
end

local function update(robot: Robot, dt: number)
	local fighter = robot.fighter
	if not Fighter.isAlive(fighter) then
		return
	end
	local time = now()
	if CombatService.isStunned(fighter) then
		stop(robot)
		return
	end
	-- Sommeil : aucun joueur à moins de 150 studs.
	if nearestPlayerDistance(fighter.root.Position) > AI.sleepDistance and robot.wave == nil then
		stop(robot)
		return
	end
	-- Exécuteur en cours de fabrication : s'active à l'approche ou s'il est touché.
	local dormant = robot.dormantRadius
	if dormant then
		if nearestTargetDistance(fighter.root.Position) > dormant and robot.brain.state == "patrol" then
			return
		end
		robot.dormantRadius = nil
	end

	local target = RobotBrain.step(robot.brain, {
		now = time,
		dt = dt,
		visible = perceive(robot),
		noise = robot.noise,
		alertedAt = robot.alertedAt,
	}, mode().robots.reactionTime)
	robot.noise = nil
	robot.alertedAt = nil
	local state = robot.brain.state
	if special(robot, if target then target.id :: Fighter else nil, time) then
		return
	end

	if target then
		local targetFighter = target.id :: Fighter
		face(robot, target.position)
		local distance = target.distance
		local def = robot.def
		local closeIn = def.attack == "melee" or (def.attack == "hybrid" and distance < def.attackRange * 0.5)
		if closeIn or distance > def.attackRange * 0.9 then
			moveTo(robot, target.position)
		elseif distance < def.preferredDistance * 0.6 then
			-- Trop près : recul.
			local away = (fighter.root.Position - target.position)
			moveTo(robot, fighter.root.Position + Vector3.new(away.X, 0, away.Z).Unit * 8)
		else
			stop(robot)
		end
		attack(robot, targetFighter, distance, time)
		-- La Mouche alerte les robots proches.
		if def.alertRadius then
			for _, other in robots do
				if
					other ~= robot
					and (other.fighter.root.Position - fighter.root.Position).Magnitude <= def.alertRadius
				then
					other.alertedAt = target.position
				end
			end
		end
		return
	end

	if state == "suspicion" then
		stop(robot)
		if robot.brain.lastKnown then
			face(robot, robot.brain.lastKnown :: Vector3)
		end
	elseif state == "search" then
		local goal = robot.brain.lastKnown or robot.wave
		if goal then
			moveTo(robot, goal)
		end
	else
		-- Patrouille (ou vague : rejoindre l'extraction et la tenir).
		local destination = robot.wave or robot.destination
		if destination == nil or (destination - fighter.root.Position).Magnitude < 4 then
			robot.destination = if robot.wave then robot.wave else patrolPoint(robot)
			destination = robot.destination
		end
		moveTo(robot, destination :: Vector3)
	end
end

--[[
	Fait apparaître un robot. `garrison` : posté dans une zone à risque.
	Les PV sont multipliés selon le mode.
]]
function RobotService.spawn(robotId: string, position: Vector3, garrison: boolean, options: SpawnOptions?): Fighter
	local def = Config.Robots.byId[robotId]
	local opts: SpawnOptions = options or {}
	local override = opts.override
	if override then
		local merged = table.clone(def) :: any
		for key, value in override do
			merged[key] = value
		end
		def = merged
	end
	local ground = groundAt(position)
	local height = if def.flying then 8 else def.size.Y / 2 + 0.2
	local cframe = CFrame.new(ground + Vector3.new(0, height, 0))
		* CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
	local built = RobotFactory.build(robotId, cframe, if override then def else nil)
	local stationary = def.stationary == true or opts.behavior == "anchored"
	if stationary then
		built.root.Anchored = true
	end
	built.model.Parent = robotFolder()
	pcall(function()
		built.root:SetNetworkOwner(nil)
	end)

	local fighter = Fighter.new("robot", nil, built.model, built.humanoid, built.root, {}, Fighter.simpleInventory({}))
	local health = def.health * mode().robots.health
	fighter.maxHealth = health
	fighter.health = health
	fighter.teamId = "axiom"
	fighter.robotId = robotId
	built.humanoid.MaxHealth = health
	built.humanoid.Health = health
	CombatService.register(fighter)

	robots[fighter] = {
		fighter = fighter,
		def = def,
		brain = RobotBrain.new(),
		home = ground,
		garrison = garrison,
		destination = nil,
		waypoints = {},
		waypointIndex = 1,
		nextPathAt = 0,
		nextAttackAt = 0,
		burstLeft = 0,
		nextUpdate = now() + random:NextNumber(0, 1 / AI.updateRate),
		noise = nil,
		alertedAt = nil,
		wave = nil,
		eye = built.eye,
		stationary = stationary,
		behavior = opts.behavior,
		dormantRadius = opts.dormantRadius,
		nextSpecialAt = now() + 4,
		hiddenUntil = 0,
		partState = nil,
	}
	return fighter
end

local function aliveCount(): number
	local count = 0
	for fighter in robots do
		if Fighter.isAlive(fighter) then
			count += 1
		end
	end
	return count
end

-- Point de patrouille : repère RobotSpawn non-garnison, sinon un point de départ de la carte.
local function patrolSpawn(): Vector3
	local markers = {}
	for _, marker in MapService.robotSpawns() do
		if marker.attributes.Garrison ~= true then
			table.insert(markers, marker)
		end
	end
	if #markers == 0 then
		markers = MapService.deploySpawns()
	end
	if #markers == 0 then
		return Vector3.zero
	end
	local marker = markers[random:NextInteger(1, #markers)]
	return marker.position + Vector3.new(random:NextNumber(-12, 12), 0, random:NextNumber(-12, 12))
end

-- Emplacement libre (pas dans un mur ni une étagère) autour d'un point, sinon le point lui-même.
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
local function openSpot(center: Vector3, radius: number, size: Vector3): Vector3
	overlapParams.FilterDescendantsInstances = { robotFolder() }
	for attempt = 1, 8 do
		local offset = if attempt == 1 and radius <= 0
			then Vector3.zero
			else Vector3.new(random:NextNumber(-radius, radius), 0, random:NextNumber(-radius, radius))
		local ground = groundAt(center + offset)
		local box = CFrame.new(ground + Vector3.new(0, size.Y / 2 + 0.6, 0))
		local blocking = Workspace:GetPartBoundsInBox(box, size, overlapParams)
		local solid = false
		for _, part in blocking do
			if part.CanCollide then
				solid = true
				break
			end
		end
		if not solid then
			return ground
		end
	end
	return groundAt(center)
end

export type PopulateOptions = {
	total: number?, -- effectif réduit (arène de test)
	guardian: { robotId: string, behavior: string?, overrides: { [string]: any } }?,
	wakeRadius: number?, -- Exécuteurs dormants (Forge-7)
}

--[[
	Population initiale de la carte (section 10.3) :
	- robots fixes posés sur la carte (repères RobotSpawn avec RobotId :
	  tourelles, Exécuteurs dormants) ;
	- Gardien de la carte dans la zone à risque principale ;
	- 60 % en garnison dans les zones à risque, 40 % en patrouilles.
]]
function RobotService.populate(newModeId: string, options: PopulateOptions?)
	RobotService.clear()
	modeId = newModeId
	visionMultiplier = 1
	local opts: PopulateOptions = options or {}
	local count = opts.total or random:NextInteger(Density.minActive, Density.maxActive)

	-- Robots fixes de la carte.
	for _, marker in MapService.robotSpawns() do
		local robotId = marker.attributes.RobotId
		if type(robotId) == "string" and Config.Robots.byId[robotId] and count > 0 then
			RobotService.spawn(robotId, marker.position, true, {
				dormantRadius = if marker.attributes.Dormant == true then opts.wakeRadius or 18 else nil,
			})
			count -= 1
		end
	end

	local zones = MapService.riskZones()
	local garrisonCount = if #zones > 0 then math.floor(count * Density.garrisonShare + 0.5) else 0

	-- Gardien dans la zone à risque principale.
	for _, zone in zones do
		if zone.attributes.Main == true then
			local guardian = opts.guardian
			if guardian then
				RobotService.spawn(guardian.robotId, zone.position, true, {
					override = guardian.overrides,
					behavior = guardian.behavior,
				})
			else
				RobotService.spawn("warden", zone.position, true)
			end
			garrisonCount -= 1
			break
		end
	end
	local placed = 0
	while placed < garrisonCount and #zones > 0 do
		local zone = zones[(placed % #zones) + 1]
		local radius = zone.attributes.Radius or AI.garrisonRadius
		local robotId = weightedPick(Density.garrison)
		local spot = openSpot(zone.position, radius, Config.Robots.byId[robotId].size)
		RobotService.spawn(robotId, spot + Vector3.new(0, 1, 0), true)
		placed += 1
	end
	local patrols = count - math.max(0, garrisonCount) - (if #zones > 0 then 1 else 0)
	local spawned = 0
	while spawned < patrols do
		local robotId = weightedPick(Density.patrol)
		local def = Config.Robots.byId[robotId]
		local origin = patrolSpawn()
		-- Les Traqueurs chassent en meute de 2 ou 3.
		local pack = if def.packSize then random:NextInteger(def.packSize.min, def.packSize.max) else 1
		for index = 1, math.min(pack, patrols - spawned) do
			RobotService.spawn(robotId, origin + Vector3.new(index * 3, 0, 0), false)
			spawned += 1
		end
	end
end

-- Coupures de courant : la vision des robots est réduite.
function RobotService.setVisionMultiplier(multiplier: number)
	visionMultiplier = math.clamp(multiplier, 0.1, 1)
end

-- Vague d'alerte (12:00) : 6 à 10 robots convergent vers les extractions.
function RobotService.alertWave()
	local wave = Config.Match.alertWave
	local count = math.min(random:NextInteger(wave.minRobots, wave.maxRobots), Density.hardCap - aliveCount())
	local extractions = ExtractionService.openZones()
	if count <= 0 or #extractions == 0 then
		return
	end
	for index = 1, count do
		local fighter = RobotService.spawn(weightedPick(Density.wave), patrolSpawn(), false)
		local robot = robots[fighter]
		robot.wave = extractions[(index % #extractions) + 1]
		robot.brain.state = "search"
		robot.brain.lastKnown = robot.wave
		robot.brain.searchUntil = now() + 120
	end
end

function RobotService.clear()
	for fighter in table.clone(robots) do
		CombatService.unregister(fighter)
		if fighter.character.Parent then
			fighter.character:Destroy()
		end
	end
	table.clear(robots)
	if folder then
		folder:Destroy()
		folder = nil
	end
end

function RobotService.count(): number
	return aliveCount()
end

function RobotService.init()
	-- Bruits : tirs et alarmes.
	local function onNoise(position: Vector3, radius: number)
		for _, robot in robots do
			if (robot.fighter.root.Position - position).Magnitude <= radius then
				robot.noise = position
			end
		end
	end
	CombatService.NoiseMade:Connect(onNoise)
	LootService.NoiseMade:Connect(onNoise)

	-- Un robot touché cible son attaquant.
	CombatService.FighterDamaged:Connect(function(target, attacker)
		local robot = robots[target]
		if robot and attacker and attacker.kind ~= "robot" then
			RobotBrain.onDamaged(robot.brain, attacker, attacker.root.Position, now())
		end
	end)

	-- Destruction : loot au sol, disparition du modèle.
	CombatService.FighterDied:Connect(function(fighter)
		local robot = robots[fighter]
		if robot == nil then
			return
		end
		robots[fighter] = nil
		local position = fighter.root.Position
		local items = LootGenerator.robot(robot.def.id, modeId, random, ItemFactory.create)
		if #items > 0 then
			LootService.dropToGround(position, items)
		end
		task.delay(Config.Combat.death.disintegrateDuration + 0.1, function()
			if fighter.character.Parent then
				fighter.character:Destroy()
			end
		end)
	end)
end

function RobotService.start()
	local interval = 1 / AI.updateRate
	RunService.Heartbeat:Connect(function()
		local time = now()
		for _, robot in robots do
			if time >= robot.nextUpdate then
				robot.nextUpdate = time + interval
				local ok, err = try(update, robot, interval)
				if not ok then
					warn(`[RobotService] IA {robot.def.id} : {err}`)
				end
			end
		end
	end)
end

return RobotService
