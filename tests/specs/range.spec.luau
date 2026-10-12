--!nocheck
-- Stand de tir : défi quotidien identique pour tous.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local RangeRules = H.require("ReplicatedStorage/Shared/Progression/RangeRules")
	local Config = H.require("ReplicatedStorage/Shared/Config")

	describe("Défi quotidien", function()
		it("jour UTC et remise à zéro à minuit", function()
			expect(RangeRules.day(86400 * 3 + 5)).toBe(3)
			expect(RangeRules.nextResetAt(86400 * 3 + 5)).toBe(86400 * 4)
		end)

		it("arme du jour déterministe, tirée de la liste, et qui varie", function()
			local seen = {}
			for day = 20000, 20060 do
				local weapon = RangeRules.weaponOfDay(day)
				expect(weapon).toBe(RangeRules.weaponOfDay(day))
				expect(Config.Weapons.ranged[weapon] ~= nil).toBe(true)
				seen[weapon] = true
			end
			local count = 0
			for _ in seen do
				count += 1
			end
			expect(count >= 4).toBe(true)
		end)

		it("suite de cibles identique pour un même jour, valeurs bornées", function()
			local a, b = RangeRules.targets(20100), RangeRules.targets(20100)
			local c = RangeRules.targets(20101)
			expect(#a).toBe(Config.Range.challenge.sequenceLength)
			local different = false
			for index, spec in a do
				expect(spec.from).toBe(b[index].from)
				expect(spec.speed).toBe(b[index].speed)
				for _, key in { "from", "to", "height", "depth" } do
					expect(spec[key] >= 0 and spec[key] < 1).toBe(true)
				end
				expect(spec.speed >= Config.Range.challenge.speedMin).toBe(true)
				expect(spec.speed <= Config.Range.challenge.speedMax).toBe(true)
				different = different or spec.from ~= c[index].from
			end
			expect(different).toBe(true)
		end)

		it("points : dégâts arrondis, au moins 1", function()
			expect(RangeRules.points(0.2)).toBe(1)
			expect(RangeRules.points(24.6)).toBe(25)
		end)

		it("armes de la liste toutes à distance", function()
			for _, id in Config.Range.challenge.weapons do
				expect(Config.Weapons.ranged[id] ~= nil).toBe(true)
			end
		end)
	end)
end
