--!nocheck
-- Boutique cosmétique : caisses, garanties, probabilités affichées, rotation, reçus.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local Shop = H.require("ReplicatedStorage/Shared/Monetization/Shop")
	local Config = H.require("ReplicatedStorage/Shared/Config")
	local M = Config.Monetization

	describe("Caisses", function()
		it("probabilités de chaque caisse : somme exactement 100 %", function()
			for crateId in M.crates do
				expect(Shop.oddsValid(crateId)).toBe(true)
			end
		end)

		it("chaque rareté possible a au moins un cosmétique", function()
			for _, crate in M.crates do
				for rarity, chance in crate.odds do
					if chance > 0 then
						expect(#Shop.cosmeticsOfRarity(rarity) > 0).toBe(true)
					end
				end
			end
		end)

		it("probabilités affichées au centième : somme exactement 100,00", function()
			for crateId in M.crates do
				for _, pity in { 0, 5, 1000 } do
					local shown = Shop.displayHundredths(Shop.effectiveOdds(crateId, pity))
					local total = 0
					for _, value in shown do
						total += value
					end
					expect(total).toBe(10000)
				end
			end
		end)

		it("garantie : Épique ou mieux à la 10e caisse Rouille sans Épique", function()
			local rng = H.FakeRandom.new(3)
			for _ = 1, 200 do
				local rarity, pity = Shop.rollRarity("rust", 9, rng)
				expect(Shop.rarityIndex(rarity) >= Shop.rarityIndex("epic")).toBe(true)
				expect(pity).toBe(0)
			end
			expect(Shop.guaranteeNext("rust", 8)).toBe(false)
			expect(Shop.guaranteeNext("rust", 9)).toBe(true)
			expect(Shop.untilGuarantee("rust", 0)).toBe(10)
		end)

		it("le compteur avance sans Épique et repart à zéro sinon", function()
			local rng = H.FakeRandom.new(11)
			local pity = 0
			for _ = 1, 500 do
				local rarity, nextPity = Shop.rollRarity("rust", pity, rng)
				if Shop.rarityIndex(rarity) >= Shop.rarityIndex("epic") then
					expect(nextPity).toBe(0)
				else
					expect(nextPity).toBe(pity + 1)
				end
				expect(nextPity < 10).toBe(true)
				pity = nextPity
			end
		end)

		it("distribution conforme aux probabilités (Caisse Néon, sans garantie)", function()
			local rng = H.FakeRandom.new(42)
			local counts = {}
			local n = 40000
			for _ = 1, n do
				local rarity = Shop.rollRarity("neon", 0, rng)
				counts[rarity] = (counts[rarity] or 0) + 1
			end
			for rarity, chance in M.crates.neon.odds do
				local observed = (counts[rarity] or 0) / n * 100
				if math.abs(observed - chance) > 1 then
					error(`{rarity} : {observed} % au lieu de {chance} %`)
				end
			end
		end)

		it("jamais une rareté à 0 % (Prototype : pas de Commun)", function()
			local rng = H.FakeRandom.new(5)
			for _ = 1, 3000 do
				expect(Shop.rollRarity("prototype", 0, rng) ~= "common").toBe(true)
			end
		end)

		it("cibles des cosmétiques : armes connues (et dessinées), sac, casque, gilet", function()
			for _, id in Config.Cosmetics.list do
				local def = Config.Cosmetics.byId[id]
				if def.category == "weapon" then
					local weapon = Config.Weapons.ranged[def.target] or Config.Weapons.melee[def.target]
					expect(weapon ~= nil).toBe(true)
					expect(Config.Visuals.weapons[def.target] ~= nil).toBe(true)
				else
					expect(def.target).toBe(def.category)
				end
				expect(Shop.rarityIndex(def.rarity) > 0).toBe(true)
			end
		end)

		it("doublon : 20 % de la valeur", function()
			expect(Shop.duplicateRefund("legendary")).toBe(200)
			expect(Shop.duplicateRefund("common")).toBe(20)
		end)
	end)

	describe("Textes", function()
		it("motifs, caisses, raretés et emplacements traduits (FR et EN)", function()
			local Localization = H.require("ReplicatedStorage/Shared/Localization")
			for _, lang in { "fr", "en" } do
				for pattern in Config.Cosmetics.patterns do
					expect(Localization.has(lang, "skin." .. pattern)).toBe(true)
				end
				for crateId in M.crates do
					expect(Localization.has(lang, "cosmeticCrate." .. crateId)).toBe(true)
				end
				for _, rarity in M.rarities do
					expect(Localization.has(lang, "rarity." .. rarity)).toBe(true)
				end
				for _, slot in { "backpack", "helmet", "vest" } do
					expect(Localization.has(lang, "cosmetic.slot." .. slot)).toBe(true)
				end
			end
		end)
	end)

	describe("Holo-Bazar", function()
		it("6 objets distincts, sans Mythique, identiques pour une même date", function()
			local day = Shop.dayIndex(1800000000)
			local a, b = Shop.rotation(day), Shop.rotation(day)
			expect(#a).toBe(6)
			local seen = {}
			for index, id in a do
				expect(id).toBe(b[index])
				expect(seen[id]).toBeNil()
				seen[id] = true
				expect(Shop.directPrice(id) ~= nil).toBe(true)
			end
		end)

		it("la rotation change d'un jour à l'autre et se renouvelle à 00:00 UTC", function()
			local unix = 1800000000
			local day = Shop.dayIndex(unix)
			local same = 0
			local tomorrow = Shop.rotation(day + 1)
			for _, id in Shop.rotation(day) do
				if table.find(tomorrow, id) then
					same += 1
				end
			end
			expect(same < 6).toBe(true)
			expect(Shop.nextRotationAt(unix) % 86400).toBe(0)
		end)

		it("tolérance juste après le changement de jour", function()
			local midnight = Shop.nextRotationAt(1800000000)
			local yesterday = Shop.rotation(Shop.dayIndex(midnight - 1))[1]
			if table.find(Shop.rotation(Shop.dayIndex(midnight)), yesterday) == nil then
				expect(Shop.inRotation(yesterday, midnight + 10, 60)).toBe(true)
				expect(Shop.inRotation(yesterday, midnight + 120, 60)).toBe(false)
			end
		end)
	end)

	describe("Reçus Robux", function()
		it("un reçu n'est traité qu'une fois ; mémoire bornée", function()
			local profile = { processedReceipts = {}, receiptOrder = {} }
			Shop.recordReceipt(profile, "a", 1)
			expect(Shop.receiptProcessed(profile, "a")).toBe(true)
			Shop.recordReceipt(profile, "a", 2)
			expect(#profile.receiptOrder).toBe(1)
			for index = 1, M.maxRememberedReceipts + 5 do
				Shop.recordReceipt(profile, "r" .. index, index)
			end
			expect(#profile.receiptOrder).toBe(M.maxRememberedReceipts)
			expect(Shop.receiptProcessed(profile, "a")).toBe(false)
		end)

		it("emplacement d'un cosmétique", function()
			expect(Shop.slotOf("cobalt__sentinel_rifle")).toBe("weapon:sentinel_rifle")
			expect(Shop.slotOf("cobalt__helmet")).toBe("helmet")
			expect(Shop.slotOf("inconnu")).toBeNil()
		end)
	end)

	describe("Ouverture d'une caisse (animation)", function()
		local CrateSequence = H.require("ReplicatedStorage/Shared/Visuals/CrateSequence")
		local ItemModels = H.require("ReplicatedStorage/Shared/Visuals/ItemModels")
		local C = M.crateOpening
		local timeline = CrateSequence.timeline(C.phases)

		it("construction, scanner, ouverture, puis l'objet sort : dans cet ordre, en moins de 8 s", function()
			local order = {}
			local total = 0
			for _, phase in C.phases do
				table.insert(order, phase.name)
				expect(phase.duration > 0).toBe(true)
				total += phase.duration
			end
			expect(table.concat(order, ",")).toBe("coarse,fine,solidify,scan,open,rise")
			expect(timeline.total).toBeNear(total)
			expect(total < 8).toBe(true)
			expect(CrateSequence.phaseAt(timeline, 0)).toBe("coarse")
			expect(CrateSequence.phaseAt(timeline, timeline.total + 1)).toBe("done")
			local scan = CrateSequence.step(timeline, "scan")
			expect(CrateSequence.phaseAt(timeline, (scan.start + scan.finish) / 2)).toBe("scan")
			expect(CrateSequence.progress(timeline, "scan", scan.start - 1)).toBe(0)
			expect(CrateSequence.progress(timeline, "scan", (scan.start + scan.finish) / 2)).toBeNear(0.5)
			expect(CrateSequence.progress(timeline, "scan", timeline.total)).toBe(1)
		end)

		it("pixels de plus en plus fins, tous dans la caisse, du bas vers le haut", function()
			local size = C.crateSize
			local coarse = CrateSequence.voxels(size, C.coarseCell)
			local fine = CrateSequence.voxels(size, C.fineCell)
			expect(#coarse >= 8).toBe(true)
			expect(#fine > #coarse * 3).toBe(true)
			-- Budget de pièces raisonnable dans un ViewportFrame.
			expect(#fine <= 150).toBe(true)
			for _, list in { coarse, fine } do
				local seen = {}
				local lastY = -math.huge
				for _, voxel in list do
					local p = voxel.position
					local key = string.format("%.3f,%.3f,%.3f", p.X, p.Y, p.Z)
					expect(seen[key]).toBeNil()
					seen[key] = true
					expect(math.abs(p.X) + voxel.size.X / 2 <= size.X / 2 + 1e-6).toBe(true)
					expect(math.abs(p.Y) + voxel.size.Y / 2 <= size.Y / 2 + 1e-6).toBe(true)
					expect(math.abs(p.Z) + voxel.size.Z / 2 <= size.Z / 2 + 1e-6).toBe(true)
					expect(p.Y >= lastY - 1e-6).toBe(true)
					lastY = p.Y
				end
			end
			-- Toujours le même ordre (aucun hasard).
			local again = CrateSequence.voxels(size, C.fineCell)
			for index, voxel in fine do
				expect(again[index].position).toEqual(voxel.position)
			end
			expect(CrateSequence.spawned(#fine, 0)).toBe(0)
			expect(CrateSequence.spawned(#fine, 0.5)).toBe(math.floor(#fine / 2))
			expect(CrateSequence.spawned(#fine, 1)).toBe(#fine)
		end)

		it("chaque cosmétique s'affiche sur un objet qui a un modèle", function()
			local PREVIEW = { backpack = "backpack_medium", helmet = "helmet", vest = "vest" }
			for id, def in Config.Cosmetics.byId do
				local itemId = if def.category == "weapon" then def.target else PREVIEW[def.category]
				if not ItemModels.has(itemId) then
					error(`{id} : aucun modèle pour {itemId}`)
				end
			end
		end)
	end)
end
