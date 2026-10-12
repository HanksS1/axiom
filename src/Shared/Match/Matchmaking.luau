--!strict
--[[
	Matchmaking : règles pures (sections 4.2, 4.3, 16.2, 16.3).

	- Groupe de plateformes d'une file : crossplay, ou une seule plateforme
	  (tactile, clavier/souris, manette). Un duo de deux plateformes
	  différentes est forcé en crossplay.
	- Éligibilité d'un joueur à un mode : niveau, SE dans la plage du mode,
	  loot de la partie précédente trié.
	- Composition d'une partie à partir d'une file triée par ancienneté :
	  16 places (un duo en prend 2) ; lancement dès que c'est plein, ou après
	  le délai d'attente avec complément de mercenaires IA.
	- Duo aléatoire : un joueur seul peut rejoindre la file Duo (ticket
	  « à compléter »). Deux joueurs seuls sont appariés ; celui qui reste
	  seul au départ reçoit un mercenaire IA comme coéquipier.
]]

local Config = require(script.Parent.Parent.Config)
local ItemRules = require(script.Parent.Parent.Items.ItemRules)
local Types = require(script.Parent.Parent.Types)

local Matchmaking = {}

export type Platform = "touch" | "keyboard" | "gamepad"
export type Format = "solo" | "duo"

export type Ticket = {
	id: string,
	userIds: { number },
	fill: boolean?, -- duo aléatoire : joueur seul à apparier
	modeId: string,
	format: Format,
	group: string,
	joinedAt: number,
	hubJobId: string,
}

export type Composition = {
	tickets: { Ticket },
	teams: { { number } }, -- joueurs par équipe (un duo aléatoire peut rester à 1)
	players: number,
	bots: number,
	full: boolean,
}

export type Member = {
	level: number,
	score: number,
	pendingLoot: number,
}

export type Refusal = {
	reason: string,
	params: { [string]: any }?,
}

-- Taille d'un ticket selon le format (un duo occupe 2 places).
function Matchmaking.ticketSize(format: Format): number
	return if format == "duo" then 2 else 1
end

function Matchmaking.isPlatform(value: any): boolean
	return type(value) == "string" and table.find(Config.Matchmaking.platforms, value) ~= nil
end

--[[
	Groupe de plateformes d'un ticket. Retourne aussi `forced` : vrai quand
	le crossplay est imposé (duo de deux plateformes différentes).
]]
function Matchmaking.platformGroup(crossplay: boolean, platforms: { Platform }): (string, boolean)
	local first = platforms[1]
	for _, platform in platforms do
		if platform ~= first then
			return "crossplay", true
		end
	end
	if crossplay or first == nil then
		return "crossplay", false
	end
	return first, false
end

function Matchmaking.queueKey(modeId: string, format: Format, group: string): string
	return `{modeId}:{format}:{group}`
end

-- SE d'un profil au départ : objets équipés, sac préparé et objet temporaire (4.2).
function Matchmaking.profileScore(profile: Types.Profile): number
	local bag = profile.bag
	if profile.tempItem then
		bag = table.clone(bag)
		table.insert(bag, profile.tempItem)
	end
	return ItemRules.equipmentScore(profile.loadout, bag)
end

function Matchmaking.memberOf(profile: Types.Profile): Member
	return {
		level = profile.level,
		score = Matchmaking.profileScore(profile),
		pendingLoot = #profile.pendingLoot,
	}
end

--[[
	Un joueur peut-il partir dans ce mode ? Retourne nil si oui, sinon la
	raison du refus et ses paramètres (affichés tels quels : « SE trop
	élevé : 2 450 / 2 000 max »).
]]
function Matchmaking.refusal(member: Member, modeId: string): Refusal?
	local mode = Config.Modes.byId[modeId]
	if mode == nil then
		return { reason = "unknown_mode" }
	end
	local required = Config.Progression.minLevelToPlay
	if Config.Matchmaking.levelGateEnabled and member.level < required then
		return { reason = "level", params = { level = member.level, required = required } }
	end
	if member.pendingLoot > 0 then
		return { reason = "pending_loot", params = { count = member.pendingLoot } }
	end
	if member.score < mode.minScore then
		return { reason = "score_too_low", params = { score = member.score, min = mode.minScore } }
	end
	if mode.maxScore ~= nil and member.score > mode.maxScore then
		return { reason = "score_too_high", params = { score = member.score, max = mode.maxScore } }
	end
	return nil
