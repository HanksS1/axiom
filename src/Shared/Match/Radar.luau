--!strict
--[[
	Radar : calculs du détecteur du joueur (module PUR).

	Le détecteur (en haut à gauche) montre les robots proches autour du
	joueur, au centre. « Devant » (le regard de la caméra) est en haut.
	Chaque robot a un niveau de menace pour CE joueur :

	- "none"     : en patrouille, ne vous a pas vu ;
	- "alert"    : en alerte (recherche, autre cible), pas contre vous ;
	- "noticed"  : est en train de vous remarquer (soupçon) ;
	- "hostile"  : vous a pris pour cible ;
	- "imminent" : vous vise de près, ou prépare une attaque annoncée.
]]

local Radar = {}

export type Level = "none" | "alert" | "noticed" | "hostile" | "imminent"

export type Contact = {
	alert: string?, -- attribut Alert du robot ("suspicion" | "search" | "combat")
	aggro: boolean, -- le robot a remarqué ou vise CE joueur
	windup: boolean, -- attaque annoncée en cours
	guardian: boolean,
	distance: number,
}

export type Ranges = { imminentRange: number, guardianImminentRange: number }

local ORDER: { [string]: number } = { none = 0, alert = 1, noticed = 2, hostile = 3, imminent = 4 }

-- Regard à plat (devant = nord si la caméra regarde à la verticale).
local function flatLook(look: Vector3): Vector3
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

--[[
	Position d'un point sur le radar, en rayons : x vers la droite, y vers le
	bas de l'écran (devant = y négatif). Un point hors de portée est ramené
	sur le bord (troisième valeur : true).
]]
function Radar.project(offset: Vector3, look: Vector3, range: number): (number, number, boolean)
	local forward = flatLook(look)
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local x = offset:Dot(right) / range
	local y = -offset:Dot(forward) / range
	local length = math.sqrt(x * x + y * y)
	if length > 1 then
		return x / length, y / length, true
	end
	return x, y, false
end

-- Angle (radians) entre le regard et la direction du point : 0 devant, positif à droite.
function Radar.bearing(offset: Vector3, look: Vector3): number
	local forward = flatLook(look)
	local right = Vector3.new(-forward.Z, 0, forward.X)
	return math.atan2(offset:Dot(right), offset:Dot(forward))
end

function Radar.level(contact: Contact, ranges: Ranges): Level
	if not contact.aggro then
		return if contact.alert then "alert" else "none"
	end
	if contact.alert ~= "combat" then
		return "noticed"
	end
	local near = if contact.guardian then ranges.guardianImminentRange else ranges.imminentRange
	if contact.windup or contact.distance <= near then
		return "imminent"
	end
	return "hostile"
end

-- Le plus grave de deux niveaux (état général du détecteur).
function Radar.worst(a: Level, b: Level): Level
	return if ORDER[b] > ORDER[a] then b else a
end

function Radar.rank(level: Level): number
	return ORDER[level]
end

return Radar
