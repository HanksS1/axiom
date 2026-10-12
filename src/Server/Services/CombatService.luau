--!strict
--[[
	CombatService : autorité serveur sur le combat (section 6).

	- Registre des combattants (joueurs, mannequins, plus tard robots).
	- Tirs : validation (cadence, munitions, position, portée, ligne de vue)
	  puis calcul des dégâts par le serveur uniquement.
	- Mêlée, parade (garde, parade parfaite, garde brisée), étourdissement.
	- Recharge, changement d'arme, postures et vitesses.
	- PV / bouclier, mort (désintégration côté client).

	Le client n'envoie que des intentions ; toute incohérence est rejetée
	et signalée à ServerNet (journal + expulsion au-delà d'un seuil).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Damage = require(Shared.Combat.Damage)
local InventoryLogic = require(Shared.Items.InventoryLogic)
local Guard = require(Shared.Util.Guard)
local Movement = require(Shared.Combat.Movement)
local Signal = require(Shared.Util.Signal)
local WeaponLogic = require(Shared.Combat.WeaponLogic)

local Fighter = require(script.Parent.Parent.Combat.Fighter)
local HitValidator = require(script.Parent.Parent.Combat.HitValidator)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)

type Fighter = Fighter.Fighter

local Combat = Config.Combat

local CombatService = {}

-- (victime, tueur?) : un combattant vient de mourir.
CombatService.FighterDied = Signal.new() :: Signal.Signal<Fighter, Fighter?>
-- (victime, attaquant?, dégâts) : un combattant a subi des dégâts.
CombatService.FighterDamaged = Signal.new() :: Signal.Signal<Fighter, Fighter?, number>
-- (position, rayon) : bruit audible par les robots (tirs).
CombatService.NoiseMade = Signal.new() :: Signal.Signal<Vector3, number>
-- (combattant) : le joueur quitte le serveur (avant la destruction du personnage).
CombatService.PlayerLeaving = Signal.new() :: Signal.Signal<Fighter>
-- (combattant) : posture / vitesse modifiée (pour le contrôle de mouvement).
CombatService.MovementChanged = Signal.new() :: Signal.Signal<Fighter>

local fighters: { [Model]: Fighter } = {}
local byPlayer: { [Player]: Fighter } = {}
local ownerStateQueued: { [Fighter]: boolean } = {}

-- Gestion de la mort (remplaçable par le déroulé de partie en P3).
-- Par défaut (arène, stand de tir) : réapparition après `respawnTime`.
local deathHandler: ((fighter: Fighter, killer: Fighter?) -> ())? = nil

local worldRayParams = RaycastParams.new()
worldRayParams.FilterType = Enum.RaycastFilterType.Exclude
worldRayParams.IgnoreWater = true

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- Exclut tous les personnages des rayons « monde » (ligne de vue).
local function refreshRayFilter()
	-- Les personnages ne bloquent pas la ligne de vue ; les objets (mur
	-- déployable, drone, orbe) la bloquent.
	local excluded = {}
	for character, fighter in fighters do
		if fighter.kind ~= "object" then
			table.insert(excluded, character)
		end
	end
	worldRayParams.FilterDescendantsInstances = excluded
end

local function castWorldRay(origin: Vector3, displacement: Vector3): number?
	local result = Workspace:Raycast(origin, displacement, worldRayParams)
	if result == nil then
		return nil
	end
	return result.Distance
end

-- Vue publique (répliquée à tous) : attributs du personnage.
local function publishPublic(fighter: Fighter)
	local character = fighter.character
	character:SetAttribute("Health", fighter.health)
	character:SetAttribute("Shield", fighter.shield)
	character:SetAttribute("MaxShield", fighter.maxShield)
	character:SetAttribute("Stance", fighter.move.stance)
	character:SetAttribute("Parrying", fighter.move.parrying)
	character:SetAttribute("Stunned", fighter.move.stunned)
	character:SetAttribute("Dead", fighter.dead)
	character:SetAttribute("Using", fighter.usingItemId ~= nil)
	local weapon = if fighter.activeSlot == "ranged" then fighter.ranged else fighter.melee
	character:SetAttribute("WeaponId", if weapon then weapon.item.itemId else nil)
	character:SetAttribute("WeaponCondition", if weapon then weapon.item.condition else nil)
	if fighter.humanoid.Parent ~= nil then
		fighter.humanoid.Health = math.max(if fighter.dead then 0 else 0.01, fighter.health)
	end
end

local function buildOwnerState(fighter: Fighter): { [string]: any }
	local state: { [string]: any } = {
		serverTime = now(),
		activeSlot = fighter.activeSlot,
	}
	local ranged = fighter.ranged
	if ranged then
		local def = ranged.def
		WeaponLogic.updateHeat(ranged.state, now())
		state.ranged = {
			itemId = ranged.item.itemId,
			condition = ranged.item.condition,
			ammo = ranged.state.ammo,
			capacity = def.capacity,
			reserve = fighter.inventory:countCells(def.cell),
			heat = ranged.state.heat,
			overheatedUntil = ranged.state.overheatedUntil,
			reloadEndsAt = ranged.state.reloadEndsAt,
			lastFireAt = ranged.state.lastFireAt,
		}
	end
	local melee = fighter.melee
	if melee then
		state.melee = { itemId = melee.item.itemId, condition = melee.item.condition }
	end
	if fighter.usingItemId then
		state.using = { itemId = fighter.usingItemId, endsAt = fighter.usingUntil }
	end
	if fighter.boostUntil > state.serverTime then
		state.boostUntil = fighter.boostUntil
	end
	return state
end

-- État privé (munitions, chaleur…) : envoyé au seul propriétaire, regroupé par frame.
local function queueOwnerState(fighter: Fighter)
	local player = fighter.player
	if player == nil or ownerStateQueued[fighter] then
		return
	end
	ownerStateQueued[fighter] = true
	task.defer(function()
		ownerStateQueued[fighter] = nil
		if player.Parent == Players and byPlayer[player] == fighter then
			ServerNet.fire("CombatState", player, buildOwnerState(fighter))
		end
	end)
end

-- Applique la vitesse et le saut correspondant à l'état de mouvement.
local function applyMovement(fighter: Fighter)
	Fighter.refresh(fighter, now())
	local humanoid = fighter.humanoid
	if humanoid.Parent == nil then
		return
	end
	if fighter.dead then
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
	elseif fighter.kind == "player" or fighter.kind == "bot" then
		-- Les robots ont leur propre vitesse (RobotService).
		humanoid.WalkSpeed = Movement.walkSpeed(fighter.move)
		humanoid.JumpHeight = Movement.jumpHeight(fighter.move)
	end
	publishPublic(fighter)
	CombatService.MovementChanged:Fire(fighter)
end

-- Programme un rafraîchissement du mouvement à la fin d'un effet temporaire.
local function refreshAt(fighter: Fighter, time: number)
	task.delay(math.max(0, time - now()) + 0.02, function()
		if fighters[fighter.character] == fighter then
			applyMovement(fighter)
		end
	end)
end

local function stun(fighter: Fighter, duration: number)
	local until_ = now() + duration
	fighter.stunnedUntil = math.max(fighter.stunnedUntil, until_)
	fighter.move.parrying = false
	fighter.move.sprinting = false
	applyMovement(fighter)
	refreshAt(fighter, fighter.stunnedUntil)
end

local function endParry(fighter: Fighter, time: number)
	if not fighter.move.parrying then
		return
	end
	fighter.move.parrying = false
	-- Une garde qui n'a produit aucune parade parfaite impose un délai.
	if not fighter.parryPerfected then
		fighter.parryCooldownUntil = time + Combat.parry.failedPerfectCooldown
	end
end

local function kill(fighter: Fighter, killer: Fighter?)
	if fighter.dead then
		return
	end
	fighter.dead = true
	fighter.health = 0
	fighter.usingToken += 1
	fighter.usingItemId = nil
	fighter.move.parrying = false
	fighter.move.sprinting = false
	if fighter.ranged then
		WeaponLogic.cancelReload(fighter.ranged.state)
	end
	fighter.root.Anchored = true
	applyMovement(fighter)
	queueOwnerState(fighter)
	CombatService.FighterDied:Fire(fighter, killer)

	-- Objet détruit (mur, drone, orbe) : il disparaît après l'effet.
	if fighter.kind == "object" then
		task.delay(Combat.death.disintegrateDuration, function()
			if fighter.character.Parent then
				fighter.character:Destroy()
			end
		end)
		return
	end

	local handler = deathHandler
	if handler then
		handler(fighter, killer)
		return
	end
	-- Comportement par défaut : la désintégration se joue côté client,
	-- puis le personnage meurt (réapparition automatique de Roblox).
	task.delay(Combat.death.disintegrateDuration, function()
		if fighter.humanoid.Parent ~= nil then
			fighter.humanoid.Health = 0
		end
	end)
end

-- Mouvement d'un mercenaire IA (décidé par le serveur, sans horodatage client).
function CombatService.setBotMovement(fighter: Fighter, sprinting: boolean)
	if fighter.kind ~= "bot" or not Fighter.isAlive(fighter) then
		return
	end
	local time = now()
	Fighter.refresh(fighter, time)
	local move = fighter.move
	local wantsSprint = sprinting and Movement.canSprint(move)
	if wantsSprint == move.sprinting then
		return
	end
	if move.sprinting then
		fighter.sprintEndedAt = time
	end
	move.sprinting = wantsSprint
	applyMovement(fighter)
end

-- Filtre des dégâts (zones sans combat) : false = dégâts annulés.
local damageFilter: ((attacker: Fighter?, target: Fighter) -> boolean)? = nil

function CombatService.setDamageFilter(filter: ((attacker: Fighter?, target: Fighter) -> boolean)?)
	damageFilter = filter
end

export type DamageOptions = {
	shieldIgnore: number?,
	sourcePosition: Vector3?,
	isHead: boolean?,
}

--[[
	Applique des dégâts à un combattant (seul point d'entrée des dégâts).
	Retourne les dégâts réellement infligés et si la cible est morte.
]]
function CombatService.applyDamage(
	target: Fighter,
	amount: number,
	attacker: Fighter?,
	options: DamageOptions?
): (number, boolean)
	if not Fighter.isAlive(target) or amount <= 0 then
		return 0, false
	end
	-- Pas de tir ami entre coéquipiers.
	if attacker and attacker ~= target and Fighter.sameTeam(attacker, target) then
		return 0, false
	end
	-- Zones sans combat (Terminus).
	local filter = damageFilter
	if filter and not filter(attacker, target) then
		return 0, false
	end
	local opts: DamageOptions = options or {}
	local result = Damage.apply(target.health, target.shield, amount, opts.shieldIgnore)
	target.health = result.health
	target.shield = result.shield
	target.lastAttacker = attacker
	local dealt = result.healthDamage + result.shieldDamage
	publishPublic(target)
	CombatService.FighterDamaged:Fire(target, attacker, dealt)

	if target.player and opts.sourcePosition then
		ServerNet.fire("DamageTaken", target.player, opts.sourcePosition, dealt)
	end
	if target.health <= 0 then
		kill(target, attacker)
		return dealt, true
	end
	return dealt, false
end

-- Soin / recharge de bouclier (consommables, réanimation…).
function CombatService.heal(target: Fighter, health: number, shield: number)
	if not Fighter.isAlive(target) then
		return
	end
	target.health = math.min(target.maxHealth, target.health + math.max(0, health))
	target.shield = math.min(target.maxShield, target.shield + math.max(0, shield))
	publishPublic(target)
end

--[[
	Utilisation d'un consommable du sac (section 8.6). Pendant le temps
	d'utilisation, le joueur est ralenti et ne peut ni tirer, ni frapper, ni
	parer ; l'effet s'applique à la fin (annulé en cas de mort).
	Retourne (succès, raison) : "dead", "busy", "missing", "useless".
]]
function CombatService.useConsumable(fighter: Fighter, itemId: string): (boolean, string?)
	local bag = fighter.bag
	if bag == nil or not Fighter.isAlive(fighter) then
		return false, "dead"
	end
	local time = now()
	Fighter.refresh(fighter, time)
	if fighter.move.stunned or fighter.usingItemId ~= nil then
		return false, "busy"
	end
	local def = Config.Equipment.consumables[itemId]
	if def == nil or InventoryLogic.count(bag, itemId) <= 0 then
		return false, "missing"
	end
	local effect = def.effect
	if effect.heal and fighter.health >= fighter.maxHealth then
		return false, "useless"
	end
	if effect.shield and (fighter.maxShield <= 0 or fighter.shield >= fighter.maxShield) then
		return false, "useless"
	end
	if effect.bonusUp and fighter.exoUsed then
		return false, "useless"
	end

	local function apply()
		if not Fighter.isAlive(fighter) or fighter.bag ~= bag then
			return
		end
		if InventoryLogic.consume(bag, itemId, 1) < 1 then
			return
		end
		if effect.heal or effect.shield then
			CombatService.heal(fighter, effect.heal or 0, effect.shield or 0)
		end
		if effect.speedMultiplier then
			fighter.boostMultiplier = effect.speedMultiplier
			fighter.boostUntil = now() + (effect.duration or 0)
			refreshAt(fighter, fighter.boostUntil)
		end
		if effect.bonusUp then
			fighter.exoUsed = true
			bag.bonusUp += effect.bonusUp
		end
		if fighter.onInventoryChanged then
			fighter.onInventoryChanged()
		end
		applyMovement(fighter)
		queueOwnerState(fighter)
	end

	if def.useTime <= 0 then
		apply()
		return true, nil
	end
	fighter.usingToken += 1
	local token = fighter.usingToken
	fighter.usingItemId = itemId
	fighter.usingUntil = time + def.useTime
	fighter.move.sprinting = false
	endParry(fighter, time)
	applyMovement(fighter)
	queueOwnerState(fighter)
	task.delay(def.useTime, function()
		if fighter.usingToken ~= token then
			return
		end
		fighter.usingItemId = nil
		apply()
		applyMovement(fighter)
		queueOwnerState(fighter)
	end)
	return true, nil
end

export type MeleeOptions = {
	breaksParry: boolean?,
	parryBreakStun: number?,
	shieldIgnore: number?,
}

--[[
	Coup de mêlée d'un combattant (joueur, robot, mercenaire IA) sur un autre :
	résolution de la parade (6.8), étourdissements, puis dégâts.
	Retourne (dégâts infligés, cible tuée).
]]
function CombatService.meleeHit(
	attacker: Fighter,
	target: Fighter,
	amount: number,
	options: MeleeOptions?
): (number, boolean)
	local opts: MeleeOptions = options or {}
	local time = now()
	Fighter.refresh(target, time)
	local outcome: Damage.ParryOutcome = Damage.resolveParry({
		parrying = target.move.parrying,
		parryStartedAt = target.parryStartedAt,
		now = time,
		frontal = Damage.isFrontal(target.root.CFrame.LookVector, target.root.Position, attacker.root.Position),
		breaksParry = opts.breaksParry == true,
	})
	if outcome == "perfect" then
		target.parryPerfected = true
		stun(attacker, Combat.parry.perfectStun)
		if target.player then
			ServerNet.fire("ParryResult", target.player, "perfect")
		end
		if attacker.player then
			ServerNet.fire("ParryResult", attacker.player, "parried")
		end
		return 0, false
	elseif outcome == "broken" then
		endParry(target, time)
		stun(target, opts.parryBreakStun or 1)
		if target.player then
			ServerNet.fire("ParryResult", target.player, "broken")
		end
	end
	return CombatService.applyDamage(target, amount * Damage.parryMultiplier(outcome), attacker, {
		shieldIgnore = opts.shieldIgnore,
		sourcePosition = attacker.root.Position,
	})
end

-- Le combattant est-il étourdi (robots : aucune action pendant l'étourdissement) ?
function CombatService.isStunned(fighter: Fighter): boolean
	return now() < fighter.stunnedUntil
end

-- Registre ------------------------------------------------------------------

function CombatService.register(fighter: Fighter)
	fighters[fighter.character] = fighter
	if fighter.player then
		byPlayer[fighter.player] = fighter
	end
	refreshRayFilter()
	applyMovement(fighter)
	queueOwnerState(fighter)
	-- Marque le modèle pour les clients (effets, HUD des cibles).
	CollectionService:AddTag(fighter.character, "Fighter")
	fighter.character:SetAttribute("FighterKind", fighter.kind)

	fighter.character.Destroying:Connect(function()
		CombatService.unregister(fighter)
	end)
end

function CombatService.unregister(fighter: Fighter)
	if fighters[fighter.character] == fighter then
		fighters[fighter.character] = nil
		refreshRayFilter()
	end
	local player = fighter.player
	if player and byPlayer[player] == fighter then
		byPlayer[player] = nil
	end
	ownerStateQueued[fighter] = nil
end

function CombatService.getFighter(player: Player): Fighter?
	return byPlayer[player]
end

-- Tous les combattants enregistrés (copie : sûre à parcourir).
function CombatService.allFighters(): { Fighter }
	local list = {}
	for _, fighter in fighters do
		table.insert(list, fighter)
	end
	return list
end

-- Fixe les PV (réanimation à 50 PV…).
function CombatService.setHealth(fighter: Fighter, health: number)
	if Fighter.isAlive(fighter) then
		fighter.health = math.clamp(health, 1, fighter.maxHealth)
		publishPublic(fighter)
	end
end

-- Tue un combattant sans attaquant (Purge, mort instantanée de l'environnement).
function CombatService.kill(fighter: Fighter)
	if Fighter.isAlive(fighter) then
		kill(fighter, nil)
	end
end

function CombatService.getFighterByCharacter(character: Model): Fighter?
	return fighters[character]
end

-- Combattant vivant auquel appartient une pièce (nil sinon).
function CombatService.findFighterByPart(part: Instance): Fighter?
	local current: Instance? = part
	while current ~= nil and current ~= Workspace do
		if current:IsA("Model") then
			local fighter = fighters[current :: Model]
			if fighter then
				return if Fighter.isAlive(fighter) then fighter else nil
			end
		end
		current = current.Parent
	end
	return nil
end

function CombatService.setDeathHandler(handler: ((fighter: Fighter, killer: Fighter?) -> ())?)
	deathHandler = handler
end

-- L'équipement du sac a changé (ramassage, échange, objet jeté).
function CombatService.equipmentChanged(fighter: Fighter)
	Fighter.syncEquipment(fighter)
	applyMovement(fighter)
	queueOwnerState(fighter)
end

function CombatService.publish(fighter: Fighter)
	publishPublic(fighter)
	queueOwnerState(fighter)
end

-- Gestionnaires des intentions client ----------------------------------------

local function headPosition(fighter: Fighter): Vector3
	local head = fighter.character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end
	return fighter.root.Position + Vector3.new(0, 1.5, 0)
end

local function finishReloadIfDue(fighter: Fighter, time: number)
	local ranged = fighter.ranged
	if ranged and ranged.state.reloadEndsAt ~= nil and time >= ranged.state.reloadEndsAt then
		local def = ranged.def
		local used = WeaponLogic.finishReload(def, ranged.state, time, fighter.inventory:countCells(def.cell))
		fighter.inventory:takeCells(def.cell, used)
		queueOwnerState(fighter)
	end
end

local shotValidator = Guard.tuple(Guard.struct({
	t = Guard.number(0),
	origin = Guard.vector3(100_000),
	direction = Guard.unitVector(0.05),
	hits = Guard.array(
		Guard.struct({
			part = Guard.instanceOf("BasePart"),
			position = Guard.vector3(100_000),
		}),
		24
	),
}))

local function onFireWeapon(player: Player, shot: HitValidator.Shot)
	local fighter = byPlayer[player]
	if fighter == nil or not Fighter.isAlive(fighter) then
		return
	end
	local ranged = fighter.ranged
	if fighter.activeSlot ~= "ranged" or ranged == nil then
		return -- changement d'arme en cours de route : ignoré
	end
	local time = now()
	Fighter.refresh(fighter, time)
	if fighter.move.stunned or fighter.usingItemId ~= nil then
		return
	end
	if shot.t < fighter.lastShotTime then
		ServerNet.flag(player, "FireWeapon", "horodatage antérieur au tir précédent")
		return
	end
	if fighter.move.sprinting then
		return
	end
	local V = Combat.validation
	if shot.t - fighter.sprintEndedAt < Combat.movement.sprintToFireDelay - V.sprintToFireTolerance then
		ServerNet.flag(player, "FireWeapon", "tir trop tôt après un sprint")
		return
	end

	local def = ranged.def
	local state = ranged.state
	finishReloadIfDue(fighter, shot.t)
	local cells = fighter.inventory:countCells(def.cell)
	local canFire, block = WeaponLogic.canFire(def, state, shot.t, cells, V.fireRateTolerance)
	if not canFire then
		if block == "cooldown" then
			ServerNet.flag(player, "FireWeapon", "cadence de tir dépassée")
		end
		-- Désynchronisation (recharge, chargeur vide…) : on renvoie l'état réel.
		queueOwnerState(fighter)
		return
	end

	local fired = WeaponLogic.fire(def, state, shot.t)
	fighter.lastShotTime = shot.t
	if fired.cellsConsumed > 0 then
		fighter.inventory:takeCells(def.cell, fired.cellsConsumed)
	end

	local verdict = HitValidator.validate(shot, {
		now = time,
		shooterHead = headPosition(fighter),
		effectiveRange = def.effectiveRange,
		maxProjectiles = fired.projectiles,
		findTarget = CombatService.findFighterByPart,
		shooter = fighter,
		castRay = castWorldRay,
	})
	if not verdict.ok then
		ServerNet.flag(player, "FireWeapon", verdict.reason or "tir invalide")
		queueOwnerState(fighter)
		return
	end

	-- Le tir s'entend (les robots dans le rayon viennent voir).
	CombatService.NoiseMade:Fire(shot.origin, def.noiseRadius)

	-- Dégâts regroupés par cible (plombs d'un fusil à pompe).
	local condition = ranged.item.condition :: number
	local totals: { [Fighter]: { damage: number, head: boolean } } = {}
	for _, hit in verdict.hits do
		local target = hit.target :: Fighter
		local amount = Damage.ranged({
			def = def,
			condition = condition,
			distance = hit.distance,
			isHead = hit.isHead,
			helmet = target.helmet,
			targetKind = target.kind,
		})
		-- Point faible d'un robot (dos du Bastion).
		if target.kind == "robot" and hit.part.Name == "WeakSpot" and target.robotId then
			local robot = Config.Robots.byId[target.robotId]
			amount *= if robot and robot.weakSpotMultiplier then robot.weakSpotMultiplier else 1
		end
		local entry = totals[target]
		if entry == nil then
			entry = { damage = 0, head = false }
			totals[target] = entry
		end
		entry.damage += amount
		entry.head = entry.head or (hit.isHead and def.headshots)
	end

	local anyHit, anyHead, anyKill = false, false, false
	for target, entry in totals do
		local dealt, killed = CombatService.applyDamage(target, entry.damage, fighter, {
			sourcePosition = shot.origin,
			isHead = entry.head,
		})
		if def.slowOnHit and target.kind ~= "robot" then
			target.slowMultiplier = def.slowOnHit.multiplier
			target.slowUntil = time + def.slowOnHit.duration
			applyMovement(target)
			refreshAt(target, target.slowUntil)
		end
		anyHit = anyHit or dealt > 0
		anyHead = anyHead or entry.head
		anyKill = anyKill or killed
	end
	if anyHit then
		ServerNet.fire("HitConfirm", player, anyHead, anyKill)
	end

	-- Tracés pour les autres joueurs (non fiable : purement visuel).
	local endpoints = {}
	for _, claim in shot.hits do
		table.insert(endpoints, claim.position)
	end
	if #endpoints == 0 then
		table.insert(endpoints, shot.origin + shot.direction * Damage.maxRange(def.effectiveRange))
	end
	ServerNet.fireAllExcept("ShotFired", player, player, ranged.item.itemId, shot.origin, endpoints)
	queueOwnerState(fighter)
end

local function onReload(player: Player)
	local fighter = byPlayer[player]
	if fighter == nil or not Fighter.isAlive(fighter) then
		return
	end
	local ranged = fighter.ranged
	if ranged == nil or fighter.activeSlot ~= "ranged" then
		return
	end
	local def = ranged.def
	if not WeaponLogic.canReload(def, ranged.state, fighter.inventory:countCells(def.cell)) then
		queueOwnerState(fighter)
		return
	end
	local time = now()
	WeaponLogic.startReload(def, ranged.state, time)
	queueOwnerState(fighter)
	local endsAt = ranged.state.reloadEndsAt :: number
	task.delay(endsAt - time + 0.02, function()
		if fighter.ranged == ranged and ranged.state.reloadEndsAt == endsAt then
			finishReloadIfDue(fighter, now())
		end
	end)
end

local function onSwitchWeapon(player: Player, slot: Fighter.WeaponSlot)
	local fighter = byPlayer[player]
	if fighter == nil or not Fighter.isAlive(fighter) or fighter.activeSlot == slot then
		return
	end
	if (slot == "ranged" and fighter.ranged == nil) or (slot == "melee" and fighter.melee == nil) then
		return
	end
	fighter.activeSlot = slot
	if fighter.ranged then
		WeaponLogic.cancelReload(fighter.ranged.state)
	end
	if slot == "ranged" then
		endParry(fighter, now())
	end
	applyMovement(fighter)
	queueOwnerState(fighter)
end

local function onMeleeAttack(player: Player, targetPart: BasePart?)
	local fighter = byPlayer[player]
	if fighter == nil or not Fighter.isAlive(fighter) then
		return
	end
	local melee = fighter.melee
	if melee == nil or fighter.activeSlot ~= "melee" then
		return
	end
	local time = now()
	Fighter.refresh(fighter, time)
	if fighter.move.stunned or fighter.move.parrying or fighter.usingItemId ~= nil then
		return
	end
	local def = melee.def
	local interval = 1 / def.attacksPerSecond
	local elapsed = time - melee.lastAttackAt
	if elapsed < interval * Combat.validation.fireRateTolerance then
		if elapsed < interval * 0.5 then
			ServerNet.flag(player, "MeleeAttack", "cadence de mêlée dépassée")
		end
		return
	end
	melee.lastAttackAt = time
	ServerNet.fireAllExcept("MeleeSwing", player, player, melee.item.itemId)

	if targetPart == nil then
		return -- coup dans le vide
	end
	local target = CombatService.findFighterByPart(targetPart)
	if target == nil or target == fighter then
		return
	end

	-- Portée (entre les centres, rayon des corps inclus) et angle frontal.
	local offset = target.root.Position - fighter.root.Position
	local maxDistance = def.range + Combat.melee.rangeTolerance + 2
	if offset.Magnitude > maxDistance then
		if offset.Magnitude > maxDistance * 2 then
			ServerNet.flag(player, "MeleeAttack", "cible hors de portée")
		end
		return
	end
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local look = fighter.root.CFrame.LookVector
	if flat.Magnitude > 1 then
		local cosine = flat.Unit:Dot(Vector3.new(look.X, 0, look.Z).Unit)
		if cosine < math.cos(math.rad(Combat.melee.maxAngle)) then
			return
		end
	end
	local blockedAt = castWorldRay(fighter.root.Position, offset)
	if blockedAt ~= nil and blockedAt < offset.Magnitude - 1.5 then
		return
	end

	local dealt, killed = CombatService.meleeHit(fighter, target, Damage.melee(def, melee.item.condition :: number), {
		breaksParry = def.breaksParry == true,
		parryBreakStun = def.parryBreakStun,
		shieldIgnore = def.shieldIgnore,
	})
	if dealt > 0 then
		ServerNet.fire("HitConfirm", player, false, killed)
	end
end

local function onSetParry(player: Player, active: boolean)
	local fighter = byPlayer[player]
	if fighter == nil or not Fighter.isAlive(fighter) then
		return
	end
	local time = now()
	Fighter.refresh(fighter, time)
	if not active then
		endParry(fighter, time)
		applyMovement(fighter)
		return
	end
	if
		fighter.move.parrying
		or fighter.move.stunned
		or fighter.usingItemId ~= nil
		or time < fighter.parryCooldownUntil
	then
		return
	end
	if fighter.melee == nil then
		return
	end
	-- Lever la garde passe automatiquement sur l'arme de mêlée.
	if fighter.activeSlot ~= "melee" then
		fighter.activeSlot = "melee"
		if fighter.ranged then
			WeaponLogic.cancelReload(fighter.ranged.state)
		end
		queueOwnerState(fighter)
	end
	if fighter.move.sprinting then
		fighter.move.sprinting = false
		fighter.sprintEndedAt = time
	end
	fighter.move.parrying = true
	fighter.parryStartedAt = time
	fighter.parryPerfected = false
	applyMovement(fighter)
end

local function onSetMovement(player: Player, stance: Movement.Stance, sprinting: boolean, clientTime: number)
	local fighter = byPlayer[player]
	if fighter == nil or not Fighter.isAlive(fighter) then
		return
	end
	local time = now()
	-- Horodatage client (même horloge que les tirs) : la fin du sprint est
	-- comparée à l'horodatage des tirs sans pénaliser la latence.
	local V = Combat.validation
	if clientTime > time + 0.1 or time - clientTime > V.maxShotAge then
		ServerNet.flag(player, "SetMovement", "horodatage incohérent")
		clientTime = time
	end
	Fighter.refresh(fighter, time)
	local move = fighter.move
	if stance ~= move.stance then
		if stance == "prone" or move.stance == "prone" then
			fighter.proneUntil = time + Combat.movement.proneTransition
		end
		move.stance = stance
	end
	local wantsSprint = sprinting and Movement.canSprint(move)
	if move.sprinting and not wantsSprint then
		fighter.sprintEndedAt = clientTime
	end
	if wantsSprint and not move.sprinting and fighter.ranged then
		-- Le sprint interrompt la recharge.
		WeaponLogic.cancelReload(fighter.ranged.state)
		queueOwnerState(fighter)
	end
	move.sprinting = wantsSprint
	applyMovement(fighter)
end

-- Fin de recharge due (mercenaires IA : pas de minuterie côté client).
function CombatService.finishReload(fighter: Fighter)
	finishReloadIfDue(fighter, now())
end

function CombatService.init()
	Players.RespawnTime = Combat.respawnTime

	ServerNet.onEvent("FireWeapon", shotValidator, onFireWeapon)
	ServerNet.onEvent("ReloadWeapon", Guard.tuple(), onReload)
	ServerNet.onEvent("SwitchWeapon", Guard.tuple(Guard.enum({ "ranged", "melee" })), onSwitchWeapon)
	ServerNet.onEvent("MeleeAttack", Guard.tuple(Guard.optional(Guard.instanceOf("BasePart"))), onMeleeAttack)
	ServerNet.onEvent("SetParry", Guard.tuple(Guard.boolean()), onSetParry)
	ServerNet.onEvent(
		"SetMovement",
		Guard.tuple(Guard.enum({ "stand", "crouch", "prone" }), Guard.boolean(), Guard.number(0)),
		onSetMovement
	)
end

function CombatService.start()
	-- Le combattant d'un joueur qui part reste enregistré jusqu'à la
	-- destruction de son personnage : la partie peut encore lâcher son sac.
	Players.PlayerRemoving:Connect(function(player)
		local fighter = byPlayer[player]
		if fighter then
			CombatService.PlayerLeaving:Fire(fighter)
		end
	end)
end

return CombatService
