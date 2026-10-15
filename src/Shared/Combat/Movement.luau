--!strict
--[[
	Movement : vitesses, saut et dispersion selon la posture (section 5.2).
	Fonctions PURES partagées par le client (prédiction) et le serveur
	(contrôle de vitesse et validation).
]]

local Config = require(script.Parent.Parent.Config)

local M = Config.Combat.movement
local Parry = Config.Combat.parry

export type Stance = "stand" | "crouch" | "prone"

export type MoveState = {
	stance: Stance,
	sprinting: boolean,
	parrying: boolean,
	stunned: boolean,
	speedMultiplier: number, -- bonus / malus temporaires (Surcharge, ralentissement…)
	usingConsumable: number?, -- multiplicateur pendant l'utilisation d'un consommable
}

local Movement = {}

Movement.stances = table.freeze({ "stand", "crouch", "prone" } :: { Stance })

function Movement.isStance(value: any): boolean
	return value == "stand" or value == "crouch" or value == "prone"
end

-- Le sprint n'est possible que debout, sans garde ni étourdissement.
function Movement.canSprint(state: MoveState): boolean
	return state.stance == "stand" and not state.parrying and not state.stunned
end

function Movement.walkSpeed(state: MoveState): number
	local speed: number
	if state.stance == "prone" then
		speed = M.proneSpeed
	elseif state.stance == "crouch" then
		speed = M.crouchSpeed
	elseif state.sprinting and Movement.canSprint(state) then
		speed = M.sprintSpeed
	else
		speed = M.walkSpeed
	end
	if state.parrying then
		speed *= Parry.moveSpeedMultiplier
	end
	if state.stunned then
		speed = math.min(speed, M.walkSpeed * M.stunMoveMultiplier)
	end
	if state.usingConsumable then
		speed *= state.usingConsumable
	end
	return speed * state.speedMultiplier
end

function Movement.jumpHeight(state: MoveState): number
	if state.stance == "prone" or state.stunned then
		return 0
	end
	return M.jumpHeight
end

--[[
	Dispersion (degrés) d'une arme selon la posture, la visée, le mouvement et
	le saut. La précision accrue (+15 % accroupi, +30 % couché) réduit la
	dispersion. En l'air, les tirs partent de travers, quoi qu'on fasse.
]]
function Movement.spread(
	baseSpread: number,
	stance: Stance,
	aiming: boolean,
	moving: boolean,
	airborne: boolean?
): number
	if airborne then
		return baseSpread * M.airborneSpreadMultiplier + M.airborneSpreadBonus
	end
	local spread = baseSpread
	if stance == "crouch" then
		spread *= 1 - M.crouchAccuracyBonus
	elseif stance == "prone" then
		spread *= 1 - M.proneAccuracyBonus
	end
	if aiming then
		spread *= 1 - M.aimAccuracyBonus
	end
	if moving then
		spread *= M.movingSpreadMultiplier
	end
	return spread
end

return Movement
