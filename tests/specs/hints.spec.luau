--!nocheck
-- Aides contextuelles : règles d'affichage (jamais gênantes) et textes.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local Config = H.require("ReplicatedStorage/Shared/Config")
	local HintRules = H.require("ReplicatedStorage/Shared/Hints/HintRules")
	local Localization = H.require("ReplicatedStorage/Shared/Localization")

	local Hints = Config.Hints

	local function context(overrides)
		local base = { enabled = true, blocked = false, calm = true, gap = Hints.display.gap }
		for key, value in overrides or {} do
			base[key] = value
		end
		return base
	end

	describe("Aides contextuelles", function()
		it("désactivées par le joueur, ou moment inadapté (panneau, mort, tutoriel) : rien", function()
			local state = HintRules.new()
			expect(HintRules.canShow(state, "heal", Hints.hints.heal, 0, context())).toBe(true)
			expect(HintRules.canShow(state, "heal", Hints.hints.heal, 0, context({ enabled = false }))).toBe(false)
			expect(HintRules.canShow(state, "heal", Hints.hints.heal, 0, context({ blocked = true }))).toBe(false)
			expect(HintRules.canShow(state, "inconnue", nil, 0, context())).toBe(false)
		end)

		it("en plein combat : seules les aides urgentes passent", function()
			local state = HintRules.new()
			local fighting = context({ calm = false })
			expect(HintRules.canShow(state, "heal", Hints.hints.heal, 0, fighting)).toBe(true)
			expect(HintRules.canShow(state, "noCells", Hints.hints.noCells, 0, fighting)).toBe(true)
			expect(HintRules.canShow(state, "stance", Hints.hints.stance, 0, fighting)).toBe(false)
			expect(HintRules.canShow(state, "objective", Hints.hints.objective, 0, fighting)).toBe(false)
			expect(HintRules.canShow(state, "stance", Hints.hints.stance, 0, context())).toBe(true)
		end)

		it("une seule aide à la fois, avec un silence entre deux", function()
			local state = HintRules.new()
			local duration, gap = Hints.display.duration, Hints.display.gap
			HintRules.markShown(state, "heal", 100, duration)
			expect(HintRules.canShow(state, "battery", Hints.hints.battery, 100 + duration - 1, context())).toBe(false)
			expect(HintRules.canShow(state, "battery", Hints.hints.battery, 100 + duration + gap - 0.1, context())).toBe(
				false
			)
			expect(HintRules.canShow(state, "battery", Hints.hints.battery, 100 + duration + gap, context())).toBe(true)
		end)

		it("pas de répétition : délai entre deux affichages, puis plus du tout", function()
			local state = HintRules.new()
			local def = Hints.hints.heal
			local time = 0
			for _ = 1, def.maxShows do
				expect(HintRules.canShow(state, "heal", def, time, context())).toBe(true)
				HintRules.markShown(state, "heal", time, Hints.display.duration)
				-- Trop tôt pour la même aide.
				expect(HintRules.canShow(state, "heal", def, time + def.cooldown - 1, context())).toBe(false)
				time += def.cooldown + 1
			end
			expect(HintRules.canShow(state, "heal", def, time + 1000, context())).toBe(false)
		end)

		it("geste accompli par le joueur : l'aide ne revient plus", function()
			local state = HintRules.new()
			HintRules.learn(state, "melee")
			expect(HintRules.canShow(state, "melee", Hints.hints.melee, 0, context())).toBe(false)
			expect(HintRules.canShow(state, "stance", Hints.hints.stance, 0, context())).toBe(true)
		end)

		it("chaque aide a un texte dans les deux langues, et des règles valides", function()
			for id, def in Hints.hints do
				expect(def.maxShows >= 1).toBe(true)
				expect(def.cooldown >= 0).toBe(true)
				for _, language in { "fr", "en" } do
					local text = Localization.get(language, "hint." .. id, { amount = 50, seconds = 30 })
					if text == "hint." .. id or string.find(text, "{", 1, true) then
						error(`texte manquant ou incomplet : hint.{id} ({language}) → {text}`)
					end
				end
			end
		end)

		it("les aides restent brèves et rares", function()
			expect(Hints.display.duration <= 6).toBe(true)
			expect(Hints.display.gap >= 4).toBe(true)
			expect(Hints.tips.maxPerMatch <= 4).toBe(true)
			expect(Config.Settings.hints.default).toBe(true)
		end)
	end)
end
