--!strict
--[[
	MatchStore : données de matchmaking partagées entre serveurs
	(MemoryStoreService, section 16.3).

	- File par combinaison (mode, format, groupe de plateformes) : SortedMap,
	  clé = ticket, tri = heure d'entrée (le plus ancien d'abord). Un ticket
	  non rafraîchi expire (hub planté).
	- Verrou par file : un seul hub fait le matchmaking d'une file à la fois.
	- Affectations : ticket → serveur réservé (code d'accès), lues par le
	  hub du ticket qui téléporte ses joueurs.
	- Descriptions de partie : identifiant du serveur privé → mode, format,
	  équipes et mercenaires. Lues par le serveur de partie (jamais par les
	  données de téléportation, que le client pourrait falsifier).
	- Compteurs de file (« 11 / 16 joueurs ») publiés par le matchmaker.

	Toutes les fonctions peuvent céder la main et ne lèvent jamais d'erreur :
	un échec renvoie nil / false et laisse la boucle réessayer.
]]

local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Matchmaking = require(Shared.Match.Matchmaking)

local Queue = Config.Matchmaking.queue

local MatchStore = {}

export type Assignment = {
	accessCode: string,
	placeId: number,
	matchId: string,
}

export type MatchConfig = {
	matchId: string,
	modeId: string,
	format: Matchmaking.Format,
	teams: { { number } },
	bots: number,
	createdAt: number,
	mapId: string?, -- carte tirée par le matchmaker
}

export type QueueStats = {
	players: number,
	oldest: number?,
}

local maps: { [string]: any } = {}

local function map(name: string): any
	local existing = maps[name]
	if existing == nil then
		existing = MemoryStoreService:GetSortedMap(name)
		maps[name] = existing
	end
	return existing
end

-- Les clés d'une file ne contiennent que des caractères sûrs (mode:format:groupe).
local function queueMap(key: string): any
	return map("AxiomQueue_" .. key)
end

local function call(label: string, fn: () -> ...any): (boolean, any)
	local ok, result = pcall(fn)
	if not ok then
		warn(`[MatchStore] {label} : {result}`)
		return false, nil
	end
	return true, result
end

function MatchStore.addTicket(key: string, ticket: Matchmaking.Ticket): boolean
	local ok = call("addTicket", function()
		queueMap(key):SetAsync(ticket.id, ticket, Queue.ticketExpiry, ticket.joinedAt)
	end)
	return ok
end

-- Prolonge un ticket encore présent (ne recrée jamais un ticket retiré).
function MatchStore.refreshTicket(key: string, ticketId: string): boolean
	local ok, result = call("refreshTicket", function()
		return queueMap(key):UpdateAsync(ticketId, function(current: any, sortKey: any)
			if current == nil then
				return nil
			end
			return current, sortKey
		end, Queue.ticketExpiry)
	end)
	return ok and result ~= nil
end

function MatchStore.removeTicket(key: string, ticketId: string)
	call("removeTicket", function()
		queueMap(key):RemoveAsync(ticketId)
	end)
end

-- Tickets valides d'une file, du plus ancien au plus récent.
function MatchStore.readTickets(key: string): { Matchmaking.Ticket }?
	local ok, entries = call("readTickets", function()
		return queueMap(key):GetRangeAsync(Enum.SortDirection.Ascending, Queue.readBatch)
	end)
	if not ok or type(entries) ~= "table" then
		return nil
	end
	local tickets = {}
	for _, entry in entries :: any do
		local ticket = entry.value
		if Matchmaking.isValidTicket(ticket) and ticket.id == entry.key then
			table.insert(tickets, ticket)
		end
	end
	return tickets
end

-- Verrou de matchmaking d'une file (renouvelé par son détenteur).
function MatchStore.tryLock(key: string, owner: string): boolean
	local now = os.time()
	local ok, result = call("tryLock", function()
		return map("AxiomQueueLocks"):UpdateAsync(key, function(current: any): any
			if type(current) == "table" and current.owner ~= owner and (current.expires or 0) > now then
				return nil
			end
			return { owner = owner, expires = now + Queue.lockDuration }
		end, Queue.lockDuration)
	end)
	return ok and type(result) == "table" and result.owner == owner
end

function MatchStore.writeAssignment(ticketId: string, assignment: Assignment): boolean
	local ok = call("writeAssignment", function()
		map("AxiomAssignments"):SetAsync(ticketId, assignment, Queue.assignmentExpiry)
	end)
	return ok
end

function MatchStore.readAssignment(ticketId: string): Assignment?
	local ok, value = call("readAssignment", function()
		return map("AxiomAssignments"):GetAsync(ticketId)
	end)
	if not ok or type(value) ~= "table" then
		return nil
	end
	local assignment = value :: any
	if type(assignment.accessCode) ~= "string" or type(assignment.placeId) ~= "number" then
		return nil
	end
	return assignment
end

function MatchStore.removeAssignment(ticketId: string)
	call("removeAssignment", function()
		map("AxiomAssignments"):RemoveAsync(ticketId)
	end)
end

function MatchStore.writeMatch(serverId: string, config: MatchConfig): boolean
	local ok = call("writeMatch", function()
		map("AxiomMatches"):SetAsync(serverId, config, Config.Matchmaking.matchServer.configExpiry)
	end)
	return ok
end

function MatchStore.readMatch(serverId: string): MatchConfig?
	local ok, value = call("readMatch", function()
		return map("AxiomMatches"):GetAsync(serverId)
	end)
	if not ok or type(value) ~= "table" then
		return nil
	end
	local config = value :: any
	if Config.Modes.byId[config.modeId] == nil or type(config.teams) ~= "table" then
		return nil
	end
	if config.format ~= "solo" and config.format ~= "duo" then
		return nil
	end
	if config.mapId ~= nil and Config.Maps.byId[config.mapId] == nil then
		config.mapId = nil -- carte inconnue : tirage au hasard sur le serveur de partie
	end
	return config
end

function MatchStore.writeStats(key: string, stats: QueueStats)
	call("writeStats", function()
		map("AxiomQueueStats"):SetAsync(key, stats, Queue.lockDuration * 3)
	end)
end

function MatchStore.readStats(key: string): QueueStats?
	local ok, value = call("readStats", function()
		return map("AxiomQueueStats"):GetAsync(key)
	end)
	if ok and type(value) == "table" and type((value :: any).players) == "number" then
		return value :: any
	end
	return nil
end

return MatchStore
