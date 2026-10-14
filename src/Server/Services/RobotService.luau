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
	- Combats lisibles : les attaques lourdes sont annoncées (attributs
	  WindupUntil / WindupKind du modèle), le nombre d'attaquants par cible
	  est plafonné (Engagement), aucun robot n'apparaît près d'un joueur.
	- Détecteur du joueur : attributs Alert (soupçon, recherche, combat) et
	  Aggro (UserId du joueur remarqué ou visé), lus par le client.
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
local Engagement = require(Shared.Robots.Engagement)
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
	surfaceAt: Vector3?, -- Gardien enfoui : point d'émergence annoncé
	partState: { [BasePart]: { transparency: number, query: boolean } }?,
	windupUntil: number, -- annonce d'attaque en cours (0 = aucune)
	shownAlert: string?, -- dernières valeurs publiées (attributs du modèle)
	shownAggro: number?,
}

export type SpawnOptions = {
	override: { [string]: any }?, -- valeurs remplaçant celles de la config (Gardien d'une carte)
	behavior: string?,
	dormantRadius: number?,
}

local robots: { [Fighter]: Robot } = {}
local engagement = Engagement.new()
local folder: Folder?
local random = Random.new()
local modeId = "easy"
local visionMultiplier = 1 -- coupures de courant (Noyau Zéro)
local awakeAt = 0 -- début de partie : robots en veille jusqu'à ce moment

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

-- Distance au sol (les grands robots et les Mouches ont leur centre loin du sol :
-- une distance 3D à un point posé au sol ne passerait jamais sous le seuil).
local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
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
	-- Un obstacle touché tout près du but, c'est le but lui-même (le corps de la cible).
	local hit = Workspace:Raycast(root.Position, point - root.Position, visionParams)
	local clear = hit == nil or (hit.Position - point).Magnitude < 4
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
	if nextPoint and flatDistance(nextPoint, root.Position) < 3 then
		robot.waypointIndex += 1
		nextPoint = robot.waypoints[robot.waypointIndex]
	end
	-- Chemin pas encore calculé, épuisé ou introuvable : avancer droit vers le but
	-- plutôt que de rester planté (le chemin est recalculé à intervalle régulier).
	humanoid:MoveTo(nextPoint or point)
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

--[[
	État visible par les clients (détecteur, marqueurs de menace) : attributs du
	modèle, répliqués seulement quand ils changent.
	- Alert : "suspicion" | "search" | "combat" (absent en patrouille) ;
	- Aggro : UserId du joueur remarqué (soupçon) ou pris pour cible (combat).
]]
local function publish(robot: Robot, noticed: Fighter?)
	local character = robot.fighter.character
	local state = robot.brain.state
	local alert: string? = if state == "patrol" then nil else state
	if robot.shownAlert ~= alert then
		robot.shownAlert = alert
		character:SetAttribute("Alert", alert)
	end
	local aggro: number? = if noticed and noticed.player then noticed.player.UserId else nil
	if robot.shownAggro ~= aggro then
		robot.shownAggro = aggro
		character:SetAttribute("Aggro", aggro)
	end
end

-- Annonce d'attaque ("shot" | "melee") visible par les clients, ou sa fin (kind = nil).
-- `radius` : portée du coup de mêlée annoncé (cercle au sol côté client).
local function setWindup(robot: Robot, kind: string?, duration: number, radius: number?)
	local character = robot.fighter.character
	if kind then
		robot.windupUntil = now() + duration
		character:SetAttribute("WindupKind", kind)
		character:SetAttribute("WindupRadius", radius)
		character:SetAttribute("WindupUntil", robot.windupUntil)
	else
		robot.windupUntil = 0
		character:SetAttribute("WindupUntil", nil)
		character:SetAttribute("WindupKind", nil)
	end
end

--[[
	Attaque annoncée : `strike` n'est exécuté qu'à la fin de l'annonce, et
	seulement si le robot est encore en état de frapper (ni détruit, ni
	étourdi, ni caché). Étourdir un robot pendant l'annonce annule donc le coup.
]]
local function announce(robot: Robot, kind: string, duration: number, strike: () -> (), radius: number?)
	setWindup(robot, kind, duration, radius)
	local fighter = robot.fighter
	task.delay(duration, function()
		if robots[fighter] ~= robot then
			return
		end
		setWindup(robot, nil, 0)
		if Fighter.isAlive(fighter) and not CombatService.isStunned(fighter) and robot.hiddenUntil == 0 then
			strike()
		end
	end)
end

-- La cible est-elle visible depuis l'œil du robot ? Sinon : point de l'obstacle.
local function lineOfSight(robot: Robot, target: Fighter): (boolean, Vector3)
	local origin = robot.eye.Position
	local goal = target.root.Position
	visionParams.FilterDescendantsInstances = { robotFolder(), target.character }
	local hit = Workspace:Raycast(origin, goal - origin, visionParams)
	if hit then
		return false, hit.Position
	end
	return not blockedBySmoke(origin, goal), goal
end

--[[
	Tir d'un robot. `announced` : tir chargé annoncé à l'avance ; il est perdu
	si la cible s'est mise à couvert ou a quitté la portée pendant l'annonce.
]]
local function shoot(robot: Robot, target: Fighter, announced: boolean)
	local m = mode()
	local def = robot.def
	local origin = robot.eye.Position
	local endpoint = target.root.Position
	local distance = (endpoint - origin).Magnitude
	local visible, obstacle = true, endpoint
	if announced then
		visible, obstacle = lineOfSight(robot, target)
		if distance > def.attackRange * 1.15 then
			visible = false
		end
	end
	local speed = target.root.AssemblyLinearVelocity.Magnitude
	local chance = RobotBrain.hitChance(m.robots.accuracy, distance, def.attackRange, speed)
	if not visible then
		endpoint = obstacle
	elseif random:NextNumber() < chance then
		local damage = (def.rangedDamage or def.damage) * m.robots.damage
		CombatService.rangedHit(target, damage, robot.fighter, { sourcePosition = origin })
	else
		endpoint += Vector3.new(
			random:NextNumber(-1, 1) * AI.missSpread,
			random:NextNumber(-0.5, 1) * AI.missSpread,
			random:NextNumber(-1, 1) * AI.missSpread
		)
	end
	ServerNet.fireAll("ShotFired", nil, "robot_" .. def.id, origin, { endpoint })
end

local function attack(robot: Robot, target: Fighter, distance: number, time: number)
	if not RobotBrain.canAttack(robot.brain, time) or time < robot.nextAttackAt or time < robot.windupUntil then
		return
	end
	local def = robot.def
	local m = mode().robots
	local meleeRange: number? = def.meleeRange
	local inMelee = meleeRange ~= nil
		and distance <= meleeRange + 1.5
		and (def.attack == "melee" or def.attack == "hybrid")
	if not inMelee and (def.attack == "melee" or distance > def.attackRange) then
		return
	end
	-- Tour d'attaque : pas plus de `maxAttackers` robots à la fois sur la même cible.
	if
		not def.guardian
		and not Engagement.request(engagement, target, robot, time, m.maxAttackers, AI.engagementHold)
	then
		return
	end

	if inMelee then
		local windup: number = def.meleeWindup or 0
		robot.nextAttackAt = time + windup + (def.meleeInterval :: number)
		ServerNet.fireAll("MeleeSwing", nil, "robot_" .. def.id)
		local reach = (meleeRange :: number) + 2.5
		local function strike()
			-- Coup esquivé : la cible est sortie de portée pendant l'annonce.
			if Fighter.isAlive(target) and (target.root.Position - robot.fighter.root.Position).Magnitude <= reach then
				CombatService.meleeHit(robot.fighter, target, def.damage * m.damage, {})
			end
		end
		if windup > 0 then
			announce(robot, "melee", windup, strike, reach)
		else
			strike()
		end
		return
	end

	local windup: number = def.windup or 0
	-- Rafales (Bastion) : mise en rotation annoncée, puis les tirs, puis une pause.
	if def.burst then
		if robot.burstLeft <= 0 then
			robot.burstLeft = def.burst
			if windup > 0 then
				robot.nextAttackAt = time + windup
				announce(robot, "shot", windup, function() end)
				return
			end
		end
		robot.burstLeft -= 1
		robot.nextAttackAt = time + (if robot.burstLeft <= 0 then def.burstPause or 1.2 else def.fireInterval)
		shoot(robot, target, false)
		return
	end
	robot.nextAttackAt = time + windup + def.fireInterval
	if windup > 0 then
		announce(robot, "shot", windup, function()
			if Fighter.isAlive(target) then
				shoot(robot, target, true)
			end
		end)
	else
		shoot(robot, target, false)
	end
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
		local fighter = robot.fighter
		if time < robot.hiddenUntil then
			-- Enfoui : le point d'émergence est figé et annoncé (cercle rouge au sol)
			-- avant le surgissement, pour laisser le temps de s'en écarter.
			if behavior == "burrow" and robot.surfaceAt == nil and time >= robot.hiddenUntil - params.warning then
				local anchor = if target then target.root.Position else fighter.root.Position
				local angle = random:NextNumber(0, math.pi * 2)
				local spot = groundAt(anchor + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 3)
				robot.surfaceAt = spot
				ServerNet.fireAll("MapEvent", "surfaceWarning", spot, params.surfaceRadius, params.warning)
			end
			return true
		end
		-- Réapparition.
		robot.hiddenUntil = 0
		local announced = robot.surfaceAt
		robot.surfaceAt = nil
		local spot: Vector3
		if announced then
			spot = announced
		else
			-- Projection : réapparaît à distance de sa cible, jamais à son contact.
			local anchor = if target then target.root.Position else fighter.root.Position
			local angle = random:NextNumber(0, math.pi * 2)
			local distance = if behavior == "burrow" then 3 else params.jump
			spot = groundAt(anchor + Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance)
		end
		fighter.character:PivotTo(CFrame.new(spot + Vector3.new(0, robot.def.size.Y / 2 + 0.2, 0)))
		setHidden(robot, false, 0)
		-- Jamais de coup dans l'instant qui suit la réapparition.
		RobotBrain.delayAttack(robot.brain, time, AI.reappearDelay)
		robot.nextAttackAt = math.max(robot.nextAttackAt, time + AI.reappearDelay)
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
		Engagement.release(engagement, robot)
		stop(robot)
		return
	end
	-- Sommeil : aucun joueur à moins de 150 studs.
	if nearestPlayerDistance(fighter.root.Position) > AI.sleepDistance and robot.wave == nil then
		stop(robot)
		return
	end
	-- Veille de début de partie : immobile et aveugle, sauf s'il a été touché.
	if time < awakeAt and robot.brain.state == "patrol" and robot.wave == nil then
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

	local visible = perceive(robot)
	local target = RobotBrain.step(robot.brain, {
		now = time,
		dt = dt,
		visible = visible,
		noise = robot.noise,
		alertedAt = robot.alertedAt,
	}, mode().robots.reactionTime)
	robot.noise = nil
	robot.alertedAt = nil
	local state = robot.brain.state
	-- Détecteur : la cible en combat, ou le plus proche que le robot est en train de remarquer.
	local noticed: Fighter? = if target then target.id :: Fighter else nil
	if noticed == nil and state == "suspicion" then
		local nearest = math.huge
		for _, seen in visible do
			if seen.distance < nearest then
				nearest = seen.distance
				noticed = seen.id :: Fighter
			end
		end
	end
	publish(robot, noticed)
	if special(robot, if target then target.id :: Fighter else nil, time) then
		return
	end

	if target then
		local targetFighter = target.id :: Fighter
		face(robot, target.position)
		local distance = target.distance
		local def = robot.def
		local closeIn = def.attack == "melee" or (def.attack == "hybrid" and distance < def.attackRange * 0.5)
		-- Attaque annoncée : le robot s'immobilise (on peut s'écarter ou se mettre à couvert).
		local windingUp = time < robot.windupUntil
		if not windingUp and (closeIn or distance > def.attackRange * 0.9) then
			moveTo(robot, target.position)
		elseif not windingUp and distance < def.preferredDistance * 0.6 then
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
		if destination == nil or flatDistance(destination, fighter.root.Position) < 4 then
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
	built.model:SetAttribute("RobotId", robotId)
	if def.guardian then
		built.model:SetAttribute("Guardian", true)
	end
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
		surfaceAt = nil,
		partState = nil,
		windupUntil = 0,
		shownAlert = nil,
		shownAggro = nil,
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

