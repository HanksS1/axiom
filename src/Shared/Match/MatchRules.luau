--!strict
--[[
	MatchRules : règles PURES du déroulé d'une partie (sections 4, 13, 15).

	- Chronologie : normale → alerte (12:00) → dernière minute → Purge (15:00).
	- Extraction : progression de 30 s, en pause si un coéquipier vivant est
	  hors de la zone, bloquée si un ennemi est dans la zone (sans retour à zéro).
	- Score de partie, XP, top 10 de saison et rangs.
]]

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

local Match = Config.Match
local Progression = Config.Progression

local MatchRules = {}

export type Phase = "normal" | "alert" | "final" | "purge"

function MatchRules.phase(elapsed: number): Phase
	if elapsed >= Match.duration then
		return "purge"
	elseif elapsed >= Match.finalCountdownAt then
		return "final"
	elseif elapsed >= Match.alertAt then
		return "alert"
	end
	return "normal"
end

-- Temps restant avant la Purge (jamais négatif).
function MatchRules.remaining(elapsed: number): number
	return math.max(0, Match.duration - elapsed)
end

export type ExtractionStatus = "idle" | "running" | "paused" | "blocked" | "done"

--[[
	Fait avancer l'extraction d'une équipe dans une zone.
	- membersInside : coéquipiers vivants dans la zone ;
	- membersAlive  : coéquipiers vivants (hors orbes et morts) ;
	- enemiesInside : joueurs adverses, mercenaires IA ou robots dans la zone.
]]
function MatchRules.stepExtraction(
	progress: number,
	dt: number,
	membersInside: number,
	membersAlive: number,
	enemiesInside: number
): (number, ExtractionStatus)
	local hold = Match.extraction.holdTime
	if progress >= hold then
		return hold, "done"
	end
	if membersInside <= 0 then
		return progress, "idle"
	end
	if enemiesInside > 0 then
		return progress, "blocked"
	end
	if membersInside < membersAlive then
		return progress, "paused"
	end
	local next = math.min(hold, progress + dt)
	return next, if next >= hold then "done" else "running"
end

export type MatchStats = {
	playerKills: number,
	botKills: number,
	robotPoints: number,
	lootValue: number, -- valeur du loot extrait
}

export type ScoreBreakdown = {
	playerKills: number,
	botKills: number,
	robots: number,
	loot: number,
	modeMultiplier: number,
	deathPenalty: boolean,
	total: number,
}

--[[
	Score = (kills joueurs × 100 + kills IA × 50 + points des robots
	         + valeur du loot extrait / 10) × multiplicateur de mode.
	Mort sans extraction : la valeur du loot compte 0 et le score est divisé par 2.
]]
function MatchRules.score(stats: MatchStats, modeId: string, extracted: boolean): ScoreBreakdown
	local S = Progression.score
	local mode = Config.Modes.byId[modeId]
	local multiplier = if mode then mode.scoreMultiplier else 1
	local kills = stats.playerKills * S.playerKill
	local bots = stats.botKills * S.botKill
	local loot = if extracted then math.floor(stats.lootValue / S.lootValueDivisor) else 0
	local raw = (kills + bots + stats.robotPoints + loot) * multiplier
	if not extracted then
		raw *= S.deathPenaltyMultiplier
	end
	return {
		playerKills = kills,
		botKills = bots,
		robots = stats.robotPoints,
		loot = loot,
		modeMultiplier = multiplier,
		deathPenalty = not extracted,
		total = math.floor(raw),
	}
end

--[[
	Crédits gagnés en fin de partie (Config.Progression.credits), à partir du score
	déjà calculé. `abandoned` : le joueur a quitté la partie (aucun gain).
]]
function MatchRules.matchCredits(scoreTotal: number, extracted: boolean, abandoned: boolean): number
	if abandoned then
		return 0
	end
	local C = Progression.credits
	local base = C.participation + math.max(0, scoreTotal) * C.scoreShare
	local credits = if extracted then base + C.extractionBonus else base * C.deathShare
	return math.clamp(math.floor(credits), 0, C.maxPerMatch)
end

export type TopGame = Types.TopGame

--[[
	Insère une partie dans le top 10 de saison si elle bat la plus faible.
	Retourne le nouveau top 10 (trié, décroissant) et la position obtenue
	(nil si la partie n'y entre pas).
]]
function MatchRules.insertTopGame(top: { TopGame }, game: TopGame): ({ TopGame }, number?)
	local limit = Progression.season.topGames
	local result = table.clone(top)
	table.sort(result, function(a, b)
		return a.score > b.score
	end)
	if game.score <= 0 then
		return result, nil
	end
	if #result >= limit and game.score <= result[#result].score then
		return result, nil
	end
	local position = #result + 1
	for index, entry in result do
		if game.score > entry.score then
			position = index
			break
		end
	end
	table.insert(result, position, game)
	while #result > limit do
		table.remove(result)
	end
	return result, position
end

-- Score de classement : somme des 10 meilleures parties.
function MatchRules.rankingScore(top: { TopGame }): number
	local total = 0
	for _, entry in top do
		total += entry.score
	end
	return total
end

-- Rang correspondant à un score de classement (hors « Légende », calculée sur le classement mondial).
function MatchRules.rank(rankingScore: number): string
	local current = Progression.season.ranks[1].id
	for _, rank in Progression.season.ranks do
		if rankingScore >= rank.minScore then
			current = rank.id
		end
	end
	return current
end

-- Numéro de saison (1, 2, …) à une date Unix ; 0 avant la première saison.
function MatchRules.seasonAt(unix: number): number
	local season = Progression.season
	if unix < season.firstSeasonStartUnix then
		return 0
	end
	local length = season.lengthWeeks * 7 * 24 * 60 * 60
	return math.floor((unix - season.firstSeasonStartUnix) / length) + 1
end

-- Rang affiché pour un top 10 de saison (« legend » si le joueur a atteint le top mondial).
function MatchRules.seasonRank(season: { top10: { TopGame }, legend: boolean? }): string
	if season.legend then
		return "legend"
	end
	return MatchRules.rank(MatchRules.rankingScore(season.top10))
end

--[[
	Passe le profil à la saison en cours si elle a changé : le rang final
	de l'ancienne saison va dans l'historique, puis top 10 et rang sont
	remis à zéro. Renvoie true si le profil a été modifié.
]]
function MatchRules.rollSeason(
	profile: {
		season: { id: number, top10: { TopGame }, legend: boolean? },
		seasonHistory: { { id: number, rank: string } },
	},
	unix: number
): boolean
	local current = MatchRules.seasonAt(unix)
	if profile.season.id == current then
		return false
	end
	if profile.season.id > 0 and #profile.season.top10 > 0 then
		table.insert(profile.seasonHistory, { id = profile.season.id, rank = MatchRules.seasonRank(profile.season) })
	end
	profile.season = { id = current, top10 = {} }
	return true
end

return MatchRules
