--!strict
--[[
	Turning : rotation progressive d'un robot ancré (tourelle, bras de Forge-7)
	autour de l'axe vertical — module PUR, testé (tests/specs/robots.spec.luau).

	Le serveur s'en sert pour le cap LOGIQUE (vision, tir) ; le client, pour
	l'affichage (RobotTurnController), avec les mêmes réglages : la rotation
	vue est la même que celle que le serveur calcule, mais fluide, sans dépendre
	de la fréquence de réplication.
]]

local Config = require(script.Parent.Parent.Config)

local AI = Config.Robots.ai

local Turning = {}

-- Écart d'angle ramené dans ]-π, π] (le plus court chemin).
function Turning.delta(from: number, to: number): number
	return (to - from + math.pi) % (2 * math.pi) - math.pi
end

-- Cap (radians, autour de Y) d'une orientation : 0 = -Z (devant).
function Turning.yawOf(rotation: CFrame): number
	local look = rotation.LookVector
	return math.atan2(-look.X, -look.Z)
end

--[[
	Un pas de rotation de `current` vers `target` (radians) : rapide puis
	ralenti (`turnResponsiveness`), jamais plus vite que `turnRate` rad/s.
	Retourne le nouveau cap et s'il a atteint la cible.
]]
function Turning.step(current: number, target: number, dt: number): (number, boolean)
	local delta = Turning.delta(current, target)
	if math.abs(delta) < math.rad(0.5) then
		return target, true
	end
	local alpha = math.min(1, dt * AI.turnResponsiveness)
	local turn = delta * alpha
	local limit = AI.turnRate * dt
	turn = math.clamp(turn, -limit, limit)
	return current + turn, false
end

return Turning
