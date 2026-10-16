--!nocheck
-- File partagée entre hubs (MemoryStore simulé) : tickets, verrou, affectations, parties.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local MockMemoryStore = require("../lib/MockMemoryStore")
	local store = MockMemoryStore.new()
	H.setService("MemoryStoreService", store)
	local MatchStore = H.require("ServerScriptService/Server/Matchmaking/MatchStore")
	local Config = H.require("ReplicatedStorage/Shared/Config")
	local Queue = Config.Matchmaking.queue

	local function ticket(id, joinedAt, overrides)
		local t = {
			id = id,
			userIds = { #id * 1000 + joinedAt },
			modeId = "easy",
			format = "solo",
			group = "keyboard",
			joinedAt = joinedAt,
			hubJobId = "hub-1",
		}
		for k, v in overrides or {} do
			t[k] = v
		end
		return t
	end

	local function reset()
		store.now = 0
		store.failing = false
		store.maps = {}
	end

	describe("Tickets de file", function()
		it("lus du plus ancien au plus récent ; un ticket invalide est ignoré", function()
			reset()
			expect(MatchStore.addTicket("easy:solo:keyboard", ticket("b", 20))).toBe(true)
			MatchStore.addTicket("easy:solo:keyboard", ticket("a", 10))
			-- Ticket corrompu (mode inconnu) et ticket dont la clé ne correspond pas.
			MatchStore.addTicket("easy:solo:keyboard", ticket("x", 5, { modeId = "nightmare" }))
			store:GetSortedMap("AxiomQueue_easy:solo:keyboard"):SetAsync("y", ticket("z", 6), 60, 6)
			local tickets = MatchStore.readTickets("easy:solo:keyboard")
			expect(#tickets).toBe(2)
			expect(tickets[1].id).toBe("a")
			expect(tickets[2].id).toBe("b")
		end)

		it("un ticket non rafraîchi expire ; rafraîchir ne recrée jamais un ticket retiré", function()
			reset()
			MatchStore.addTicket("q", ticket("a", 1))
			MatchStore.addTicket("q", ticket("b", 2))
			MatchStore.removeTicket("q", "b")
			expect(MatchStore.refreshTicket("q", "b")).toBe(false)
			store.now = Queue.ticketExpiry - 1
			expect(MatchStore.refreshTicket("q", "a")).toBe(true) -- prolongé
			store.now = Queue.ticketExpiry + 10
			expect(#MatchStore.readTickets("q")).toBe(1) -- toujours là grâce au rafraîchissement
			store.now = 3 * Queue.ticketExpiry
			expect(#MatchStore.readTickets("q")).toBe(0) -- hub planté : le ticket disparaît
		end)
	end)

	describe("Verrou de matchmaking", function()
		it("un seul hub à la fois ; le détenteur le renouvelle ; libéré à l'expiration", function()
			reset()
			expect(MatchStore.tryLock("q", "hub-A")).toBe(true)
			expect(MatchStore.tryLock("q", "hub-B")).toBe(false)
			expect(MatchStore.tryLock("q", "hub-A")).toBe(true)
			-- L'entrée expire (hub A planté) : un autre hub reprend la file.
			store.now = Queue.lockDuration + 1
			expect(MatchStore.tryLock("q", "hub-B")).toBe(true)
		end)
	end)

	describe("Affectations et descriptions de partie", function()
		it("affectation lue telle qu'écrite ; données incomplètes refusées", function()
			reset()
			MatchStore.writeAssignment("t1", { accessCode = "code", placeId = 42, matchId = "m1" })
			local assignment = MatchStore.readAssignment("t1")
			expect(assignment.placeId).toBe(42)
			store:GetSortedMap("AxiomAssignments"):SetAsync("t2", { accessCode = 5 }, 60)
			expect(MatchStore.readAssignment("t2")).toBeNil()
			MatchStore.removeAssignment("t1")
			expect(MatchStore.readAssignment("t1")).toBeNil()
		end)

		it("description de partie : mode, format et carte vérifiés", function()
			reset()
			local base =
				{ matchId = "m", modeId = "hard", format = "duo", teams = { { 1, 2 } }, bots = 2, createdAt = 0 }
			MatchStore.writeMatch("s1", base)
			expect(MatchStore.readMatch("s1").modeId).toBe("hard")
			MatchStore.writeMatch("s2", table.clone(base))
			store
				:GetSortedMap("AxiomMatches")
				:SetAsync("s3", { matchId = "m", modeId = "??", format = "duo", teams = {} }, 60)
			expect(MatchStore.readMatch("s3")).toBeNil()
			local unknownMap = table.clone(base)
			unknownMap.mapId = "atlantis"
			MatchStore.writeMatch("s4", unknownMap)
			expect(MatchStore.readMatch("s4").mapId).toBeNil() -- carte inconnue : tirage sur place
			local badFormat = table.clone(base)
			badFormat.format = "trio"
			MatchStore.writeMatch("s5", badFormat)
			expect(MatchStore.readMatch("s5")).toBeNil()
		end)
	end)

	describe("Pannes du MemoryStore", function()
		it("aucune erreur levée : échec signalé, la boucle réessaiera", function()
			reset()
			store.failing = true
			expect(MatchStore.addTicket("q", ticket("a", 1))).toBe(false)
			expect(MatchStore.readTickets("q")).toBeNil()
			expect(MatchStore.tryLock("q", "hub")).toBe(false)
			expect(MatchStore.readAssignment("t")).toBeNil()
			expect(MatchStore.readMatch("s")).toBeNil()
			expect(MatchStore.readStats("q")).toBeNil()
			store.failing = false
		end)
	end)
end
