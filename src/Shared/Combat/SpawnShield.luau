--!strict
--[[
	SpawnShield : bouclier de réapparition de l'Arène FFA (logique pure, testée).
	Distinct du bouclier d'équipement (gilet) : ni jauge ni absorption, une
	simple invulnérabilité de `Config.Arena.spawnShield` secondes.

	- accordé seulement dans l'arène, à l'apparition (réapparition après une
	  mort, arrivée par le pavé du Terminus) ;
	- ne protège que dans l'arène (une partie qui démarre l'annule de fait) ;
	- tombe IMMÉDIATEMENT dès que le joueur attaque (tir, coup, gadget) : il
	  sert à arriver sans être abattu, pas à attaquer sans risque. Se déplacer,
	  parer, recharger ou se soigner ne le font pas tomber.
]]

local Config = require(script.Parent.Parent.Config)

export type Action = "fire" | "melee" | "gadget" | "move" | "parry" | "reload" | "consumable"

local SpawnShield = {}

local DROPS: { [string]: boolean } = { fire = true, melee = true, gadget = true }

-- Fin de la protection accordée maintenant, ou nil hors de l'arène.
function SpawnShield.grant(now: number, zone: string): number?
	if zone ~= "arena" then
		return nil
	end
	return now + Config.Arena.spawnShield
end

-- La protection empêche-t-elle les dégâts ?
function SpawnShield.protects(untilTime: number?, now: number, zone: string): boolean
	return zone == "arena" and untilTime ~= nil and now < untilTime
end

-- Cette action fait-elle tomber la protection ?
function SpawnShield.dropsOn(action: Action): boolean
	return DROPS[action] == true
end

return SpawnShield
