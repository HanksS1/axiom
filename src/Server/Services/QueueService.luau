--!strict
--[[
	QueueService : Porte de déploiement et file d'attente (sections 4.2, 16.2, 16.3).

	- Entrée dans la file : le chef du groupe choisit mode, format et crossplay.
	  Chaque membre doit être éligible (SE dans la plage, loot trié, niveau).
	- Dès l'entrée, le SE et l'équipement sont VERROUILLÉS (EconomyService
	  refuse toute action) jusqu'au départ ou à l'annulation.
	- Deux fonctionnements :
	  · en ligne (places configurées) : files partagées entre tous les hubs
	    (MatchStore). Le hub qui obtient le verrou d'une file compose les
	    parties, réserve un serveur et publie les affectations ; chaque hub
	    téléporte ses propres joueurs ;
	  · local (Studio, places non configurées) : la partie se lance sur ce
	    serveur, avec un délai d'attente raccourci.
	- Après 90 s d'attente, la partie part avec les joueurs présents et des
	  mercenaires IA. Hors crossplay, après 60 s, on propose de basculer.
	- Cartes : le chef du groupe coche les cartes acceptées ; la partie part sur
	  une carte acceptée par tous ses joueurs (Matchmaking.compose). Les joueurs
	  en file par carte sont affichés à la Porte (QueueMapCounts).
	- Téléportation échouée : nouvelles tentatives, puis retour au Terminus
	  avec l'équipement intact (le profil est rechargé).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Guard = require(Shared.Util.Guard)
local Matchmaking = require(Shared.Match.Matchmaking)
local Types = require(Shared.Types)
local try = require(Shared.Util.Try)

local MatchStore = require(script.Parent.Parent.Matchmaking.MatchStore)
local PlaceRole = require(script.Parent.Parent.Matchmaking.PlaceRole)
local Teleporter = require(script.Parent.Parent.Matchmaking.Teleporter)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local Uid = require(script.Parent.Parent.Util.Uid)
local DataService = require(script.Parent.DataService)
local MapRuntimeService = require(script.Parent.MapRuntimeService)
local MatchService = require(script.Parent.MatchService)
local PartyService = require(script.Parent.PartyService)
local TutorialService = require(script.Parent.TutorialService)

local MM = Config.Matchmaking

local QueueService = {}

type Entry = {
	ticket: Matchmaking.Ticket,
	key: string,
	members: { Player },
	forced: boolean,
	status: "queued" | "teleporting",
	lastRefresh: number,
	players: number, -- joueurs dans la file (affichage)
	mapCounts: { [string]: number }?, -- joueurs en file par carte (affichage)
}

local entries: { [string]: Entry } = {}
local byPlayer: { [Player]: Entry } = {}
local jobId = if game.JobId ~= "" then game.JobId else "studio"

local function isLocal(): boolean
	return not PlaceRole.teleportsEnabled()
end

-- Joueur en file ou en cours de téléportation : équipement verrouillé.
function QueueService.isLocked(player: Player): boolean
	return byPlayer[player] ~= nil
end

local function sendState(player: Player, state: Types.QueueView)
	if player.Parent == Players then
		ServerNet.fire("QueueState", player, state)
	end
end

local function push(entry: Entry)
	local ticket = entry.ticket
	local waited = os.time() - ticket.joinedAt
	local state: Types.QueueView = {
		status = entry.status,
		modeId = ticket.modeId,
		format = ticket.format,
		group = ticket.group,
		forcedCrossplay = entry.forced,
		players = math.max(entry.players, #ticket.userIds),
		needed = MM.matchSize,
		since = ticket.joinedAt,
		suggestCrossplay = Matchmaking.suggestCrossplay(ticket.group, waited, entry.forced),
		maps = ticket.maps,
		mapCounts = entry.mapCounts,
	}
	for _, member in entry.members do
		sendState(member, state)
	end
end

-- Retire une entrée (annulation, départ, partie locale lancée).
local function drop(entry: Entry, notifyKey: string?, keepRemote: boolean?)
	if entries[entry.ticket.id] ~= entry then
		return
	end
	entries[entry.ticket.id] = nil
	for _, member in entry.members do
		if byPlayer[member] == entry then
			byPlayer[member] = nil
			sendState(member, { status = "idle" })
			if notifyKey and member.Parent == Players then
				ServerNet.notify(member, notifyKey)
			end
		end
	end
	if not isLocal() and not keepRemote then
		task.spawn(MatchStore.removeTicket, entry.key, entry.ticket.id)
	end
end

function QueueService.cancelFor(player: Player, notifyKey: string?)
	local entry = byPlayer[player]
	if entry and entry.status == "queued" then
		drop(entry, notifyKey)
	end
end

local function notifyAll(members: { Player }, key: string, params: { [string]: any }?)
	for _, member in members do
		ServerNet.notify(member, key, params)
	end
end

local function join(player: Player, modeId: string, format: Matchmaking.Format, crossplay: boolean, maps: { string }?)
	if PlaceRole.isMatchServer() then
		return -- la file n'existe qu'au Terminus
	end
	local existing = byPlayer[player]
	if existing and existing.status == "teleporting" then
		return
	end
	local party = PartyService.partyOf(player)
	local members: { Player } = if party then table.clone(party.members) else { player }
	if party and party.leader ~= player then
		ServerNet.notify(player, "queue.refused.not_leader")
		return
	end
	if format == "solo" and #members > 1 then
		ServerNet.notify(player, "queue.refused.leave_party")
		return
	end
	for _, member in members do
		local other = byPlayer[member]
		if other and other ~= existing then
			ServerNet.notify(player, "queue.refused.busy", { name = member.DisplayName })
			return
		end
		if MatchService.participant(member) then
			notifyAll(members, "queue.refused.in_match", { name = member.DisplayName })
			return
		end
		if TutorialService.isInTutorial(member) then
			notifyAll(members, "queue.refused.tutorial", { name = member.DisplayName })
			return
		end
		local profile = DataService.getProfile(member)
		if profile == nil then
			notifyAll(members, "queue.refused.profile", { name = member.DisplayName })
			return
		end
		local refusal = Matchmaking.refusal(Matchmaking.memberOf(profile), modeId)
		if refusal then
			local params = table.clone(refusal.params or {})
			params.name = member.DisplayName
			notifyAll(members, "deploy.refused." .. refusal.reason, params)
			return
		end
	end

	-- Changement de file (ex. bascule en crossplay) : l'ancienneté est conservée.
	local joinedAt = if existing then existing.ticket.joinedAt else os.time()
	if existing then
		drop(existing, nil)
	end
	local platforms: { Matchmaking.Platform } = {}
	for _, member in members do
		table.insert(platforms, PartyService.platformOf(member))
	end
	local group, forced = Matchmaking.platformGroup(crossplay, platforms)
	local userIds = {}
	for _, member in members do
		table.insert(userIds, member.UserId)
	end
	local ticket: Matchmaking.Ticket = {
		id = Uid.new(),
		userIds = userIds,
		-- Duo sans coéquipier : apparié au hasard avec un autre joueur seul.
		fill = if format == "duo" and #userIds == 1 then true else nil,
		modeId = modeId,
		format = format,
		group = group,
		joinedAt = joinedAt,
		hubJobId = jobId,
		maps = Matchmaking.cleanMaps(maps),
	}
	local entry: Entry = {
		ticket = ticket,
		key = Matchmaking.queueKey(modeId, format, group),
		members = members,
		forced = forced,
		status = "queued",
		lastRefresh = os.clock(),
		players = #userIds,
	}
	-- Verrouillage AVANT toute attente réseau.
	entries[ticket.id] = entry
	for _, member in members do
		byPlayer[member] = entry
	end
	push(entry)
	if not isLocal() and not MatchStore.addTicket(entry.key, ticket) then
		drop(entry, "queue.failed")
	end
end

-- Partie trouvée : téléportation des membres présents sur ce serveur.
local function teleport(entry: Entry, assignment: MatchStore.Assignment)
	entries[entry.ticket.id] = nil
	entry.status = "teleporting"
	push(entry)
	local present = {}
	for _, member in entry.members do
		if member.Parent == Players and byPlayer[member] == entry then
			table.insert(present, member)
		end
	end
	if #present == 0 then
		return
	end
	-- Le profil est sauvegardé et libéré avant le départ (19.4).
	for _, member in present do
		DataService.releaseForTeleport(member)
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = assignment.accessCode
	Teleporter.send(present, assignment.placeId, options, function(member)
		if byPlayer[member] == entry then
			byPlayer[member] = nil
		end
		sendState(member, { status = "idle" })
		ServerNet.notify(member, "queue.teleport_failed")
		DataService.reload(member)
	end)
end

-- Partie locale (Studio / places non configurées) : lancée sur ce serveur.
local function startLocal(composition: Matchmaking.Composition)
	local byUserId: { [number]: Player } = {}
	local first = composition.tickets[1]
	for _, ticket in composition.tickets do
		local entry = entries[ticket.id]
		if entry == nil then
			continue
		end
		for _, member in entry.members do
			if member.Parent == Players then
				byUserId[member.UserId] = member
			end
		end
		drop(entry, nil)
	end
	local teams: { { Player } } = {}
	local players: { Player } = {}
	for _, userIds in composition.teams do
		local team = {}
		for _, userId in userIds do
			local member = byUserId[userId]
			if member then
				table.insert(team, member)
				table.insert(players, member)
			end
		end
		if #team > 0 then
			table.insert(teams, team)
		end
	end
	if #players == 0 then
		return
	end
	MatchService.begin({
		modeId = first.modeId,
		format = first.format,
		players = players,
		teams = teams,
		mercenaries = MM.matchSize - #players,
		-- Studio : une carte imposée par le panneau DEV passe avant la sélection.
		mapId = if RunService:IsStudio() and MapRuntimeService.devChoice ~= "random" then nil else composition.mapId,
	})
end

-- Tirage au sort parmi des cartes à égalité.
local function pickIndex(count: number): number
	return math.random(1, count)
end

-- Files en cours de traitement sur CE serveur : le verrou MemoryStore est au nom
-- du serveur, il ne protège pas contre deux passes qui se chevauchent ici.
local busyKeys: { [string]: boolean } = {}

-- Matchmaker en ligne : compose, réserve un serveur, publie les affectations.
local function matchmakeRemote(key: string)
	if not MatchStore.tryLock(key, jobId) then
		return
	end
	local tickets = MatchStore.readTickets(key)
	if tickets == nil then
		return
	end
	local total, oldest = 0, nil :: number?
	for _, ticket in tickets do
		total += #ticket.userIds
		oldest = if oldest then math.min(oldest, ticket.joinedAt) else ticket.joinedAt
	end
	MatchStore.writeStats(key, { players = total, oldest = oldest, maps = Matchmaking.mapCounts(tickets) })
	local composition = Matchmaking.compose(tickets, {
		now = os.time(),
		matchSize = MM.matchSize,
		fillTimeout = MM.queue.fillTimeout,
		minPlayers = MM.queue.minPlayersToStart,
		pick = pickIndex,
	})
	if composition == nil then
		return
	end
	local ok, accessCode, serverId = pcall(function()
		return TeleportService:ReserveServer(MM.places.match)
	end)
	if not ok or type(accessCode) ~= "string" or type(serverId) ~= "string" then
		warn(`[QueueService] réservation de serveur impossible : {accessCode}`)
		return
	end
	local first = composition.tickets[1]
	local teams = composition.teams
	local matchId = Uid.new()
	local written = MatchStore.writeMatch(serverId, {
		matchId = matchId,
		modeId = first.modeId,
		format = first.format,
		teams = teams,
		bots = composition.bots,
		createdAt = os.time(),
		mapId = composition.mapId,
	})
	if not written then
		return
	end
	-- Affectation écrite AVANT le retrait du ticket : un hub qui ne trouve
	-- plus son ticket vérifie d'abord son affectation.
	for _, ticket in composition.tickets do
		MatchStore.writeAssignment(ticket.id, { accessCode = accessCode, placeId = MM.places.match, matchId = matchId })
		MatchStore.removeTicket(key, ticket.id)
	end
end

local function matchmakerLoop()
	while true do
		task.wait(MM.queue.matchmakerInterval)
		local keys: { [string]: { Matchmaking.Ticket } } = {}
		for _, entry in entries do
			if entry.status == "queued" then
				keys[entry.key] = keys[entry.key] or {}
				table.insert(keys[entry.key], entry.ticket)
			end
		end
		for key, tickets in keys do
			if isLocal() then
				local total = 0
				for _, ticket in tickets do
					total += #ticket.userIds
				end
				local counts = Matchmaking.mapCounts(tickets)
				for _, entry in entries do
					if entry.key == key then
						entry.players = total
						entry.mapCounts = counts
					end
				end
				if not MatchService.isRunning() then
					local composition = Matchmaking.compose(tickets, {
						now = os.time(),
						matchSize = MM.matchSize,
						fillTimeout = MM.localFillTimeout,
						minPlayers = MM.queue.minPlayersToStart,
						pick = pickIndex,
					})
					if composition then
						startLocal(composition)
					end
				end
			elseif not busyKeys[key] then
				busyKeys[key] = true
				task.spawn(function()
					local ok, err = try(matchmakeRemote, key)
					busyKeys[key] = nil
					if not ok then
						warn(`[QueueService] matchmaking de {key} : {err}`)
					end
				end)
			end
		end
	end
end

-- Hubs en ligne : affectations, compteurs, maintien des tickets.
local function pollLoop()
	while true do
		task.wait(MM.queue.pollInterval)
		if isLocal() then
			for _, entry in entries do
				push(entry)
			end
			continue
		end
		local statsByKey: { [string]: MatchStore.QueueStats? } = {}
		for _, entry in table.clone(entries) do
			if entry.status ~= "queued" then
				continue
			end
			local assignment = MatchStore.readAssignment(entry.ticket.id)
			if entries[entry.ticket.id] ~= entry then
				continue -- annulé pendant la lecture
			end
			if assignment then
				MatchStore.removeAssignment(entry.ticket.id)
				teleport(entry, assignment)
				continue
			end
			if os.clock() - entry.lastRefresh >= MM.queue.ticketRefresh then
				entry.lastRefresh = os.clock()
				if not MatchStore.refreshTicket(entry.key, entry.ticket.id) then
					-- Ticket expiré sans affectation : on le republie.
					MatchStore.addTicket(entry.key, entry.ticket)
				end
			end
			if statsByKey[entry.key] == nil then
				statsByKey[entry.key] = MatchStore.readStats(entry.key)
			end
			local stats = statsByKey[entry.key]
			if stats then
				entry.players = stats.players
				entry.mapCounts = stats.maps
			end
			push(entry)
		end
	end
end

-- Joueurs en file par carte, pour une file donnée (Porte de déploiement, avant d'entrer).
local countsCache: { [string]: { at: number, counts: { [string]: number } } } = {}

local function mapCountsFor(key: string): { [string]: number }
	if isLocal() then
		local tickets = {}
		for _, entry in entries do
			if entry.key == key and entry.status == "queued" then
				table.insert(tickets, entry.ticket)
			end
		end
		return Matchmaking.mapCounts(tickets)
	end
	local cached = countsCache[key]
	if cached and os.clock() - cached.at < MM.queue.pollInterval then
		return cached.counts
	end
	local stats = MatchStore.readStats(key)
	local counts = if stats and type(stats.maps) == "table" then stats.maps else Matchmaking.mapCounts({})
	countsCache[key] = { at = os.clock(), counts = counts }
	return counts
end

local function sendMapCounts(player: Player, modeId: string, format: Matchmaking.Format, crossplay: boolean)
	local group = Matchmaking.platformGroup(crossplay, { PartyService.platformOf(player) })
	local key = Matchmaking.queueKey(modeId, format, group)
	ServerNet.fire("QueueMapCountsResult", player, modeId, format, mapCountsFor(key))
end

function QueueService.init()
	ServerNet.onEvent(
		"QueueJoin",
		Guard.tuple(
			Guard.keyOf(Config.Modes.byId),
			Guard.enum({ "solo", "duo" }),
			Guard.boolean(),
			Guard.optional(Guard.array(Guard.keyOf(Config.Maps.byId), #Config.Maps.list))
		),
		join
	)
	ServerNet.onEvent(
		"QueueMapCounts",
		Guard.tuple(Guard.keyOf(Config.Modes.byId), Guard.enum({ "solo", "duo" }), Guard.boolean()),
		function(player, modeId: string, format: Matchmaking.Format, crossplay: boolean)
			if not PlaceRole.isMatchServer() then
				sendMapCounts(player, modeId, format, crossplay)
			end
		end
	)
	ServerNet.onEvent("QueueLeave", Guard.tuple(), function(player)
		QueueService.cancelFor(player, "queue.cancelled")
	end)

	-- Un joueur en file ne peut pas rejoindre ou quitter un groupe.
	PartyService.setBusyCheck(function(player)
		return if byPlayer[player] then "party.refused.queued" else nil
	end)
	PartyService.Changed:Connect(function(members)
		for _, member in members do
			QueueService.cancelFor(member, "queue.cancelled.party_changed")
		end
	end)
end

function QueueService.start()
	if PlaceRole.isMatchServer() then
		return
	end
	Players.PlayerRemoving:Connect(function(player)
		local entry = byPlayer[player]
		byPlayer[player] = nil
		if entry and entry.status == "queued" then
			drop(entry, "queue.cancelled.partner_left")
		end
	end)
	task.spawn(matchmakerLoop)
	task.spawn(pollLoop)
end

return QueueService
