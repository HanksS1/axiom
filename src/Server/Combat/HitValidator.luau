--!strict
--[[
	HitValidator : validation serveur des tirs déclarés par un client (6.11).

	Le client affiche son tir immédiatement puis envoie une INTENTION :
	{ t, origin, direction, hits = { { part, position } } }. Le serveur
	vérifie l'âge du tir, la position du tireur, la portée, la cohérence du
	point d'impact avec la position de la cible, que chaque impact est dans
	l'axe du tir (cône de dispersion maximal de l'arme), et la ligne de vue.
	Les dégâts sont ensuite calculés uniquement par le serveur.

	Le lancer de rayon est injecté (`castRay`) pour pouvoir tester hors Studio.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Damage = require(Shared.Combat.Damage)

local V = Config.Combat.validation

export type ClaimedHit = {
	part: BasePart,
	position: Vector3,
}

export type Shot = {
	t: number,
	origin: Vector3,
	direction: Vector3,
	hits: { ClaimedHit },
}

export type ValidHit = {
	target: any, -- Fighter
	part: BasePart,
	position: Vector3,
	distance: number,
	isHead: boolean,
	throughCover: boolean, -- un couvert léger a été traversé (dégâts réduits)
}

-- Raycast « monde » : retourne la distance du premier obstacle (hors
-- personnages), ou nil si la ligne est dégagée.
export type CastRay = (origin: Vector3, displacement: Vector3) -> number?

-- Variante qui traverse les couverts légers : (distance du premier obstacle
-- solide ou nil, un couvert léger a été traversé).
export type CastThrough = (origin: Vector3, displacement: Vector3) -> (number?, boolean)

export type Context = {
	now: number,
	shooterHead: Vector3, -- position serveur de la tête du tireur
	effectiveRange: number,
	maxProjectiles: number,
	findTarget: (part: BasePart) -> any?, -- Fighter vivant possédant la pièce, sinon nil
	shooter: any, -- Fighter du tireur
	castRay: CastRay,
	castThrough: CastThrough?, -- armes qui traversent les couverts légers
	-- Demi-angle (degrés) du cône de dispersion maximal de l'arme : un impact hors
	-- de ce cône (plus `directionTolerance`) autour de `shot.direction` est refusé.
	maxSpread: number?,
}

export type Verdict = {
	ok: boolean,
	reason: string?, -- incohérence grave (journalisée)
	hits: { ValidHit },
	dropped: number, -- impacts écartés sans sanction (ligne de vue, désynchronisation)
	originBlocked: boolean?, -- origine déclarée cachée derrière un obstacle : rien ne part
}

local HitValidator = {}

local function reject(reason: string): Verdict
	return { ok = false, reason = reason, hits = {}, dropped = 0 }
end

function HitValidator.validate(shot: Shot, context: Context): Verdict
	-- Âge du tir : ni trop vieux, ni dans le futur.
	if shot.t > context.now + 0.1 then
		return reject("tir daté dans le futur")
	end
	if context.now - shot.t > V.maxShotAge then
		return reject("tir trop ancien")
	end
	-- Position du tireur.
	if (shot.origin - context.shooterHead).Magnitude > V.maxShooterPositionError then
		return reject("position du tireur incohérente")
	end
	if #shot.hits > context.maxProjectiles then
		return reject("trop d'impacts déclarés")
	end
	-- L'origine déclarée doit être visible depuis la tête du tireur (sinon un
	-- client modifié pourrait tirer « depuis » l'autre côté d'un mur).
	local fromHead = shot.origin - context.shooterHead
	if fromHead.Magnitude > 0.5 then
		local blockedAt = context.castRay(context.shooterHead, fromHead)
		if blockedAt ~= nil and blockedAt < fromHead.Magnitude - 0.25 then
			return { ok = true, reason = nil, hits = {}, dropped = #shot.hits, originBlocked = true }
		end
	end

	local maxRange = Damage.maxRange(context.effectiveRange) + V.rangeTolerance
	local verdict: Verdict = { ok = true, reason = nil, hits = {}, dropped = 0 }
	local maxSpread = context.maxSpread
	local minCos = if maxSpread then math.cos(math.rad(math.min(180, maxSpread + V.directionTolerance))) else nil
	local direction = shot.direction.Unit

	for _, claim in shot.hits do
		local target = context.findTarget(claim.part)
		if target == nil or target == context.shooter then
			-- Cible morte entre-temps, ou pièce qui n'appartient à personne.
			verdict.dropped += 1
			continue
		end
		local offset = claim.position - shot.origin
		local distance = offset.Magnitude
		if distance > maxRange then
			return reject("impact hors de portée")
		end
		-- Dans l'axe du tir : un client modifié ne peut pas toucher une cible hors
		-- de son viseur (derrière lui, sur le côté).
		if minCos and distance > V.directionMinDistance and (offset / distance):Dot(direction) < minCos then
			return reject("impact hors de l'axe du tir")
		end
		local partRadius = claim.part.Size.Magnitude / 2
		if (claim.position - claim.part.Position).Magnitude > partRadius + V.maxHitPositionError then
			return reject("impact loin de la cible")
		end
		-- Ligne de vue : un obstacle avant le point d'impact annule l'impact
		-- (sans sanction : la cible a pu passer derrière un mur entre-temps).
		local throughCover = false
		if distance > 0.5 then
			local blockedAt: number?
			if context.castThrough then
				blockedAt, throughCover = context.castThrough(shot.origin, offset)
			else
				blockedAt = context.castRay(shot.origin, offset)
			end
			if blockedAt ~= nil and blockedAt < distance - 1 then
				verdict.dropped += 1
				continue
			end
		end
		table.insert(verdict.hits, {
			target = target,
			part = claim.part,
			position = claim.position,
			distance = distance,
			isHead = claim.part.Name == "Head",
			throughCover = throughCover,
		})
	end
	return verdict
end

return HitValidator
