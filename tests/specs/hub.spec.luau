--!nocheck
-- Terminus : PNJ et textes du décor traduits.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local Localization = H.require("ReplicatedStorage/Shared/Localization")
	-- Services utilisés à la construction uniquement (pas appelés par ces tests).
	H.setService("CollectionService", {})
	H.setService("Players", {})
	local HubNpcs = H.require("ServerScriptService/Server/Hub/HubNpcs")

	describe("Terminus", function()
		it("chaque PNJ a un nom et 3 répliques (FR et EN)", function()
			local count = 0
			for station, id in HubNpcs.ids() do
				count += 1
				for _, lang in { "fr", "en" } do
					expect(Localization.has(lang, `npc.{id}.name`)).toBe(true)
					expect(Localization.has(lang, "station." .. station)).toBe(true)
					for line = 1, 3 do
						expect(Localization.has(lang, `npc.{id}.line.{line}`)).toBe(true)
					end
				end
			end
			expect(count).toBe(8)
		end)

		it("affiches, tags et écrans traduits", function()
			for _, lang in { "fr", "en" } do
				for index = 1, 3 do
					expect(Localization.has(lang, "hub.poster." .. index)).toBe(true)
					expect(Localization.has(lang, "hub.monitor." .. index)).toBe(true)
				end
				for index = 1, 6 do
					expect(Localization.has(lang, "hub.graffiti." .. index)).toBe(true)
				end
			end
		end)
	end)
end