end

-- Un ticket est-il cohérent (format, taille, joueurs distincts) ?
function Matchmaking.isValidTicket(ticket: any): boolean
	if type(ticket) ~= "table" or type(ticket.id) ~= "string" or type(ticket.userIds) ~= "table" then
		return false
	end
	if ticket.format ~= "solo" and ticket.format ~= "duo" then
		return false
	end
	if Config.Modes.byId[ticket.modeId] == nil or type(ticket.joinedAt) ~= "number" then
		return false
	end
	local expected = if ticket.format == "duo" and ticket.fill == true then 1 else Matchmaking.ticketSize(ticket.format)
	if #ticket.userIds ~= expected then
		return false
	end
	local seen = {}
	for _, userId in ticket.userIds do
		if type(userId) ~= "number" or seen[userId] then
			return false
		end
		seen[userId] = true
	end
	return true
end

export type ComposeOptions = {
	now: number,
	matchSize: number,
	fillTimeout: number,
	minPlayers: number,
}

--[[
	Compose une partie à partir des tickets d'UNE file, du plus ancien au plus
	récent. Retourne nil s'il faut encore attendre.
	- Plein (16 places) : départ immédiat.
	- Sinon, dès que le plus ancien ticket a attendu `fillTimeout` : départ
	  avec les joueurs présents (au moins `minPlayers`) et des mercenaires IA.
	- Duo aléatoire : les joueurs seuls sont appariés deux à deux, dans
	  l'ordre d'arrivée ; chaque équipe occupe 2 places.
	Un joueur présent dans deux tickets n'est retenu qu'une fois.
]]
function Matchmaking.compose(tickets: { Ticket }, options: ComposeOptions): Composition?
	local sorted = table.clone(tickets)
	table.sort(sorted, function(a, b)
		if a.joinedAt ~= b.joinedAt then
			return a.joinedAt < b.joinedAt
		end
		return a.id < b.id
	end)
	local chosen: { Ticket } = {}
	local teams: { { number } } = {}
	local slots, players = 0, 0
	local taken: { [number]: boolean } = {}
	local waitingTeam: { number }? = nil -- joueur seul en attente d'un coéquipier
	for _, ticket in sorted do
		if slots >= options.matchSize and waitingTeam == nil then
			break
		end
		if not Matchmaking.isValidTicket(ticket) then
			continue
		end
		local duplicate = false
		for _, userId in ticket.userIds do
			if taken[userId] then
				duplicate = true
			end
		end
		if duplicate then
			continue
		end
		local lone = ticket.format == "duo" and ticket.fill == true
		local open = waitingTeam
		if lone and open then
			-- Coéquipier trouvé : la place était déjà réservée.
			table.insert(open, ticket.userIds[1])
			waitingTeam = nil
		else
			local size = Matchmaking.ticketSize(ticket.format)
			if slots + size > options.matchSize then
				continue
			end
			slots += size
			local team = table.clone(ticket.userIds)
			table.insert(teams, team)
			if lone then
				waitingTeam = team
			end
		end
		for _, userId in ticket.userIds do
			taken[userId] = true
		end
		table.insert(chosen, ticket)
		players += #ticket.userIds
	end
	if #chosen == 0 then
		return nil
	end
	if players == options.matchSize then
		return { tickets = chosen, teams = teams, players = players, bots = 0, full = true }
	end
	local oldest = chosen[1].joinedAt
	if options.now - oldest >= options.fillTimeout and players >= options.minPlayers then
		return {
			tickets = chosen,
			teams = teams,
			players = players,
			bots = options.matchSize - players,
			full = false,
		}
	end
	return nil
end

-- Faut-il proposer de basculer en crossplay (attente trop longue) ?
function Matchmaking.suggestCrossplay(group: string, waited: number, forced: boolean): boolean
	return group ~= "crossplay" and not forced and waited >= Config.Matchmaking.queue.crossplaySuggestAfter
end

-- Équipes de mercenaires IA pour compléter une partie (des paires en duo).
function Matchmaking.botTeams(format: Format, bots: number): { number }
	local size = Matchmaking.ticketSize(format)
	local teams = {}
	local remaining = math.max(0, bots)
	while remaining > 0 do
		local count = math.min(size, remaining)
		table.insert(teams, count)
		remaining -= count
	end
	return teams
end

return Matchmaking