-- Points de départ des joueurs : aucun robot n'apparaît à côté en début de partie.
local function playerSpawnPoints(): { Vector3 }
	local points = {}
	for _, marker in MapService.deploySpawns() do
		table.insert(points, marker.position)
	end
	for _, marker in MapService.soloSpawns() do
		table.insert(points, marker.position)
	end
	return points
end

-- Joueurs et mercenaires vivants (vague d'alerte : les renforts arrivent de loin).
local function livePositions(): { Vector3 }
	local points = {}
	for _, other in CombatService.allFighters() do
		if (other.kind == "player" or other.kind == "bot") and Fighter.isAlive(other) then
			table.insert(points, other.root.Position)
		end
	end
	return points
end

-- Distance au sol jusqu'au plus proche des points à éviter.
local function clearance(position: Vector3, avoid: { Vector3 }): number
	local best = math.huge
	for _, point in avoid do
		best = math.min(best, flatDistance(point, position))
	end
	return best
end

--[[
	Point de patrouille : repère RobotSpawn non-garnison (sinon un point de
	départ de la carte), à `minDistance` au moins des points à éviter. Si
	aucun essai ne convient, le plus éloigné des essais est retenu.
]]
local function patrolSpawn(avoid: { Vector3 }, minDistance: number): Vector3
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
	local best: Vector3 = markers[1].position
	local bestGap = -1
	for _ = 1, 16 do
		local marker = markers[random:NextInteger(1, #markers)]
		local candidate = marker.position + Vector3.new(random:NextNumber(-12, 12), 0, random:NextNumber(-12, 12))
		local gap = clearance(candidate, avoid)
		if gap >= minDistance then
			return candidate
		end
		if gap > bestGap then
			best, bestGap = candidate, gap
		end
	end
	return best
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
	awakeAt = now() + AI.wakeDelay
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

	local avoid = playerSpawnPoints()
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
		local size = Config.Robots.byId[robotId].size
		local spot = openSpot(zone.position, radius, size)
		-- Jamais collé à un point de départ : quelques autres essais dans la zone.
		for _ = 1, 4 do
			if clearance(spot, avoid) >= Density.spawnClearance then
				break
			end
			spot = openSpot(zone.position, radius, size)
		end
		RobotService.spawn(robotId, spot + Vector3.new(0, 1, 0), true)
		placed += 1
	end
	local patrols = count - math.max(0, garrisonCount) - (if #zones > 0 then 1 else 0)
	local spawned = 0
	while spawned < patrols do
		local robotId = weightedPick(Density.patrol)
		local def = Config.Robots.byId[robotId]
		local origin = patrolSpawn(avoid, Density.spawnClearance)
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
	-- Les renforts arrivent de loin : jamais au contact d'un joueur.
	local avoid = livePositions()
	for index = 1, count do
		local origin = patrolSpawn(avoid, Density.waveClearance)
		local fighter = RobotService.spawn(weightedPick(Density.wave), origin, false)
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
	table.clear(engagement)
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
		Engagement.forget(engagement, fighter)
		local robot = robots[fighter]
		if robot == nil then
			return
		end
		robots[fighter] = nil
		Engagement.release(engagement, robot)
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
