--!nocheck
-- Cohérence des modules de configuration (valeurs du document de conception).

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local Config = H.require("ReplicatedStorage/Shared/Config")
	local ItemCatalog = H.require("ReplicatedStorage/Shared/Items/ItemCatalog")
	local Remotes = H.require("ReplicatedStorage/Shared/Net/Remotes")

	local function sum(list)
		local total = 0
		for _, v in list do
			total += v
		end
		return total
	end

	describe("Config", function()
		it("est entièrement gelée", function()
			expect(table.isfrozen(Config)).toBe(true)
			expect(table.isfrozen(Config.Weapons.ranged.needle)).toBe(true)
			expect(function()
				Config.Combat.maxHealth = 999
			end).toThrow()
		end)

		it("taux de drop par état : somme = 100 % pour chaque mode", function()
			for _, modeId in Config.Modes.list do
				local rates = Config.Modes.byId[modeId].conditionDropRates
				expect(#rates).toBe(Config.Conditions.MAX)
				expect(sum(rates)).toBeNear(100, 1e-9)
			end
		end)

		it("probabilités des caisses cosmétiques : somme = 100 %", function()
			for id, crate in Config.Monetization.crates do
				local total = 0
				for _, rarity in Config.Monetization.rarities do
					local odds = crate.odds[rarity]
					expect(odds ~= nil).toBe(true)
					total += odds
				end
				expect(total).toBeNear(100, 1e-9)
				expect(table.find(Config.Monetization.rarities, crate.pity.minRarity) ~= nil).toBe(true)
			end
		end)

		it("états : efficacité et valeur strictement croissantes", function()
			local list = Config.Conditions.list
			for i = 2, #list do
				expect(list[i].efficiency > list[i - 1].efficiency).toBe(true)
				expect(list[i].valueMultiplier > list[i - 1].valueMultiplier).toBe(true)
				expect(list[i].index).toBe(i)
			end
		end)

		it("armes à distance : cellule valide, chargeur OU surchauffe", function()
			for id, weapon in Config.Weapons.ranged do
				expect(Config.Cells[weapon.cell] ~= nil).toBe(true)
				local hasMagazine = weapon.capacity ~= nil
				local hasHeat = weapon.heat ~= nil
				expect(hasMagazine ~= hasHeat).toBe(true)
				if hasMagazine then
					expect(weapon.reloadTime ~= nil).toBe(true)
				else
					expect(weapon.cellCost ~= nil).toBe(true)
				end
			end
		end)

		it("valeurs du document : quelques contrôles ponctuels", function()
			expect(Config.Weapons.ranged.sentinel_rifle.damage).toBe(17)
			expect(Config.Weapons.ranged.hullbreaker.pellets).toBe(8)
			expect(Config.Weapons.melee.vibro_blade.shieldIgnore).toBe(0.5)
			expect(Config.Equipment.vests.vest.shieldByCondition[5]).toBe(100)
			expect(Config.Equipment.backpacks.backpack_large.capacityByCondition[5]).toBe(25)
			expect(Config.Economy.vault.baseCapacity).toBe(30)
			expect(Config.Match.duration).toBe(900)
			expect(Config.Match.alertAt).toBe(720)
		end)

		it("toutes les références d'objets existent", function()
			for pool, entries in Config.Loot.pools do
				for itemId in entries do
					expect(ItemCatalog.exists(itemId)).toBe(true)
				end
			end
			for _, robot in Config.Robots.byId do
				for _, entry in robot.loot do
					if entry.itemId then
						expect(ItemCatalog.exists(entry.itemId)).toBe(true)
					else
						expect(Config.Loot.pools[entry.pool] ~= nil).toBe(true)
					end
				end
			end
			for _, itemId in Config.Economy.freeCrate.tempItemPool do
				expect(ItemCatalog.exists(itemId)).toBe(true)
			end
			local kit = Config.Economy.baseKit
			expect(ItemCatalog.exists(kit.ranged.itemId)).toBe(true)
			expect(ItemCatalog.exists(kit.melee.itemId)).toBe(true)
			expect(ItemCatalog.exists(kit.backpack.itemId)).toBe(true)
			for _, entry in kit.bag do
				expect(ItemCatalog.exists(entry.itemId)).toBe(true)
			end
			expect(ItemCatalog.exists(Config.Economy.repair.calibrationItemId)).toBe(true)
		end)

		it("la lame vibrante n'est pas dans les caisses (lâchée par les élites uniquement)", function()
			for _, entries in Config.Loot.pools do
				expect(entries.vibro_blade).toBeNil()
			end
		end)

		it("chaque remote client → serveur a une limite de fréquence", function()
			for name, def in Remotes do
				if def.toServer then
					expect(Config.Network.limits[name] ~= nil).toBe(true)
				end
			end
		end)

		it("paramètres : valeurs par défaut dans les bornes", function()
			for key, def in Config.Settings do
				if def.kind == "number" then
					expect(def.default >= def.min and def.default <= def.max).toBe(true)
				elseif def.kind == "enum" then
					expect(table.find(def.values, def.default) ~= nil).toBe(true)
				else
					expect(type(def.default)).toBe("boolean")
				end
			end
		end)

		it("plages de SE : chevauchement Facile/Moyen et Moyen/Difficile", function()
			local modes = Config.Modes.byId
			expect(modes.medium.minScore < modes.easy.maxScore).toBe(true)
			expect(modes.hard.minScore < modes.medium.maxScore).toBe(true)
			expect(modes.easy.minScore).toBe(0)
		end)
	end)
end
