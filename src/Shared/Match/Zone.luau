--!strict
--[[
	Zone : où se trouve un joueur, et ce qui y est permis (logique pure, testée).
	Règles : `Config.Zones` (voir l'en-tête de ce fichier pour les zones).

	Le serveur rassemble les faits (`Facts`) et décide ; le client ne reçoit la
	zone que pour l'affichage (attribut « Zone » du joueur).
]]

local Config = require(script.Parent.Parent.Config)

export type Zone = "match" | "arena" | "tutorial" | "hub"
export type Rule = "gadgets" | "freeAmmo"

export type Facts = {
	inMatch: boolean, -- participant d'une partie en cours, pas encore sorti
	inTutorial: boolean,
	inArena: boolean, -- position dans l'Arène FFA
}

local Zone = {}

-- Priorité : la partie, puis le tutoriel, puis l'arène ; ailleurs, le Terminus.
-- (Pendant une partie sur le même serveur, un joueur resté dans l'arène n'y
-- participe pas : il reste en « arena ».)
function Zone.classify(facts: Facts): Zone
	if facts.inMatch then
		return "match"
	elseif facts.inTutorial then
		return "tutorial"
	elseif facts.inArena then
		return "arena"
	end
	return "hub"
end

-- Position dans les bornes de l'Arène FFA (centrée sur l'origine du monde, jusqu'au
-- plafond de son enceinte). Le serveur vérifie en plus que l'arène est construite.
function Zone.inArena(position: Vector3): boolean
	local half = Config.Dev.arenaSize / 2
	return math.abs(position.X) <= half
		and math.abs(position.Z) <= half
		and position.Y > -20
		and position.Y < Config.Arena.ceiling + 4
end

-- Position sur une carte de partie (elles sont construites autour de Config.Maps.origin,
-- loin du Terminus et de l'Arène FFA). Hauteur large : toits, chutes.
function Zone.onMatchMap(position: Vector3): boolean
	local offset = position - Config.Maps.origin
	local half = Config.Maps.size / 2 + Config.Match.strandedMargin
	return math.abs(offset.X) <= half and math.abs(offset.Z) <= half
end

-- Règle permise dans cette zone ? Une zone inconnue (attribut absent côté client,
-- serveur de partie dédié) suit les règles d'une partie.
function Zone.allows(zone: string?, rule: Rule): boolean
	local rules = (Config.Zones.rules :: any)[zone or "match"] or Config.Zones.rules.match
	return rules[rule] == true
end

return Zone
