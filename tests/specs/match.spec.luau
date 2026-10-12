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
end
