--!nocheck
-- Règles de partie : chronologie, extraction, score, top 10, rangs, saisons.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local MatchRules = H.require("ReplicatedStorage/Shared/Match/MatchRules")

	describe("Chronologie", function()
		it("alerte à 12:00, dernière minute à 14:00, Purge à 15:00", function()
			expect(MatchRules.phase(0)).toBe("normal")
			expect(MatchRules.phase(719)).toBe("normal")
			expect(MatchRules.phase(720)).toBe("alert")
			expect(MatchRules.phase(840)).toBe("final")
			expect(MatchRules.phase(900)).toBe("purge")
			expect(MatchRules.remaining(890)).toBe(10)
			expect(MatchRules.remaining(1000)).toBe(0)
		end)
	end)

	describe("Extraction", function()
		it("30 s dans la zone", function()
			local progress, status = 0, nil
			for _ = 1, 29 do
				progress, status = MatchRules.stepExtraction(progress, 1, 1, 1, 0)
			end
			expect(status).toBe("running")
			progress, status = MatchRules.stepExtraction(progress, 1, 1, 1, 0)
			expect(status).toBe("done")
		end)

		it("pause si un coéquipier vivant est dehors, sans retour à zéro", function()
			local progress = MatchRules.stepExtraction(0, 10, 2, 2, 0)
			local paused, status = MatchRules.stepExtraction(progress, 5, 1, 2, 0)
			expect(status).toBe("paused")
			expect(paused).toBe(10)
		end)

		it("bloquée tant qu'un ennemi est dans la zone", function()
			local progress, status = MatchRules.stepExtraction(12, 5, 1, 1, 1)
			expect(status).toBe("blocked")
			expect(progress).toBe(12)
		end)

		it("seul survivant du duo : extraction seul", function()
			local _, status = MatchRules.stepExtraction(0, 1, 1, 1, 0)
			expect(status).toBe("running")
		end)

		it("personne dans la zone : rien ne bouge", function()
			local progress, status = MatchRules.stepExtraction(7, 1, 0, 2, 3)
			expect(status).toBe("idle")
			expect(progress).toBe(7)
		end)
	end)

	describe("Score", function()
		local stats = { playerKills = 2, botKills = 1, robotPoints = 90, lootValue = 3000 }

		it("formule du document, mode Moyen", function()
			local s = MatchRules.score(stats, "medium", true)
			-- (200 + 50 + 90 + 300) × 1,5 = 960
			expect(s.total).toBe(960)
			expect(s.loot).toBe(300)
		end)

		it("mort sans extraction : loot à 0 et score divisé par 2", function()
			local s = MatchRules.score(stats, "medium", false)
			-- (200 + 50 + 90) × 1,5 / 2 = 255
			expect(s.total).toBe(255)
			expect(s.loot).toBe(0)
			expect(s.deathPenalty).toBe(true)
		end)

		it("multiplicateur Difficile ×2,5", function()
			expect(
				MatchRules.score({ playerKills = 1, botKills = 0, robotPoints = 0, lootValue = 0 }, "hard", true).total
			).toBe(250)
		end)
	end)

	describe("Top 10 de saison", function()
		it("insère, trie et remplace la plus faible", function()
			local top = {}
			for i = 1, 10 do
				table.insert(top, { score = i * 100, mode = "easy", date = i })
			end
			local newTop, position = MatchRules.insertTopGame(top, { score = 750, mode = "hard", date = 99 })
			expect(#newTop).toBe(10)
			expect(position).toBe(4) -- NOUVEAU RECORD #4
			expect(newTop[10].score).toBe(200) -- 100 a été remplacé
			local _, none = MatchRules.insertTopGame(newTop, { score = 150, mode = "easy", date = 100 })
			expect(none).toBeNil()
		end)

		it("score de classement et rangs", function()
			expect(MatchRules.rankingScore({ { score = 1500 }, { score = 600 } })).toBe(2100)
			expect(MatchRules.rank(0)).toBe("scrap")
			expect(MatchRules.rank(2100)).toBe("copper")
			expect(MatchRules.rank(30000)).toBe("plasma")
		end)

		it("saisons de 8 semaines", function()
			local Config = H.require("ReplicatedStorage/Shared/Config")
			local start = Config.Progression.season.firstSeasonStartUnix
			expect(MatchRules.seasonAt(start - 1)).toBe(0)
			expect(MatchRules.seasonAt(start)).toBe(1)
			expect(MatchRules.seasonAt(start + 8 * 7 * 86400)).toBe(2)
		end)
	end)

	describe("Crédits de fin de partie", function()
		local Config = H.require("ReplicatedStorage/Shared/Config")
		local C = Config.Progression.credits

		it("l'extraction paie nettement mieux que la mort ; l'abandon ne paie rien", function()
			local extracted = MatchRules.matchCredits(400, true, false)
			expect(extracted).toBe(math.floor(C.participation + 400 * C.scoreShare + C.extractionBonus))
			-- Même partie, mais morte : le score est déjà divisé par 2 par la pénalité de mort.
			local died = MatchRules.matchCredits(200, false, false)
			expect(extracted >= died * 4).toBe(true)
			expect(died > 0).toBe(true)
			expect(MatchRules.matchCredits(400, true, true)).toBe(0)
			-- Partie sans rien : la participation seule.
			expect(MatchRules.matchCredits(0, true, false)).toBe(C.participation + C.extractionBonus)
			expect(MatchRules.matchCredits(-50, false, false)).toBe(math.floor(C.participation * C.deathShare))
		end)

		it("plafonné par partie, et cohérent avec la caisse gratuite", function()
			expect(MatchRules.matchCredits(10_000_000, true, false)).toBe(C.maxPerMatch)
			-- Une partie extraite moyenne rapporte de l'ordre d'une à deux caisses gratuites (50 à 300 cr).
			local typical = MatchRules.matchCredits(400, true, false)
			expect(typical >= 150 and typical <= 600).toBe(true)
		end)
	end)

	describe("Réanimation en duo (ReviveRules)", function()
		local roblox = require("@lune/roblox")
		local Vector3, CFrame = roblox.Vector3, roblox.CFrame
		local ReviveRules = H.require("ReplicatedStorage/Shared/Match/ReviveRules")
		local Config = H.require("ReplicatedStorage/Shared/Config")
		local R = Config.Combat.revive

		local function spot(x)
			local position = Vector3.new(x, 0, 0)
			return { position = position, cframe = CFrame.new(position) }
		end

		it("réglages de la spécification : orbe 1:30 et 100 PV, dépôt 5 s, réanimé à 50 PV", function()
			expect(R.orbLifetime).toBe(90)
			expect(R.orbHealth).toBe(100)
			expect(R.channelTime).toBe(5)
			expect(R.reviveHealth).toBe(50)
			expect(R.acceleratorMinDistance).toBe(80)
			expect(R.acceleratorMaxDistance).toBe(200)
		end)

		it("Accélérateur : tiré parmi les emplacements à 80–200 studs, jamais hors plage s'il y en a", function()
			local spots = { spot(30), spot(79), spot(80), spot(150), spot(200), spot(201), spot(260) }
			local random = H.FakeRandom.new(7)
			local seen = {}
			for _ = 1, 200 do
				local x = ReviveRules.chooseSpot(spots, Vector3.new(0, 0, 0), random).Position.X
				expect(x >= 80 and x <= 200).toBe(true)
				seen[x] = true
			end
			-- Le tirage couvre toute la plage (pas toujours le même emplacement).
			expect(seen[80] and seen[150] and seen[200]).toBe(true)
		end)

		it(
			"aucun emplacement dans la plage : le plus proche de la plage ; carte sans emplacement : 80 studs",
			function()
				local death = Vector3.new(0, 0, 0)
				expect(ReviveRules.chooseSpot({ spot(20), spot(60) }, death, H.FakeRandom.new(1)).Position.X).toBe(60)
				expect(ReviveRules.chooseSpot({ spot(20), spot(230) }, death, H.FakeRandom.new(1)).Position.X).toBe(230)
				expect(ReviveRules.chooseSpot({}, death, H.FakeRandom.new(1)).Position.X).toBe(R.acceleratorMinDistance)
			end
		)

		it("dépôt : maintien d'environ 5 s exigé (marge de latence), à portée de la base", function()
			expect(ReviveRules.channelComplete(R.channelTime)).toBe(true)
			expect(ReviveRules.channelComplete(R.channelTime * 0.85)).toBe(true)
			expect(ReviveRules.channelComplete(R.channelTime * 0.5)).toBe(false)
			expect(ReviveRules.channelComplete(0)).toBe(false)
			local reach = Config.Match.revive.acceleratorDistance
			expect(ReviveRules.inReach(reach)).toBe(true)
			expect(ReviveRules.inReach(reach + 4)).toBe(true)
			expect(ReviveRules.inReach(reach + 10)).toBe(false)
		end)
	end)

	describe("Une partie locale à la fois (MatchLifecycle)", function()
		local MatchLifecycle = H.require("ReplicatedStorage/Shared/Match/MatchLifecycle")

		it("refuse de démarrer pendant une partie ET pendant le retour de ses joueurs", function()
			local lc = MatchLifecycle.new()
			expect((MatchLifecycle.canStart(lc))).toBe(true)
			expect(MatchLifecycle.start(lc, "A", 900)).toBe(true)
			local ok, reason = MatchLifecycle.canStart(lc)
			expect(ok).toBe(false)
			expect(reason).toBe("running")
			expect(MatchLifecycle.start(lc, "B", 900)).toBe(false)
			local batch = MatchLifecycle.finish(lc, { "ada", "bo" }, 1020)
			ok, reason = MatchLifecycle.canStart(lc)
			expect(ok).toBe(false)
			expect(reason).toBe("returning") -- la carte de B se chargerait sous les pieds de A
			expect(MatchLifecycle.complete(lc, batch)).toBe(true)
			expect((MatchLifecycle.canStart(lc))).toBe(true)
		end)

		it("le retour des joueurs survit à ce qui arrive pendant le délai (partie suivante comprise)", function()
			local lc = MatchLifecycle.new()
			MatchLifecycle.start(lc, "A", 900)
			local players = { "ada", "bo" }
			local batch = MatchLifecycle.finish(lc, players, 1020)
			-- La table des participants est vidée et remplie par une autre partie…
			table.clear(players)
			table.insert(players, "cyd")
			lc.phase, lc.matchId = "running", "B" -- démarrage forcé (outil de test)
			-- …le retour concerne toujours les joueurs de A, sans toucher au monde de B.
			expect(batch.players[1]).toBe("ada")
			expect(batch.players[2]).toBe("bo")
			expect(#batch.players).toBe(2)
			expect(MatchLifecycle.complete(lc, batch)).toBe(false) -- carte et butin de B intacts
			expect(lc.phase).toBe("running")
			expect(lc.matchId).toBe("B")
		end)

		it("fin sans partie en cours : rien à ramener ; attente estimée pour la file", function()
			local lc = MatchLifecycle.new()
			expect(MatchLifecycle.finish(lc, { "ada" }, 10)).toBeNil()
			expect(MatchLifecycle.waitEstimate(lc, 0, 20)).toBeNil()
			MatchLifecycle.start(lc, "A", 900)
			expect(MatchLifecycle.waitEstimate(lc, 300, 20)).toBe(620) -- reste de la partie + retour
			MatchLifecycle.finish(lc, { "ada" }, 920)
			expect(MatchLifecycle.waitEstimate(lc, 910, 20)).toBe(10)
			expect(MatchLifecycle.waitEstimate(lc, 999, 20)).toBe(0)
		end)
	end)
end
