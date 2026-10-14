--!nocheck
-- Prix, inventaire porté et génération du loot.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local Pricing = H.require("ReplicatedStorage/Shared/Economy/Pricing")
	local InventoryLogic = H.require("ReplicatedStorage/Shared/Items/InventoryLogic")
	local ItemRules = H.require("ReplicatedStorage/Shared/Items/ItemRules")
	local LootGenerator = H.require("ServerScriptService/Server/Loot/LootGenerator")

	local counter = 0
	local function create(itemId, options)
		counter += 1
		options = options or {}
		local ItemCatalog = H.require("ReplicatedStorage/Shared/Items/ItemCatalog")
		local info = ItemCatalog.get(itemId)
		return {
			uid = "u" .. counter,
			itemId = itemId,
			condition = if info.hasCondition then (options.condition or 4) else nil,
			stack = if info.stackSize then (options.stack or info.stackSize) else nil,
		}
	end

	describe("Pricing", function()
		it("prix du Marchand", function()
			expect(Pricing.merchantPrice("sentinel_rifle", 4)).toBe(2000)
			expect(Pricing.merchantPrice("sentinel_rifle", 3)).toBe(1000)
			expect(Pricing.merchantPrice("sentinel_rifle", 5)).toBeNil() -- Neuf : loot uniquement
			expect(Pricing.merchantPrice("sentinel_rifle", 1)).toBeNil()
			expect(Pricing.merchantPrice("cell_light")).toBe(20)
			expect(Pricing.merchantPrice("nanite_injector")).toBe(225)
			expect(Pricing.merchantPrice("nanite_injector", nil, 1)).toBe(75)
			expect(Pricing.merchantPrice("calibration_module")).toBeNil()
		end)

		it("coût du kit de base au Marchand", function()
			-- pistolet 100 + barre 80 + petit sac 300 + injecteurs 225 + 2 × cellules 20
			expect(Pricing.baseKitPurchaseCost()).toBe(745)
		end)

		it("revente : kit et objets temporaires invendables", function()
			expect(Pricing.sellPrice(create("vest", { condition = 4 }))).toBe(900)
			local kit = create("scrap_laser_pistol", { condition = 1 })
			kit.isKit = true
			expect(Pricing.sellPrice(kit)).toBe(0)
		end)

		it("réparation : un état à la fois, ×1,5 la différence", function()
			local cost, needsCalibration = Pricing.repairCost(create("sentinel_rifle", { condition = 1 }))
			expect(cost).toBe(225) -- 1,5 × (250 − 100)
			expect(needsCalibration).toBe(false)
			cost, needsCalibration = Pricing.repairCost(create("sentinel_rifle", { condition = 4 }))
			expect(cost).toBe(2250) -- 1,5 × (2500 − 1000)
			expect(needsCalibration).toBe(true)
			expect((Pricing.repairCost(create("sentinel_rifle", { condition = 5 })))).toBeNil()
		end)

		it("réparer pour revendre fait toujours perdre de l'argent", function()
			for condition = 1, 4 do
				local item = create("needle", { condition = condition })
				local cost = Pricing.repairCost(item)
				local gain = ItemRules.valueAt("needle", condition + 1) - ItemRules.valueAt("needle", condition)
				expect(cost > gain).toBe(true)
			end
		end)

		it("assurance : % du SE", function()
			expect(Pricing.insuranceCost("basic", 1000)).toBe(100)
			expect(Pricing.insuranceCost("standard", 1000)).toBe(180)
			expect(Pricing.insuranceCost("premium", 1000)).toBe(300)
			expect(Pricing.insuranceCost("gold", 1000)).toBeNil()
			-- SE nul (kit de base) : prix plancher, jamais 0, hiérarchie des formules conservée.
			local tiers = H.require("ReplicatedStorage/Shared/Config").Economy.insurance.tiers
			expect(Pricing.insuranceCost("basic", 0)).toBe(tiers.basic.minCost)
			expect(Pricing.insuranceCost("standard", 0)).toBe(tiers.standard.minCost)
			expect(Pricing.insuranceCost("premium", 0)).toBe(tiers.premium.minCost)
			expect(tiers.basic.minCost > 0).toBe(true)
			expect(tiers.basic.minCost < tiers.standard.minCost).toBe(true)
			expect(tiers.standard.minCost < tiers.premium.minCost).toBe(true)
			-- Kit acheté au Marchand : la part du SE dépasse le plancher.
			for id, tier in tiers do
				expect(Pricing.insuranceCost(id, 745) > tier.minCost).toBe(true)
			end
		end)
	end)

	describe("InventoryLogic", function()
		local function inventory()
			return InventoryLogic.new({ backpack = create("backpack_small", { condition = 1 }) }, {})
		end

		it("capacité : sac + bonus", function()
			local inv = inventory()
			expect(InventoryLogic.capacity(inv)).toBe(8)
			inv.bonusUp = 6
			expect(InventoryLogic.capacity(inv)).toBe(14)
		end)

		it("rangement et sac plein", function()
			local inv = inventory()
			expect(InventoryLogic.store(inv, create("sentinel_rifle"))).toBe(true) -- 4
			expect(InventoryLogic.store(inv, create("hullbreaker"))).toBe(true) -- 3 → 7
			local ok, leftover = InventoryLogic.store(inv, create("vigil_pistol")) -- 2 → 9 > 8
			expect(ok).toBe(false)
			expect(leftover ~= nil).toBe(true)
			expect(InventoryLogic.used(inv)).toBe(7)
		end)

		it("les piles fusionnent avant de prendre de la place", function()
			local inv = inventory()
			InventoryLogic.store(inv, create("cell_light", { stack = 20 }))
			InventoryLogic.store(inv, create("cell_light", { stack = 15 }))
			expect(#inv.bag).toBe(2)
			expect(inv.bag[1].stack).toBe(30)
			expect(inv.bag[2].stack).toBe(5)
			expect(InventoryLogic.count(inv, "cell_light")).toBe(35)
		end)

		it("fusion partielle quand le sac est plein", function()
			local inv = InventoryLogic.new({}, {}) -- 4 UP de poches
			InventoryLogic.store(inv, create("vigil_pistol")) -- 2
			InventoryLogic.store(inv, create("cell_light", { stack = 25 })) -- 1
			InventoryLogic.store(inv, create("helmet")) -- poches pleines ? 2+1 = 3, casque 2 → refus
			expect(InventoryLogic.used(inv)).toBe(3)
			InventoryLogic.store(inv, create("nanite_injector", { stack = 1 })) -- 4
			local ok, leftover = InventoryLogic.store(inv, create("cell_light", { stack = 20 }))
			expect(ok).toBe(true) -- 5 cellules fusionnées
			expect(leftover.stack).toBe(15)
			expect(InventoryLogic.count(inv, "cell_light")).toBe(30)
		end)

		it("les cellules du kit ne fusionnent pas avec les autres", function()
			local inv = inventory()
			local kitCells = create("cell_light", { stack = 10 })
			kitCells.isKit = true
			InventoryLogic.store(inv, kitCells)
			InventoryLogic.store(inv, create("cell_light", { stack = 10 }))
			expect(#inv.bag).toBe(2)
		end)

		it("consommation : les petites piles d'abord", function()
			local inv = inventory()
			table.insert(inv.bag, create("cell_light", { stack = 30 }))
			table.insert(inv.bag, create("cell_light", { stack = 5 }))
			expect(InventoryLogic.consume(inv, "cell_light", 12)).toBe(12)
			expect(#inv.bag).toBe(1)
			expect(inv.bag[1].stack).toBe(23)
			expect(InventoryLogic.consume(inv, "cell_light", 100)).toBe(23)
			expect(#inv.bag).toBe(0)
		end)

		it("équiper depuis le sac : l'ancien objet retourne au sac", function()
			local inv = inventory()
			inv.equipped.ranged = create("scrap_laser_pistol")
			local rifle = create("sentinel_rifle")
			InventoryLogic.store(inv, rifle)
			expect(InventoryLogic.equipFromBag(inv, rifle.uid, "ranged")).toBe(true)
			expect(inv.equipped.ranged.uid).toBe(rifle.uid)
			expect(inv.bag[1].itemId).toBe("scrap_laser_pistol")
			local ok, why = InventoryLogic.equipFromBag(inv, inv.bag[1].uid, "melee")
			expect(ok).toBe(false)
			expect(why).toBe("wrong_slot")
		end)

		it("changer de sac : le contenu doit tenir", function()
			local inv = InventoryLogic.new({ backpack = create("backpack_large", { condition = 5 }) }, {})
			for _ = 1, 3 do
				InventoryLogic.store(inv, create("bastion_minigun")) -- 18 UP
			end
			local small = create("backpack_small", { condition = 1 })
			local ok, why = InventoryLogic.equipFromOutside(inv, small, "backpack")
			expect(ok).toBe(false)
			expect(why).toBe("too_small")
			local ok2, why2 = InventoryLogic.unequip(inv, "backpack")
			expect(ok2).toBe(false)
			expect(why2).toBe("too_small")
		end)

		it("ramasser une arme : l'arme équipée est rendue (elle tombe au sol)", function()
			local inv = inventory()
			local pistol = create("scrap_laser_pistol")
			inv.equipped.ranged = pistol
			local ok, _, previous = InventoryLogic.equipFromOutside(inv, create("needle"), "ranged")
			expect(ok).toBe(true)
			expect(previous.uid).toBe(pistol.uid)
		end)

		it("emplacement naturel : 2e gadget dans le 2e emplacement", function()
			local inv = inventory()
			expect(InventoryLogic.slotFor(inv, "jump_boots")).toBe("gadget1")
			inv.equipped.gadget1 = create("jump_boots")
			expect(InventoryLogic.slotFor(inv, "smoke_deployer")).toBe("gadget2")
			expect(InventoryLogic.slotFor(inv, "cell_light")).toBeNil()
		end)

		it("mort : tout est vidé dans le sac de dépouille", function()
			local inv = inventory()
			inv.equipped.ranged = create("needle")
			table.insert(inv.bag, create("cell_light"))
			local items = InventoryLogic.drainAll(inv)
			expect(#items).toBe(3)
			expect(#inv.bag).toBe(0)
			expect(inv.equipped.backpack).toBeNil()
		end)
	end)

	describe("LootGenerator", function()
		local Random = H.FakeRandom

		it("états tirés selon la table du mode", function()
			local rng = Random.new(42)
			local counts = { 0, 0, 0, 0, 0 }
			for _ = 1, 20000 do
				local c = LootGenerator.rollCondition("easy", rng)
				counts[c] += 1
			end
			expect(counts[1] / 20000).toBeNear(0.5, 0.02)
			expect(counts[2] / 20000).toBeNear(0.3, 0.02)
			expect(counts[5] / 20000).toBeNear(0.005, 0.004)
		end)

		it("élites : état décalé d'un cran, Neuf reste Neuf", function()
			local rng = Random.new(1)
			for _ = 1, 2000 do
				local c = LootGenerator.rollCondition("hard", rng, 1)
				expect(c >= 2 and c <= 5).toBe(true)
			end
		end)

		it("2 caisses de ravitaillement ≈ le coût du kit de base (Facile)", function()
			local rng = Random.new(7)
			local kit = Pricing.baseKitPurchaseCost()
			local total = 0
			local runs = 4000
			local low, high = math.huge, 0
			for _ = 1, runs do
				local pair = 0
				for _ = 1, 2 do
					for _, item in LootGenerator.crate("supply", "easy", rng, create) do
						pair += ItemRules.value(item)
					end
				end
				total += pair
				low = math.min(low, pair)
				high = math.max(high, pair)
			end
			local average = total / runs
			-- Moyenne proche du kit (l'équipement chanceux tire un peu vers le haut).
			expect(average > kit * 0.85 and average < kit * 1.35).toBe(true)
			-- Variation réelle : parfois en dessous, parfois au-dessus.
			expect(low < kit * 0.85).toBe(true)
			expect(high > kit * 1.15).toBe(true)
		end)

		it("casier d'AXIOM : 2 objets, le 1er Dégradé ou mieux", function()
			local rng = Random.new(3)
			for _ = 1, 500 do
				local items = LootGenerator.crate("axiom_locker", "easy", rng, create)
				local equipment = {}
				for _, item in items do
					if item.condition then
						table.insert(equipment, item)
					end
				end
				expect(#equipment).toBe(2)
				expect(equipment[1].condition >= 3).toBe(true)
			end
		end)

		it("Module de calibration seulement en Difficile", function()
			local rng = Random.new(5)
			local easyFound, hardFound = false, false
			for _ = 1, 600 do
				for _, item in LootGenerator.crate("axiom_locker", "easy", rng, create) do
					easyFound = easyFound or item.itemId == "calibration_module"
				end
				for _, item in LootGenerator.crate("axiom_locker", "hard", rng, create) do
					hardFound = hardFound or item.itemId == "calibration_module"
				end
			end
			expect(easyFound).toBe(false)
			expect(hardFound).toBe(true)
		end)

		it("jamais plus d'objets que la limite de la caisse", function()
			local rng = Random.new(9)
			for _, crateId in { "supply", "military", "axiom_locker" } do
				for _ = 1, 300 do
					expect(#LootGenerator.crate(crateId, "hard", rng, create) <= 6).toBe(true)
				end
			end
		end)

		it("loot des robots : Exécuteur avec objet garanti, Gardien 2 ou 3", function()
			local rng = Random.new(11)
			for _ = 1, 200 do
				local items = LootGenerator.robot("executor", "medium", rng, create)
				local equipment = 0
				for _, item in items do
					if item.condition then
						equipment += 1
					end
				end
				expect(equipment >= 1).toBe(true)
				local warden = LootGenerator.robot("warden", "easy", rng, create)
				expect(#warden >= 2 and #warden <= 3).toBe(true) -- pas de module hors Difficile
			end
		end)
	end)
end
