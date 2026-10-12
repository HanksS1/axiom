--!nocheck
-- Verrouillage de session : aucun profil ne doit être ouvert sur deux serveurs.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local SessionStore = H.require("ServerScriptService/Server/Data/SessionStore")
	local MockDataStore = H.require("ServerScriptService/Server/Data/MockDataStore")

	local clock = 1000
	local counter = 0

	local function makeServer(store, jobId)
		return SessionStore.new({
			store = store,
			jobId = jobId,
			placeId = 1,
			now = function()
				return clock
			end,
			wait = function(seconds)
				clock += seconds
			end,
			generateId = function()
				counter += 1
				return "session-" .. counter
			end,
			template = function()
				return { credits = 0, vault = {} }
			end,
			lockTimeout = 600,
			loadAttempts = 3,
			loadRetryDelay = 2,
			saveAttempts = 3,
			saveRetryDelay = 1,
			log = function() end,
		})
	end

	describe("SessionStore", function()
		it("crée un nouveau profil et le recharge sans perte", function()
			local db = MockDataStore.new()
			local serverA = makeServer(db, "A")
			local session = serverA:acquire("player_1", 1)
			expect(session ~= nil).toBe(true)
			expect(session.isNew).toBe(true)
			session.data.credits = 250
			table.insert(session.data.vault, { uid = "x", itemId = "vest", condition = 4 })
			expect(serverA:save(session, true)).toBe(true)
			expect(session.active).toBe(false)

			local serverB = makeServer(db, "B")
			local reloaded = serverB:acquire("player_1", 1)
			expect(reloaded.isNew).toBe(false)
			expect(reloaded.data.credits).toBe(250)
			expect(reloaded.data.vault[1].uid).toBe("x")
		end)

		it("refuse un profil verrouillé par un autre serveur", function()
			local db = MockDataStore.new()
			local serverA = makeServer(db, "A")
			local serverB = makeServer(db, "B")
			local session = serverA:acquire("player_2", 2)
			expect(session ~= nil).toBe(true)
			local other, err = serverB:acquire("player_2", 2)
			expect(other).toBeNil()
			expect(err).toBe("locked")
		end)

		it("attend la libération (cas de la téléportation)", function()
			local db = MockDataStore.new()
			local serverA = makeServer(db, "A")
			local serverB = makeServer(db, "B")
			local session = serverA:acquire("player_3", 3)
			-- Le serveur A libère pendant que B réessaie : on simule via le mock.
			local originalUpdate = db.UpdateAsync
			local calls = 0
			db.UpdateAsync = function(self, key, transform)
				calls += 1
				if calls == 2 then
					serverA:save(session, true)
				end
				return originalUpdate(self, key, transform)
			end
			local reloaded = serverB:acquire("player_3", 3)
			db.UpdateAsync = originalUpdate
			expect(reloaded ~= nil).toBe(true)
		end)

		it("reprend un verrou abandonné (serveur planté)", function()
			local db = MockDataStore.new()
			local serverA = makeServer(db, "A")
			local serverB = makeServer(db, "B")
			local session = serverA:acquire("player_4", 4)
			session.data.credits = 42
			serverA:save(session, false)
			clock += 601
			local stolen = serverB:acquire("player_4", 4)
			expect(stolen ~= nil).toBe(true)
			expect(stolen.data.credits).toBe(42)

			-- L'ancien serveur ne peut plus écrire : la session est perdue.
			session.data.credits = 999999
			local ok, err = serverA:save(session, false)
			expect(ok).toBe(false)
			expect(err).toBe("lost")
			expect(session.active).toBe(false)
			expect(db:GetAsync("player_4").data.credits).toBe(42)
		end)

		it("rafraîchit le verrou à chaque sauvegarde", function()
			local db = MockDataStore.new()
			local serverA = makeServer(db, "A")
			local serverB = makeServer(db, "B")
			local session = serverA:acquire("player_5", 5)
			for _ = 1, 5 do
				clock += 300
				expect(serverA:save(session, false)).toBe(true)
			end
			local other, err = serverB:acquire("player_5", 5)
			expect(other).toBeNil()
			expect(err).toBe("locked")
		end)

		it("réessaie après une panne du DataStore", function()
			local db = MockDataStore.new()
			local serverA = makeServer(db, "A")
			db.failNext = 2
			local session = serverA:acquire("player_6", 6)
			expect(session ~= nil).toBe(true)
			db.failNext = 2
			expect(serverA:save(session, false)).toBe(true)
			db.failNext = 5
			local ok, err = serverA:save(session, false)
			expect(ok).toBe(false)
			expect(err).toBe("error")
			-- Une panne n'invalide pas la session : la suivante réussit.
			expect(session.active).toBe(true)
			expect(serverA:save(session, true)).toBe(true)
		end)

		it("ne réécrit jamais un enregistrement corrompu", function()
			local db = MockDataStore.new()
			db:SetRaw("player_7", "corrompu")
			local serverA = makeServer(db, "A")
			local session, err = serverA:acquire("player_7", 7)
			expect(session).toBeNil()
			expect(err).toBe("error")
			expect(db:GetAsync("player_7")).toBe("corrompu")
		end)

		it("le même serveur reprend son propre verrou orphelin", function()
			local db = MockDataStore.new()
			local serverA = makeServer(db, "A")
			local session = serverA:acquire("player_8", 8)
			-- La libération échoue (panne), la session locale est fermée.
			db.failNext = 3
			local ok = serverA:save(session, true)
			expect(ok).toBe(false)
			expect(session.active).toBe(false)
			-- Le joueur revient sur le même serveur : pas d'attente de 10 minutes.
			local again = serverA:acquire("player_8", 8)
			expect(again ~= nil).toBe(true)
		end)

		it("une sauvegarde n'écrit pas une référence vivante", function()
			local db = MockDataStore.new()
			local serverA = makeServer(db, "A")
			local session = serverA:acquire("player_9", 9)
			session.data.credits = 10
			serverA:save(session, false)
			session.data.credits = 20
			expect(db:GetAsync("player_9").data.credits).toBe(10)
		end)
	end)
end
