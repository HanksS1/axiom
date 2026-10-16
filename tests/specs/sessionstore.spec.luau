--!nocheck
-- Verrouillage de session : aucun profil ne doit être ouvert sur deux serveurs.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local SessionStore = H.require("ServerScriptService/Server/Data/SessionStore")
	local MockDataStore = H.require("ServerScriptService/Server/Data/MockDataStore")

	local clock = 1000
	local counter = 0
	-- Appelé à chaque attente d'un serveur simulé (pour reprendre une écriture suspendue).
	local onWait = nil

	local function makeServer(store, jobId, events)
		return SessionStore.new({
			store = store,
			jobId = jobId,
			placeId = 1,
			now = function()
				return clock
			end,
			wait = function(seconds)
				clock += seconds
				if onWait then
					onWait()
				end
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
			event = if events
				then function(name, fields)
					table.insert(events, { name = name, fields = fields })
				end
				else nil,
		})
	end

	local function find(events, name, result)
		for _, e in events do
			if e.name == name and (result == nil or e.fields.result == result) then
				return e.fields
			end
		end
		return nil
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

	describe("SessionStore : journal et arrêt du serveur (retours en arrière)", function()
		it("chaque écriture numérote l'enregistrement ; le numéro suit le profil d'un serveur à l'autre", function()
			local db = MockDataStore.new()
			local events = {}
			local serverA = makeServer(db, "A", events)
			local session = serverA:acquire("seq_1", 101)
			expect(find(events, "load", "new").seq).toBe(0)
			serverA:save(session, false)
			serverA:save(session, false)
			serverA:save(session, true)
			local released = find(events, "save", "ok")
			expect(released.jobId).toBe("A")
			expect(db:GetAsync("seq_1").meta.seq).toBe(3)
			expect(db:GetAsync("seq_1").meta.jobId).toBe("A")
			local eventsB = {}
			local serverB = makeServer(db, "B", eventsB)
			serverB:acquire("seq_1", 101)
			-- Un retour en arrière se lirait ici : seq chargé < seq de la dernière libération.
			local load = find(eventsB, "load", "acquired")
			expect(load.seq).toBe(3)
			expect(load.jobId).toBe("B")
			expect(load.userId).toBe(101)
			expect(type(load.time)).toBe("number")
		end)

		it("verrou périmé repris : le chargement dit qui le détenait et depuis quand", function()
			local db = MockDataStore.new()
			local serverA = makeServer(db, "A")
			local session = serverA:acquire("stale_1", 102)
			session.data.credits = 7
			serverA:save(session, false)
			clock += 601
			local events = {}
			local serverB = makeServer(db, "B", events)
			local taken = serverB:acquire("stale_1", 102)
			expect(taken.data.credits).toBe(7)
			local load = find(events, "load", "acquired")
			expect(load.takeover).toBe("stale")
			expect(load.previousHolder).toBe("A")
			expect(load.lockAge >= 601).toBe(true)
		end)

		it("verrou volé par un autre serveur : perte journalisée, rien n'est écrit", function()
			local db = MockDataStore.new()
			local events = {}
			local serverA = makeServer(db, "A", events)
			local session = serverA:acquire("stolen_1", 103)
			serverA:save(session, false)
			clock += 601
			makeServer(db, "B"):acquire("stolen_1", 103)
			session.data.credits = 5000
			local ok, err = serverA:save(session, false)
			expect(ok).toBe(false)
			expect(err).toBe("lost")
			local lost = find(events, "lock.lost")
			expect(lost.holder).toBe("B")
			expect(lost.jobId).toBe("A")
			expect(db:GetAsync("stolen_1").data.credits).toBe(0)
		end)

		it("échec de sauvegarde : chaque tentative et l'échec final sont journalisés, seq inchangé", function()
			local db = MockDataStore.new()
			local events = {}
			local serverA = makeServer(db, "A", events)
			local session = serverA:acquire("fail_1", 104)
			serverA:save(session, false)
			db.failNext = 3
			local ok, err = serverA:save(session, false)
			expect(ok).toBe(false)
			expect(err).toBe("error")
			local retries = 0
			for _, e in events do
				if e.name == "save" and e.fields.result == "retry" then
					retries += 1
					expect(string.find(e.fields.error, "panne simulée", 1, true) ~= nil).toBe(true)
				end
			end
			expect(retries).toBe(3)
			local final = find(events, "save", "error")
			expect(final.attempts).toBe(3)
			expect(final.seq).toBe(1)
			expect(session.seq).toBe(1)
		end)

		it("tentatives de chargement épuisées : jamais de profil neuf, abandon journalisé", function()
			local db = MockDataStore.new()
			local serverA = makeServer(db, "A")
			local held = serverA:acquire("busy_1", 105)
			held.data.credits = 900
			serverA:save(held, false)
			local events = {}
			local serverB = makeServer(db, "B", events)
			local session, err = serverB:acquire("busy_1", 105)
			expect(session).toBeNil()
			expect(err).toBe("locked")
			local gaveUp = find(events, "load.gaveup")
			expect(gaveUp.result).toBe("locked")
			expect(gaveUp.attempts).toBe(3)
			expect(find(events, "load", "locked").holder).toBe("A")
			-- L'enregistrement n'a pas été touché (ni écrasé par un profil vierge).
			expect(db:GetAsync("busy_1").data.credits).toBe(900)
			expect(db:GetAsync("busy_1").lock.jobId).toBe("A")
		end)

		it("arrêt du serveur : la libération lancée par le départ du dernier joueur est attendue", function()
			local db = MockDataStore.new()
			local serverA = makeServer(db, "A")
			local session = serverA:acquire("close_1", 106)
			session.data.credits = 321
			-- L'écriture de libération est suspendue en plein UpdateAsync (requête réseau).
			local original = db.UpdateAsync
			local suspended = true
			db.UpdateAsync = function(self, key, transform)
				if suspended then
					coroutine.yield()
				end
				return original(self, key, transform)
			end
			local leaving = coroutine.create(function()
				serverA:save(session, true)
			end)
			coroutine.resume(leaving)
			expect(coroutine.status(leaving)).toBe("suspended")
			-- Fermeture : chaque attente laisse la requête se terminer.
			onWait = function()
				if coroutine.status(leaving) == "suspended" then
					suspended = false
					coroutine.resume(leaving)
				end
			end
			expect(serverA:waitForSaves(5)).toBe(true)
			onWait = nil
			db.UpdateAsync = original
			expect(coroutine.status(leaving)).toBe("dead")
			expect(db:GetAsync("close_1").data.credits).toBe(321)
			expect(db:GetAsync("close_1").lock).toBeNil()
		end)

		it("arrêt du serveur : délai dépassé signalé (false), aucune attente sans écriture en cours", function()
			local db = MockDataStore.new()
			local serverA = makeServer(db, "A")
			expect(serverA:waitForSaves(5)).toBe(true)
			local session = serverA:acquire("close_2", 107)
			local original = db.UpdateAsync
			db.UpdateAsync = function(self, key, transform)
				coroutine.yield() -- requête qui ne revient jamais
				return original(self, key, transform)
			end
			local leaving = coroutine.create(function()
				serverA:save(session, true)
			end)
			coroutine.resume(leaving)
			local before = clock
			expect(serverA:waitForSaves(5)).toBe(false)
			expect(clock - before >= 5).toBe(true)
			db.UpdateAsync = original
		end)
	end)
end
