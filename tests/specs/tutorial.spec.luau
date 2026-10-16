--!nocheck
-- Tutoriel : ordre des étapes, récompense, durée maximale.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local TutorialRules = H.require("ReplicatedStorage/Shared/Progression/TutorialRules")
	local Config = H.require("ReplicatedStorage/Shared/Config")
	local Localization = H.require("ReplicatedStorage/Shared/Localization")

	describe("Tutoriel", function()
		it("six étapes dans l'ordre, puis fin", function()
			local step, seen = "move", { "move" }
			while true do
				local next = TutorialRules.next(step)
				if next == nil then
					break
				end
				table.insert(seen, next)
				step = next
			end
			expect(table.concat(seen, ",")).toBe("move,shoot,parry,loot,heal,extract")
		end)

		it("récompense : niveau 2 minimum, sans baisser un niveau plus haut", function()
			local fresh = { level = 1, xp = 300, tutorialDone = false }
			expect(TutorialRules.complete(fresh)).toBe(true)
			expect(fresh.level).toBe(Config.Progression.tutorial.rewardLevel)
			expect(fresh.xp).toBe(0)
			expect(fresh.level >= Config.Progression.minLevelToPlay).toBe(true) -- peut partir
			local veteran = { level = 14, xp = 900, tutorialDone = true }
			expect(TutorialRules.complete(veteran)).toBe(false)
			expect(veteran.level).toBe(14)
			expect(veteran.xp).toBe(900)
			expect(1 < Config.Progression.minLevelToPlay).toBe(true) -- un nouveau joueur ne peut pas
		end)

		it("5 minutes au maximum", function()
			expect(TutorialRules.timedOut(100, 100 + 299)).toBe(false)
			expect(TutorialRules.timedOut(100, 100 + 300)).toBe(true)
		end)

		it("radio du mentor traduite pour chaque étape", function()
			for _, lang in { "fr", "en" } do
				for _, step in TutorialRules.steps do
					expect(Localization.has(lang, "tutorial.radio." .. step)).toBe(true)
					expect(Localization.has(lang, "tutorial.goal." .. step)).toBe(true)
				end
			end
		end)

		it("le niveau minimum est exigé pour partir", function()
			expect(Config.Matchmaking.levelGateEnabled).toBe(true)
		end)
	end)
end
