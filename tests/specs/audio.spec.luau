--!nocheck
-- Audio : chaque annonce d'AXIOM a sa voix (FR/EN), chaque arme à distance son tir.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local Config = H.require("ReplicatedStorage/Shared/Config")

	describe("Audio", function()
		it("4 couches de musique", function()
			for _, layer in { "hub", "exploration", "combat", "alert" } do
				local def = Config.Audio.music.layers[layer]
				expect(def ~= nil).toBe(true)
				expect(type(def.id)).toBe("string")
				expect(def.volume > 0 and def.volume <= 1).toBe(true)
			end
			expect(Config.Audio.music.combatHold).toBe(8)
		end)

		it("voix d'AXIOM en FR et EN pour chaque annonce", function()
			for key, lines in Config.Audio.voice do
				expect(type(lines.fr)).toBe("string")
				expect(type(lines.en)).toBe("string")
				expect(string.match(key, "^[%w_%.]+$") ~= nil).toBe(true)
			end
			for _, key in { "axiom.start", "axiom.alert", "axiom.purge" } do
				expect(Config.Audio.voice[key] ~= nil).toBe(true)
			end
		end)

		it("un son de tir par arme à distance", function()
			for id in Config.Weapons.ranged do
				expect(Config.Audio.weapons[id] ~= nil).toBe(true)
			end
		end)
	end)
end
