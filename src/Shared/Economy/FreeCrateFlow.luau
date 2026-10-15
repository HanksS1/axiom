--!strict
--[[
	FreeCrateFlow : déroulé côté client de l'ouverture de la caisse gratuite
	(calcul pur, testé ; l'interface est dans TerminusController).

	idle ──start──▶ opening ──(fin de l'animation)──▶ waiting ──résultat──▶ shown ──close──▶ idle
	                   │                                  │
	                   └───────── cancel / refus / délai dépassé ──────────▶ idle

	- La demande au serveur (`OpenFreeCrate`) n'est envoyée qu'APRÈS
	  l'animation : une ouverture annulée (départ en partie, fermeture) n'a
	  rien consommé, la caisse reste disponible.
	- Chaque ouverture a un numéro de séance : la suite différée d'une
	  ouverture annulée (`task.delay`) est ignorée (`isCurrent`).
	- En file d'attente ou en partie, le serveur refuse l'ouverture
	  (économie verrouillée) : on ne lance pas d'animation (`decide`).
]]

local FreeCrateFlow = {}

export type Phase = "idle" | "opening" | "waiting" | "shown"

export type Flow = {
	phase: Phase,
	session: number,
	sentAt: number?,
}

-- Que faire quand le joueur clique sur la caisse ?
-- "animate" : animation puis demande ; "direct" : demande sans animation (le
-- serveur répond ou explique son refus) ; "busy" : une ouverture est en cours.
export type Decision = "animate" | "direct" | "busy"

function FreeCrateFlow.new(): Flow
	return { phase = "idle", session = 0, sentAt = nil }
end

function FreeCrateFlow.decide(
	flow: Flow,
	available: number,
	locked: boolean, -- en file d'attente ou en partie
	skipAnimation: boolean
): Decision
	if flow.phase == "opening" or flow.phase == "waiting" then
		return "busy"
	end
	if available <= 0 or locked or skipAnimation then
		return "direct"
	end
	return "animate"
end

-- Début de l'animation : retourne le numéro de séance.
function FreeCrateFlow.start(flow: Flow): number
	flow.session += 1
	flow.phase = "opening"
	flow.sentAt = nil
	return flow.session
end

-- La séance `session` est-elle toujours celle en cours d'animation ?
function FreeCrateFlow.isCurrent(flow: Flow, session: number): boolean
	return flow.phase == "opening" and flow.session == session
end

-- Fin de l'animation : demande envoyée au serveur.
function FreeCrateFlow.sent(flow: Flow, now: number)
	flow.phase = "waiting"
	flow.sentAt = now
end

-- Demande envoyée sans réponse depuis plus de `timeout` secondes (refus du serveur) ?
function FreeCrateFlow.timedOut(flow: Flow, now: number, timeout: number): boolean
	local sentAt = flow.sentAt
	return flow.phase == "waiting" and sentAt ~= nil and now - sentAt > timeout
end

function FreeCrateFlow.shown(flow: Flow)
	flow.phase = "shown"
	flow.sentAt = nil
end

-- Annulation (départ en partie, refus, délai dépassé) ou fermeture : la
-- séance en cours est périmée.
function FreeCrateFlow.cancel(flow: Flow)
	flow.session += 1
	flow.phase = "idle"
	flow.sentAt = nil
end

return FreeCrateFlow
