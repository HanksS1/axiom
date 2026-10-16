--!strict
--[[
	MovementCheck : décision du contrôle des déplacements (section 19.4),
	logique pure (MovementGuardService l'applique aux personnages).

	À chaque contrôle, le déplacement horizontal DEPUIS LA DERNIÈRE POSITION
	VALIDE est comparé à ce que la vitesse autorisée permet sur le temps écoulé
	depuis (× tolérance, + marge fixe), et la montée à un plafond par contrôle.
	Une infraction isolée est pardonnée (paquets réseau regroupés : le contrôle
	suivant, mesuré sur deux intervalles, repasse) ; `strikesBeforeCorrection`
	infractions de suite → recalage à la dernière position valide. Mesurer
	depuis la position valide, et non depuis la précédente, empêche une
	téléportation unique de passer pour un simple à-coup. Un joueur immobile vu
	du serveur (pic de latence) accumule jusqu'à `catchUpWindow` secondes de
	déplacement à rattraper. La chute n'est pas limitée.

	Tolérances :
	- vitesse qui baisse (fin de sprint…) : l'ancienne reste admise
	  `speedGraceTime` secondes (latence du client) ;
	- gadgets et poussées : allocation temporaire de vitesse et de montée
	  (`grant`) ;
	- après une téléportation serveur : 1 s sans contrôle.
	Réglages : `Config.Combat.movementGuard`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local G = Config.Combat.movementGuard
local M = Config.Combat.movement

-- En deçà (studs), le personnage est considéré immobile entre deux contrôles.
local STILL = 0.5

export type Track = {
	lastValid: CFrame,
	sinceValid: number, -- secondes écoulées depuis `lastValid` (infractions en cours)
	strikes: number,
	currentSpeed: number, -- vitesse autorisée actuelle (dernier changement connu)
	-- Vitesse autorisée la plus élevée récente (tolérance de latence).
	recentMaxSpeed: number,
	recentMaxUntil: number,
	allowanceSpeed: number,
	allowanceUntil: number,
	allowanceRise: number, -- montée verticale tolérée par contrôle pendant l'allocation
	resetUntil: number, -- après un recalage ou une téléportation serveur
}

-- "ok" : position acceptée ; "strike" : infraction pardonnée ; "correct" : recaler.
export type Verdict = "ok" | "strike" | "correct"

local MovementCheck = {}

function MovementCheck.newTrack(cframe: CFrame, clock: number): Track
	return {
		lastValid = cframe,
		sinceValid = 0,
		strikes = 0,
		currentSpeed = M.walkSpeed,
		-- Personnage qui (ré)apparaît : il peut déjà sprinter.
		recentMaxSpeed = M.sprintSpeed,
		recentMaxUntil = clock + G.speedGraceTime,
		allowanceSpeed = 0,
		allowanceUntil = 0,
		allowanceRise = 0,
		resetUntil = clock + 1,
	}
end

-- Vitesse admise : celle de l'état actuel, ou plus si une tolérance est en cours.
function MovementCheck.allowedSpeed(track: Track, baseSpeed: number, clock: number): number
	local speed = baseSpeed
	if clock < track.recentMaxUntil then
		speed = math.max(speed, track.recentMaxSpeed)
	end
	if clock < track.allowanceUntil then
		speed = math.max(speed, track.allowanceSpeed)
	end
	return speed
end

--[[
	Un contrôle : `cframe` est la position actuelle, `dt` le temps écoulé depuis
	le précédent, `baseSpeed` la vitesse de l'état (Movement.walkSpeed).
	`frozen` : personnage ancré (cinématique, recalage en cours) → accepté.
	Sur "correct", l'appelant replace le personnage sur `track.lastValid` ; le
	second retour est la raison (journal anti-triche).
]]
function MovementCheck.step(
	track: Track,
	cframe: CFrame,
	clock: number,
	dt: number,
	baseSpeed: number,
	frozen: boolean
): (Verdict, string?)
	local position = cframe.Position
	if clock < track.resetUntil or frozen then
		track.lastValid = cframe
		track.sinceValid = 0
		track.strikes = 0
		return "ok", nil
	end

	local window = track.sinceValid + dt
	local delta = position - track.lastValid.Position
	local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
	local maxHorizontal = MovementCheck.allowedSpeed(track, baseSpeed, clock) * window * G.speedTolerance
		+ G.flatTolerance
	local tooFast = horizontal > maxHorizontal
	local maxRise = if clock < track.allowanceUntil
		then math.max(G.maxVerticalRise, track.allowanceRise)
		else G.maxVerticalRise
	-- Plafond par contrôle : sur plusieurs intervalles, autant de fois le plafond.
	local tooHigh = delta.Y > maxRise * math.max(1, window / dt)

	if tooFast or tooHigh then
		track.strikes += 1
		if track.strikes < G.strikesBeforeCorrection then
			track.sinceValid = window
			return "strike", nil
		end
		track.sinceValid = 0
		track.strikes = 0
		return "correct",
			if tooHigh then "montée anormale" else `vitesse anormale ({math.floor(horizontal / window)} studs/s)`
	end
	track.strikes = 0
	if horizontal < STILL and math.abs(delta.Y) < STILL then
		-- Immobile vu du serveur (arrêt, ou paquets en retard) : le temps s'accumule,
		-- borné, pour que le rattrapage d'un pic de latence ne passe pas pour une
		-- téléportation.
		track.sinceValid = math.min(window, G.catchUpWindow)
	else
		track.lastValid = cframe
		track.sinceValid = 0
	end
	return "ok", nil
end

-- Tolérance temporaire (gadgets, poussées). Une allocation échue repart de zéro ;
-- sinon les allocations se cumulent (la plus grande vitesse, la plus grande montée).
function MovementCheck.grant(track: Track, speed: number, duration: number, rise: number?, clock: number)
	if clock >= track.allowanceUntil then
		track.allowanceSpeed = 0
		track.allowanceRise = 0
	end
	track.allowanceSpeed = math.max(track.allowanceSpeed, speed)
	track.allowanceRise = math.max(track.allowanceRise, rise or 0)
	track.allowanceUntil = math.max(track.allowanceUntil, clock + duration)
end

-- Changement d'état (sprint, posture, effet) : l'ancienne vitesse reste admise un instant.
function MovementCheck.speedChanged(track: Track, newSpeed: number, clock: number)
	local stillTolerated = if clock < track.recentMaxUntil then track.recentMaxSpeed else 0
	track.recentMaxSpeed = math.max(stillTolerated, track.currentSpeed, newSpeed)
	track.recentMaxUntil = clock + G.speedGraceTime
	track.currentSpeed = newSpeed
end

-- Repoussement (Gantelet à impulsion) : vitesse, durée et montée à tolérer pour la victime.
function MovementCheck.knockbackAllowance(
	velocity: Vector3,
	duration: number,
	gravity: number
): (number, number, number)
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local rise = velocity.Y * velocity.Y / (2 * gravity) + 3
	return horizontal * 1.2, duration + 0.6, rise
end

return MovementCheck
