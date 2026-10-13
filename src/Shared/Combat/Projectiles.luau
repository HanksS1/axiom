--!strict
--[[
	Projectiles : vol des projectiles lents (section 6.6).

	- Lance-clous magnétique : projectile droit, 250 studs/s.
	- Court-Circuit : grenade en cloche (gravité propre), explosion en zone.

	Le client n'envoie qu'une origine et une direction : c'est le SERVEUR qui
	fait voler le projectile et décide de l'impact (aucun impact déclaré par
	le client pour ces armes). Le client utilise la même logique pour
	l'image du projectile seulement. Logique PURE : le lancer de rayon et la
	réaction à l'impact sont injectés, pour pouvoir tester hors Studio.
]]

local Projectiles = {}

export type Projectile = {
	position: Vector3,
	velocity: Vector3,
	gravity: number, -- studs/s² vers le bas (0 = tir droit)
	origin: Vector3,
	traveled: number,
	maxDistance: number,
	expiresAt: number,
	data: any, -- propre à l'appelant (tireur, arme…)
}

-- Premier obstacle sur un segment : position et pièce touchée, ou nil.
export type Cast = (projectile: Projectile, from: Vector3, displacement: Vector3) -> (Vector3?, any?)

-- `instance` = nil : le projectile s'est éteint sans rien toucher (portée, durée).
export type Impact = (projectile: Projectile, position: Vector3, instance: any?) -> ()

-- Pas de simulation maximal : un à-coup du serveur ne fait pas sauter un mur.
local MAX_STEP = 1 / 30

function Projectiles.new(
	origin: Vector3,
	velocity: Vector3,
	gravity: number,
	maxDistance: number,
	expiresAt: number,
	data: any
): Projectile
	return {
		position = origin,
		velocity = velocity,
		gravity = gravity,
		origin = origin,
		traveled = 0,
		maxDistance = maxDistance,
		expiresAt = expiresAt,
		data = data,
	}
end

-- Avance un projectile de `dt`. Retourne false quand il a fini sa course.
local function advance(projectile: Projectile, dt: number, cast: Cast, onImpact: Impact): boolean
	local remaining = dt
	while remaining > 1e-6 do
		local step = math.min(remaining, MAX_STEP)
		remaining -= step
		local drop = Vector3.new(0, -projectile.gravity * step, 0)
		local displacement = projectile.velocity * step + drop * (step / 2)
		local hitPosition, instance = cast(projectile, projectile.position, displacement)
		if hitPosition then
			projectile.traveled += (hitPosition - projectile.position).Magnitude
			projectile.position = hitPosition
			onImpact(projectile, hitPosition, instance)
			return false
		end
		projectile.position += displacement
		projectile.velocity += drop
		projectile.traveled += displacement.Magnitude
		if projectile.traveled >= projectile.maxDistance then
			onImpact(projectile, projectile.position, nil)
			return false
		end
	end
	return true
end

--[[
	Avance tous les projectiles de la liste (modifiée en place : ceux qui ont
	touché quelque chose, dépassé leur portée ou leur durée de vie en sortent).
]]
function Projectiles.step(list: { Projectile }, dt: number, now: number, cast: Cast, onImpact: Impact)
	local index = 1
	while index <= #list do
		local projectile = list[index]
		local alive = true
		if now >= projectile.expiresAt then
			onImpact(projectile, projectile.position, nil)
			alive = false
		else
			alive = advance(projectile, dt, cast, onImpact)
		end
		if alive then
			index += 1
		else
			table.remove(list, index)
		end
	end
end

--[[
	Direction de tir en cloche pour atteindre `target` depuis `origin` avec
	une vitesse `speed` et une gravité `gravity` (trajectoire tendue). Hors de
	portée : tir à 45° dans la direction de la cible.
]]
function Projectiles.ballisticDirection(origin: Vector3, target: Vector3, speed: number, gravity: number): Vector3
	local offset = target - origin
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local distance = flat.Magnitude
	if gravity <= 0 or distance < 1e-3 then
		return if offset.Magnitude > 1e-3 then offset.Unit else Vector3.new(0, 0, -1)
	end
	local forward = flat / distance
	local speed2 = speed * speed
	local discriminant = speed2 * speed2 - gravity * (gravity * distance * distance + 2 * offset.Y * speed2)
	local tangent = if discriminant >= 0 then (speed2 - math.sqrt(discriminant)) / (gravity * distance) else 1
	return (forward + Vector3.new(0, tangent, 0)).Unit
end

return Projectiles
