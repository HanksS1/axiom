--!nocheck
-- Économie : coffre, sac préparé, tri, Marchand, Armurier, assurance, caisse gratuite.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local EconomyRules = H.require("ServerScriptService/Server/Economy/EconomyRules")
	local ProfileTemplate = H.require("ServerScriptService/Server/Data/ProfileTemplate")
	local ItemCatalog = H.require("ReplicatedStorage/Shared/Items/ItemCatalog")
	local Config = H.require("ReplicatedStorage/Shared/Config")

	local counter = 0
	local function create(itemId, options)
		counter += 1
		options = options or {}
		local info = ItemCatalog.get(itemId)
		return {
			uid = "n" .. counter,
			itemId = itemId,
			condition = if info.hasCondition then (options.condition or 4) else nil,
			stack = if info.stackSize then (options.stack or info.stackSize) else nil,
			isKit = options.isKit,
			tempGamesLeft = options.tempGamesLeft,
		}
	end
	local function profile()
		return ProfileTemplate.new(1000)
	end

	describe("Coffre et équipement", function()
		it("équiper depuis le coffre, l'ancien objet revient au coffre", function()
			local p = profile()
			local rifle = create("sentinel_rifle")
			table.insert(p.vault, rifle)
			p.loadout.ranged = create("vigil_pistol")
			expect(EconomyRules.equipFromVault(p, rifle.uid, "ranged")).toBe(true)
			expect(p.loadout.ranged.uid).toBe(rifle.uid)
			expect(p.vault[1].itemId).toBe("vigil_pistol")
		end)

		it("le coffre ne dépasse jamais 30 UP", function()
			local p = profile()
			for _ = 1, 5 do
				table.insert(p.vault, create("bastion_minigun")) -- 30 UP
			end
			p.loadout.ranged = create("needle")
			local ok, why = EconomyRules.unequipToVault(p, "ranged")
			expect(ok).toBe(false)
			expect(why).toBe("vault_full")
			p.hasVaultExtension = true -- 40 UP
			expect(EconomyRules.unequipToVault(p, "ranged")).toBe(true)
		end)

		it("sac préparé limité par le sac équipé", function()
			local p = profile()
			p.loadout.backpack = create("backpack_small", { condition = 1 }) -- 8 UP
			for _ = 1, 4 do
				table.insert(p.vault, create("cell_light"))
			end
			table.insert(p.vault, create("needle")) -- 5 UP
			for _, item in table.clone(p.vault) do
				EconomyRules.vaultToBag(p, item.uid)
			end
			expect(#p.bag).toBe(4) -- l'Aiguille (5) ne rentre plus (4 + 5 > 8)
			local ok, why = EconomyRules.unequipToVault(p, "backpack")
			expect(ok).toBe(true) -- 4 UP <= 4 UP de poches
			expect(why).toBeNil()
		end)

		it("écran de tri : garder (si place) ou jeter", function()
			local p = profile()
			local loot = create("vest")
			table.insert(p.pendingLoot, loot)
			expect(EconomyRules.keepPending(p, loot.uid)).toBe(true)
			expect(#p.vault).toBe(1)
			local junk = create("helmet", { condition = 1 })
			table.insert(p.pendingLoot, junk)
			expect(EconomyRules.discard(p, junk.uid)).toBe(true)
			expect(#p.pendingLoot).toBe(0)
		end)
	end)

	describe("Marchand", function()
		it("achat : prix ×2, états Dégradé / Bon uniquement, crédits suffisants", function()
			local p = profile()
			p.credits = 2500
			local ok, why = EconomyRules.buy(p, "sentinel_rifle", 5, nil, create)
			expect(ok).toBe(false)
			expect(why).toBe("not_for_sale")
			ok = EconomyRules.buy(p, "sentinel_rifle", 4, nil, create)
			expect(ok).toBe(true)
			expect(p.credits).toBe(500)
			ok, why = EconomyRules.buy(p, "sentinel_rifle", 4, nil, create)
			expect(why).toBe("not_enough_credits")
			ok = EconomyRules.buy(p, "cell_standard", nil, nil, create)
			expect(ok).toBe(true)
			expect(p.credits).toBe(480)
		end)

		it("vente : valeur de l'objet, kit invendable, pas de doublon", function()
			local p = profile()
			local vest = create("vest", { condition = 5 }) -- 2250
			local wrecked = create("helmet", { condition = 1 }) -- 50
			table.insert(p.vault, vest)
			table.insert(p.pendingLoot, wrecked)
			local ok, _, total = EconomyRules.sell(p, { vest.uid, wrecked.uid })
			expect(ok).toBe(true)
			expect(total).toBe(2300)
			expect(p.credits).toBe(2300)
			local kit = create("scrap_laser_pistol", { condition = 1, isKit = true })
			table.insert(p.vault, kit)
			local ok2, why = EconomyRules.sell(p, { kit.uid })
			expect(ok2).toBe(false)
			expect(why).toBe("not_sellable")
			local again = create("vest")
			table.insert(p.vault, again)
			local ok3, why3 = EconomyRules.sell(p, { again.uid, again.uid })
			expect(ok3).toBe(false)
			expect(why3).toBe("duplicate")
		end)
	end)

	describe("Armurier", function()
		it("un état à la fois ; Bon → Neuf exige un Module de calibration", function()
			local p = profile()
			p.credits = 100000
			local rifle = create("sentinel_rifle", { condition = 3 })
			p.loadout.ranged = rifle
			local ok, _, cost = EconomyRules.repair(p, rifle.uid)
			expect(ok).toBe(true)
			expect(cost).toBe(750) -- 1,5 × (1000 − 500)
			expect(rifle.condition).toBe(4)
			local ok2, why = EconomyRules.repair(p, rifle.uid)
			expect(ok2).toBe(false)
			expect(why).toBe("needs_calibration")
			table.insert(p.vault, create("calibration_module"))
			expect((EconomyRules.repair(p, rifle.uid))).toBe(true)
			expect(rifle.condition).toBe(5)
			expect(#p.vault).toBe(0) -- module consommé
		end)
	end)

	describe("Assurance", function()
		it("objets rendus dégradés, avec de nouveaux uid ; consommables exclus", function()
			local items = {
				create("needle", { condition = 4 }),
				create("vest", { condition = 1 }),
				create("nanite_injector"),
				create("scrap_laser_pistol", { condition = 1, isKit = true }),
			}
			local basic = EconomyRules.insuranceClaim("basic", items, create)
			expect(#basic).toBe(2)
			expect(basic[1].condition).toBe(2)
			expect(basic[2].condition).toBe(1) -- au minimum Très abîmé
			expect(basic[1].uid ~= items[1].uid).toBe(true)
			local premium = EconomyRules.insuranceClaim("premium", items, create)
			expect(premium[1].condition).toBe(4)
		end)

		it("valeur assurée : équipement uniquement", function()
			local loadout = { ranged = create("needle", { condition = 4 }) } -- 1500
			local bag = { create("cell_light"), create("vest", { condition = 4 }) } -- 900
			expect(EconomyRules.insuredValue(loadout, bag)).toBe(2400)
		end)

		it("livraison via l'écran de tri", function()
			local p = profile()
			p.pendingInsurance = { create("vest") }
			EconomyRules.deliverInsurance(p)
			expect(#p.pendingLoot).toBe(1)
			expect(p.pendingInsurance).toBeNil()
		end)
	end)

	describe("Caisse gratuite", function()
		local interval = Config.Economy.freeCrate.interval

		it("une caisse toutes les 20 min, 2 au maximum, même hors ligne", function()
			local p = profile()
			EconomyRules.accrueFreeCrate(p, 1000 + interval - 1)
			expect(p.freeCrate.stored).toBe(0)
			EconomyRules.accrueFreeCrate(p, 1000 + interval * 1.5)
			expect(p.freeCrate.stored).toBe(1)
			EconomyRules.accrueFreeCrate(p, 1000 + interval * 10)
			expect(p.freeCrate.stored).toBe(2)
		end)

		it("ouverture : crédits ou objet temporaire (3 parties)", function()
			local p = profile()
			p.freeCrate.stored = 2
			local rng = H.FakeRandom.new(4)
			local credits, items = 0, 0
			for _ = 1, 400 do
				p.freeCrate.stored = 1
				p.tempItem = nil
				local ok, _, reward = EconomyRules.openFreeCrate(p, 1000, rng, create)
				expect(ok).toBe(true)
				if reward.kind == "credits" then
					credits += 1
					expect(reward.amount >= 50 and reward.amount <= 300).toBe(true)
				else
					items += 1
					expect(reward.item.tempGamesLeft).toBe(3)
					if ItemCatalog.get(reward.item.itemId).hasCondition then
						expect(reward.item.condition).toBe(4) -- gadget en Bon état
					end
				end
			end
			expect(credits / 400).toBeNear(0.85, 0.06)
			p.freeCrate.stored = 0
			local ok = EconomyRules.openFreeCrate(p, 1000, rng, create)
			expect(ok).toBe(false)
		end)

		it("objet temporaire : disparaît après 3 parties", function()
			local item = create("smoke_deployer", { tempGamesLeft = 3 })
			expect(EconomyRules.ageTempItem(item).tempGamesLeft).toBe(2)
			EconomyRules.ageTempItem(item)
			expect(EconomyRules.ageTempItem(item)).toBeNil()
		end)
	end)
end
