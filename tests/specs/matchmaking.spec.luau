--!nocheck
-- Matchmaking : plateformes, éligibilité, composition des parties, complément de bots.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local Matchmaking = H.require("ReplicatedStorage/Shared/Match/Matchmaking")
	local Config = H.require("ReplicatedStorage/Shared/Config")

	local nextId = 0
	local function ticket(format, joinedAt, userIds)
		nextId += 1
		return {
			id = "t" .. nextId,
			userIds = userIds,
			modeId = "easy",
			format = format,
			group = "crossplay",
			joinedAt = joinedAt,
			hubJobId = "hub",
		}
	end

	local options = { now = 100, matchSize = 16, fillTimeout = 90, minPlayers = 1 }

	describe("Plateformes", function()
		it("crossplay choisi ou plateforme unique", function()
			expect(Matchmaking.platformGroup(true, { "touch" })).toBe("crossplay")
			expect(Matchmaking.platformGroup(false, { "touch" })).toBe("touch")
			expect(Matchmaking.platformGroup(false, { "gamepad", "gamepad" })).toBe("gamepad")
		end)

		it("duo de deux plateformes différentes : crossplay forcé", function()
			local group, forced = Matchmaking.platformGroup(false, { "touch", "keyboard" })
			expect(group).toBe("crossplay")
			expect(forced).toBe(true)
		end)

		it("proposition de crossplay après 60 s hors crossplay", function()
			expect(Matchmaking.suggestCrossplay("touch", 59, false)).toBe(false)
			expect(Matchmaking.suggestCrossplay("touch", 60, false)).toBe(true)
			expect(Matchmaking.suggestCrossplay("crossplay", 120, false)).toBe(false)
		end)
	end)

	describe("Éligibilité", function()
		it("SE hors plage : raison et valeurs affichables", function()
			local refusal = Matchmaking.refusal({ level = 5, score = 2450, pendingLoot = 0 }, "easy")
			expect(refusal.reason).toBe("score_too_high")
			expect(refusal.params.score).toBe(2450)
			expect(refusal.params.max).toBe(2000)
			refusal = Matchmaking.refusal({ level = 5, score = 300, pendingLoot = 0 }, "hard")
			expect(refusal.reason).toBe("score_too_low")
			expect(refusal.params.min).toBe(5000)
		end)

		it("plages qui se chevauchent : 1 500 accède à Facile et Moyen", function()
			local member = { level = 5, score = 1500, pendingLoot = 0 }
			expect(Matchmaking.refusal(member, "easy")).toBeNil()
			expect(Matchmaking.refusal(member, "medium")).toBeNil()
			expect(Matchmaking.refusal(member, "hard")).toBeTruthy()
		end)

		it("loot non trié : départ refusé", function()
			local refusal = Matchmaking.refusal({ level = 5, score = 100, pendingLoot = 2 }, "easy")
			expect(refusal.reason).toBe("pending_loot")
		end)

		it("SE du profil : équipement, sac préparé et objet temporaire", function()
			local profile = {
				loadout = {},
				bag = {},
				tempItem = { uid = "u1", itemId = "nanite_injector", stack = 1 },
				pendingLoot = {},
				level = 1,
			}
			expect(Matchmaking.profileScore(profile) > 0).toBe(true)
		end)
	end)

	describe("Composition", function()
		it("16 solos : départ immédiat sans bots", function()
			local tickets = {}
			for index = 1, 18 do
				table.insert(tickets, ticket("solo", 50 + index, { index }))
			end
			local composition = Matchmaking.compose(tickets, options)
			expect(composition.full).toBe(true)
			expect(composition.players).toBe(16)
			expect(composition.bots).toBe(0)
			-- Les plus anciens d'abord.
			expect(composition.tickets[1].userIds[1]).toBe(1)
		end)

		it("en attente avant 90 s, puis complément de mercenaires", function()
			local tickets = { ticket("solo", 50, { 1 }), ticket("solo", 60, { 2 }) }
			expect(Matchmaking.compose(tickets, options)).toBeNil()
			local later = table.clone(options)
			later.now = 140
			local composition = Matchmaking.compose(tickets, later)
			expect(composition.players).toBe(2)
			expect(composition.bots).toBe(14)
			expect(composition.full).toBe(false)
		end)

		it("duos : 8 paires, places paires uniquement", function()
			local tickets = {}
			for index = 1, 9 do
				table.insert(tickets, ticket("duo", index, { index * 10, index * 10 + 1 }))
			end
			local composition = Matchmaking.compose(tickets, options)
			expect(#composition.tickets).toBe(8)
			expect(composition.players).toBe(16)
			local late = Matchmaking.compose({ ticket("duo", 0, { 1, 2 }) }, options)
			expect(late.bots).toBe(14)
			expect(#Matchmaking.botTeams("duo", late.bots)).toBe(7)
		end)

		it("tickets invalides ou joueur en double ignorés", function()
			local tickets = {
				ticket("solo", 1, { 7 }),
				ticket("solo", 2, { 7 }),
				ticket("duo", 3, { 8 }), -- duo à un seul joueur
				ticket("solo", 4, { 9, 10 }), -- solo à deux joueurs
			}
			local composition =
				Matchmaking.compose(tickets, { now = 1000, matchSize = 16, fillTimeout = 90, minPlayers = 1 })
			expect(#composition.tickets).toBe(1)
			expect(composition.players).toBe(1)
		end)

		it("mercenaires en solo : une équipe chacun", function()
			local teams = Matchmaking.botTeams("solo", 3)
			expect(#teams).toBe(3)
			expect(teams[1]).toBe(1)
			expect(Config.Matchmaking.matchSize).toBe(16)
		end)
	end)
	describe("Mercenaires IA", function()
		local MercenaryGear = H.require("ServerScriptService/Server/Robots/MercenaryGear")
		local ItemCatalog = H.require("ReplicatedStorage/Shared/Items/ItemCatalog")
		local ItemRules = H.require("ReplicatedStorage/Shared/Items/ItemRules")
		local counter = 0
		local function create(itemId, options)
			counter += 1
			options = options or {}
			local info = ItemCatalog.get(itemId)
			return {
				uid = "m" .. counter,
				itemId = itemId,
				condition = if info.hasCondition then (options.condition or 4) else nil,
				stack = if info.stackSize then (options.stack or info.stackSize) else nil,
			}
		end

		it("armes de mercenaires : connues et à chargeur", function()
			for _, list in Config.Mercenaries.weapons do
				for _, id in list do
					local def = Config.Weapons.ranged[id]
					expect(def ~= nil).toBe(true)
					expect(def.capacity ~= nil).toBe(true)
				end
			end
			for _, id in Config.Mercenaries.melee do
				expect(Config.Weapons.melee[id] ~= nil).toBe(true)
			end
		end)

		it("SE dans la plage du mode (200 tirages par mode)", function()
			for _, modeId in Config.Modes.list do
				local minScore, maxScore = MercenaryGear.range(modeId)
				local rng = H.FakeRandom.new(7)
				local inside = 0
				for _ = 1, 200 do
					local loadout, bag = MercenaryGear.build(modeId, rng, create)
					local score = ItemRules.equipmentScore(loadout, bag)
					if score >= minScore and score <= maxScore then
						inside += 1
					end
					expect(loadout.ranged ~= nil).toBe(true)
				end
				if inside < 196 then
					error(`{modeId} : {inside}/200 dans la plage [{minScore}, {maxScore}]`)
				end
			end
		end)
	end)
end
