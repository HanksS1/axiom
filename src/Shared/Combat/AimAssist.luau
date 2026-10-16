--!strict
--[[
	AimAssist : visée assistée à la manette et au tactile (jamais à la souris),
	logique pure. Réglages : `Config.Combat.aimAssist`.

	- cible : la plus proche du centre de l'écran dans un cône étroit (6°), à
	  portée (140 studs) ;
	- ralentissement : la rotation de la caméra est freinée sur une cible
	  (jusqu'à 45 %, selon la force réglée par le joueur) ;
	- adhérence : la caméra glisse vers la cible, bornée à 7°/s × force.
]]

local Config = require(script.Parent.Parent.Config)

local A = Config.Combat.aimAssist

export type Candidate = { point: Vector3, model: any }

local AimAssist = {}

-- Force effective (0 = désactivée) : appareil, paramètre on/off, curseur de force.
function AimAssist.strength(device: string, enabled: boolean, strength: number): number
	if device == "keyboard" or not enabled then
		return 0
	end
	return math.clamp(strength, 0, 1)
end

-- Meilleure cible : la plus proche du centre (cône et portée), ou nil.
function AimAssist.pick(origin: Vector3, look: Vector3, candidates: { Candidate }): Candidate?
	local best: Candidate? = nil
	local bestDot = math.cos(math.rad(A.cone))
	for _, candidate in candidates do
		local offset = candidate.point - origin
		local distance = offset.Magnitude
		if distance > A.range or distance < 1 then
			continue
		end
		local dot = look:Dot(offset / distance)
		if dot > bestDot then
			best, bestDot = candidate, dot
		end
	end
	return best
end

-- Multiplicateur de la vitesse de rotation (1 = aucun frein).
function AimAssist.slowdown(strength: number, hasTarget: boolean): number
	if not hasTarget then
		return 1
	end
	return 1 - A.slowdown * strength
end

--[[
	Un pas d'adhérence : lacet / tangage rapprochés de la direction de la cible,
	chacun d'au plus `pull × force × dt` (radians). Le lacet prend le plus
	court chemin (passage de -π à π).
]]
function AimAssist.pull(
	yaw: number,
	pitch: number,
	direction: Vector3,
	strength: number,
	dt: number,
	maxPitch: number
): (number, number)
	local targetYaw = math.atan2(-direction.X, -direction.Z)
	local targetPitch = math.asin(math.clamp(direction.Y, -1, 1))
	local maxStep = math.rad(A.pull) * strength * dt
	local yawDiff = (targetYaw - yaw + math.pi) % (2 * math.pi) - math.pi
	local newYaw = yaw + math.clamp(yawDiff, -maxStep, maxStep)
	local newPitch = math.clamp(pitch + math.clamp(targetPitch - pitch, -maxStep, maxStep), -maxPitch, maxPitch)
	return newYaw, newPitch
end

return AimAssist
