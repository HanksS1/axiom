--!strict
--[[
	RobotBrain : machine à états PURE de l'IA des robots (section 10.4).

		Patrouille → Suspicion → Combat → Recherche → Patrouille

	- Perception : cône de vision (90°) et portée selon le type ; le serveur
	  fournit les cibles visibles (ligne de vue déjà vérifiée).
	- Audition : un bruit (tir, alarme) dans son rayon envoie le robot en recherche.
	- Ciblage : la cible la plus menaçante (celle qui vient de lui infliger des
	  dégâts), sinon la plus proche. Aucune distinction entre équipes.
	- Temps de réaction selon le mode avant le premier tir.
]]

local Config = require(script.Parent.Parent.Config)

local AI = Config.Robots.ai

export type State = "patrol" | "suspicion" | "combat" | "search"

export type Brain = {
	state: State,
	targetId: any?,
	suspicion: number,
	lastKnown: Vector3?,
	searchUntil: number,
	readyAt: number, -- moment où le robot peut tirer (temps de réaction)
	threatId: any?,
	threatUntil: number,
}

export type VisibleTarget = {
	id: any,
	position: Vector3,
	distance: number,
}

export type Perception = {
	now: number,
	dt: number,
	visible: { VisibleTarget },
	noise: Vector3?, -- position du dernier bruit entendu
	alertedAt: Vector3?, -- alerte d'une Mouche (position de la cible repérée)
}

local RobotBrain = {}

function RobotBrain.new(): Brain
	return {
		state = "patrol",
		targetId = nil,
		suspicion = 0,
		lastKnown = nil,
		searchUntil = 0,
		readyAt = 0,
		threatId = nil,
		threatUntil = 0,
	}
end

-- La cible est-elle dans le cône de vision (angle total `angle`, en degrés) ?
function RobotBrain.inCone(forward: Vector3, toTarget: Vector3, angle: number): boolean
	local flatForward = Vector3.new(forward.X, 0, forward.Z)
	local flatTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
	if flatTarget.Magnitude < 1e-3 then
		return true
	end
	if flatForward.Magnitude < 1e-3 then
		return false
	end
	return flatForward.Unit:Dot(flatTarget.Unit) >= math.cos(math.rad(angle / 2))
end

-- Signale une attaque subie : l'attaquant devient prioritaire.
function RobotBrain.onDamaged(brain: Brain, attackerId: any, attackerPosition: Vector3, now: number)
	brain.threatId = attackerId
	brain.threatUntil = now + AI.threatMemory
	brain.lastKnown = attackerPosition
	if brain.state ~= "combat" then
		-- Être touché vaut une détection immédiate.
		brain.state = "search"
		brain.searchUntil = now + AI.searchTime
	end
end

local function chooseTarget(brain: Brain, visible: { VisibleTarget }, now: number): VisibleTarget?
	local best: VisibleTarget? = nil
	for _, target in visible do
		if brain.threatId ~= nil and now < brain.threatUntil and target.id == brain.threatId then
			return target
		end
		if best == nil or target.distance < best.distance then
			best = target
		end
	end
	return best
end

--[[
	Fait évoluer le cerveau d'un pas. `reactionTime` vient du mode.
	Retourne la cible courante (nil hors combat).
]]
function RobotBrain.step(brain: Brain, perception: Perception, reactionTime: number): VisibleTarget?
	local now = perception.now
	local target = chooseTarget(brain, perception.visible, now)

	if target then
		brain.lastKnown = target.position
		if brain.state == "combat" then
			if brain.targetId ~= target.id then
				brain.targetId = target.id
				brain.readyAt = now + reactionTime
			end
			return target
		end
		-- Suspicion : il faut voir la cible un court instant (sauf si déjà en alerte).
		local alerted = brain.state == "search"
		brain.suspicion += perception.dt
		if alerted or brain.suspicion >= AI.suspicionTime then
			brain.state = "combat"
			brain.targetId = target.id
			brain.suspicion = 0
			brain.readyAt = now + reactionTime
			return target
		end
		brain.state = "suspicion"
		return nil
	end

	-- Plus de cible visible.
	brain.suspicion = math.max(0, brain.suspicion - perception.dt)
	if brain.state == "combat" or brain.state == "suspicion" then
		brain.state = "search"
		brain.targetId = nil
		brain.searchUntil = now + AI.searchTime
		return nil
	end

	local heard = perception.noise or perception.alertedAt
	if heard then
		brain.state = "search"
		brain.lastKnown = heard
		brain.searchUntil = now + AI.searchTime
		return nil
	end

	if brain.state == "search" and now >= brain.searchUntil then
		brain.state = "patrol"
		brain.lastKnown = nil
	end
	return nil
end

-- Le robot peut-il tirer (temps de réaction écoulé) ?
function RobotBrain.canAttack(brain: Brain, now: number): boolean
	return brain.state == "combat" and now >= brain.readyAt
end

return RobotBrain
