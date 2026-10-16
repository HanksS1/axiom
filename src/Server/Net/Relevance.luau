--!strict
--[[
	Relevance : à qui envoyer un événement visuel localisé (tir, coup) — module
	PUR, testé (tests/specs/util.spec.luau).

	Les parties se jouent sur le serveur du Terminus tant que les places ne sont
	pas configurées : sans filtre, les joueurs du hub recevraient tous les tirs
	de la partie. Un joueur reçoit l'événement si son personnage est à moins de
	`radius` studs ; un joueur sans personnage (chargement, spectateur) le reçoit
	par prudence (rien de pire que l'envoi à tous d'avant).
]]

local Relevance = {}

function Relevance.recipients<P>(
	players: { P },
	positionOf: (player: P) -> Vector3?,
	origin: Vector3,
	radius: number,
	except: P?
): { P }
	local result = {}
	for _, player in players do
		if player ~= except then
			local position = positionOf(player)
			if position == nil or (position - origin).Magnitude <= radius then
				table.insert(result, player)
			end
		end
	end
	return result
end

return Relevance
