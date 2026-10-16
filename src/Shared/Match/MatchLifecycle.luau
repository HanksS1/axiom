--!strict
--[[
	MatchLifecycle : une partie locale à la fois, proprement (logique pure, testée).

	Hub et parties sur le même serveur (Studio, ou places de partie à 0) : le
	serveur ne joue qu'une partie à la fois ; en ligne, chaque partie a son
	serveur réservé (cahier des charges, § 16.1).

	Phases : idle → running → returning → idle.
	- `returning` : la partie est finie, ses joueurs voient le bilan pendant
	  `Config.Match.returnDelay` avant d'être ramenés au Terminus. Aucune partie
	  ne démarre pendant ce temps (sinon la nouvelle carte se chargerait sous
	  les pieds des joueurs qui n'ont pas encore été ramenés).
	- `finish` capture LES joueurs de la partie qui se termine (`Batch`) : leur
	  retour se fait quoi qu'il arrive entre-temps. `complete` dit en plus s'il
	  faut remettre le monde à zéro (carte, butin, gadgets) : seulement si
	  aucune autre partie n'a démarré depuis.
]]

export type Phase = "idle" | "running" | "returning"

export type Batch = {
	matchId: string,
	players: { any }, -- Player (pur : aucune Instance n'est lue ici)
	returnAt: number,
}

export type Lifecycle = {
	phase: Phase,
	matchId: string?,
	endsAt: number, -- running : fin au plus tard (Purge) ; returning : retour des joueurs
	batch: Batch?, -- retour en attente
}

local MatchLifecycle = {}

function MatchLifecycle.new(): Lifecycle
	return { phase = "idle", matchId = nil, endsAt = 0, batch = nil }
end

-- Une partie peut-elle démarrer ? Sinon la raison : "running" | "returning".
function MatchLifecycle.canStart(lifecycle: Lifecycle): (boolean, string?)
	if lifecycle.phase == "idle" then
		return true, nil
	end
	return false, lifecycle.phase
end

-- `endsAt` : heure de fin au plus tard (début + durée de la partie).
function MatchLifecycle.start(lifecycle: Lifecycle, matchId: string, endsAt: number): boolean
	if not MatchLifecycle.canStart(lifecycle) then
		return false
	end
	lifecycle.phase = "running"
	lifecycle.matchId = matchId
	lifecycle.endsAt = endsAt
	return true
end

-- Fin de partie : capture de ses joueurs, retour prévu à `returnAt`.
function MatchLifecycle.finish(lifecycle: Lifecycle, players: { any }, returnAt: number): Batch?
	if lifecycle.phase ~= "running" or lifecycle.matchId == nil then
		return nil
	end
	local batch: Batch = { matchId = lifecycle.matchId :: string, players = table.clone(players), returnAt = returnAt }
	lifecycle.phase = "returning"
	lifecycle.endsAt = returnAt
	lifecycle.batch = batch
	return batch
end

--[[
	Retour des joueurs de `batch` (à faire dans tous les cas). Retourne true
	s'il faut aussi remettre le monde à zéro : aucune partie n'a démarré depuis.
]]
function MatchLifecycle.complete(lifecycle: Lifecycle, batch: Batch): boolean
	local untouched = lifecycle.phase == "returning" and lifecycle.matchId == batch.matchId
	if lifecycle.batch == batch then
		lifecycle.batch = nil
	end
	if untouched then
		lifecycle.phase = "idle"
		lifecycle.matchId = nil
		lifecycle.endsAt = 0
	end
	return untouched
end

-- Attente avant qu'une nouvelle partie puisse démarrer (secondes), ou nil si libre.
function MatchLifecycle.waitEstimate(lifecycle: Lifecycle, now: number, returnDelay: number): number?
	if lifecycle.phase == "idle" then
		return nil
	end
	if lifecycle.phase == "running" then
		return math.max(0, lifecycle.endsAt - now) + returnDelay
	end
	return math.max(0, lifecycle.endsAt - now)
end

return MatchLifecycle
