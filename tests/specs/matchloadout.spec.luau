--!nocheck
-- Équipement entre le profil et une partie : départ, retour, assurance, partie non terminée.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local MatchLoadout = H.require("ServerScriptService/Server/Economy/MatchLoadout")
	local ProfileTemplate = H.require("ServerScriptService/Server/Data/ProfileTemplate")
	local InventoryLogic = H.require("ReplicatedStorage/Shared/Items/InventoryLogic")
	local ItemCatalog = H.require("ReplicatedStorage/Shared/Items/ItemCatalog")
	local ItemRules = H.require("ReplicatedStorage/Shared/Items/ItemRules")
	local Config = H.require("ReplicatedStorage/Shared/Config")

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
			isKit = options.isKit,
			tempGamesLeft = options.tempGamesLeft,
		}
	end
	local function profile()
		local p = ProfileTemplate.new(1000)
		p.credits = 5000
		return p
	end
	-- Profil équipé : fusil, mêlée, sac, deux soins au sac.
	local function equipped()
		local p = profile()
		p.loadout.ranged = create("sentinel_rifle")
		p.loadout.melee = create("shock_crowbar")
		p.loadout.backpack = create("backpack_small")
		table.insert(p.bag, create("nanite_injector", { stack = 2 }))
		return p
	end
	-- Tous les uid d'un profil (équipement, sac, coffre, tri, objet temporaire).
	local function uids(p)
		local set = {}
		local function add(item)
			if item then
				expect(set[item.uid]).toBeNil() -- jamais deux fois le même objet
				set[item.uid] = true
			end
		end
		for _, slot in ItemCatalog.slotNames do
			add(p.loadout[slot])
		end
		for _, list in { p.bag, p.vault, p.pendingLoot, p.pendingInsurance or {} } do
			for _, item in list do
				add(item)
			end
		end
		add(p.tempItem)
		return set
	end

	describe("Départ en partie", function()
		it("l'équipement quitte le profil ; l'instantané et le sac de partie le contiennent", function()
			local p = equipped()
			local rifle = p.loadout.ranged
			local departure = MatchLoadout.takeForMatch(p, "match-1", "easy", 1234)
			expect(next(p.loadout)).toBeNil()
			expect(#p.bag).toBe(0)
			expect(p.activeMatch.id).toBe("match-1")
			expect(p.activeMatch.mode).toBe("easy")
			expect(p.activeMatch.startedAt).toBe(1234)
			expect(p.activeMatch.snapshot.loadout.ranged.uid).toBe(rifle.uid)
			expect(departure.bag.equipped.ranged.uid).toBe(rifle.uid)
			expect(#departure.bag.bag).toBe(1)
			-- Copies distinctes : la partie ne modifie pas l'instantané.
			departure.bag.equipped.ranged.condition = 1
			expect(p.activeMatch.snapshot.loadout.ranged.condition).toBe(4)
		end)

		it("l'objet temporaire part avec le joueur : gadget dans un emplacement libre, sinon au sac", function()
			local p = equipped()
			p.tempItem = create("jump_boots", { tempGamesLeft = 3 })
			local departure = MatchLoadout.takeForMatch(p, "m", "easy", 0)
			expect(p.tempItem).toBeNil()
			expect(departure.bag.equipped.gadget1.itemId).toBe("jump_boots")
			local q = equipped()
			q.tempItem = create("overdrive", { tempGamesLeft = 3 })
			local other = MatchLoadout.takeForMatch(q, "m", "easy", 0)
			local found = false
			for _, item in other.bag.bag do
				found = found or item.itemId == "overdrive"
			end
			expect(found).toBe(true)
		end)

		it("assurance payée au départ, refusée sans crédits suffisants", function()
			local p = equipped()
			p.insuranceTier = "basic"
			local cost = MatchLoadout.insuranceCost("basic", p.loadout, p.bag)
			local before = p.credits
			local departure = MatchLoadout.takeForMatch(p, "m", "easy", 0)
			expect(departure.insurance).toBe("basic")
			expect(p.credits).toBe(before - cost)
			expect(p.activeMatch.insurance).toBe("basic")
			expect(p.insuranceTier).toBeNil()

			local poor = equipped()
			poor.credits = 0
			poor.insuranceTier = "premium"
			local refused = MatchLoadout.takeForMatch(poor, "m", "easy", 0)
			expect(refused.insurance).toBeNil()
			expect(refused.insuranceRefused).toBe(true)
			expect(poor.credits).toBe(0)
		end)
	end)

	describe("Assurance au départ (valeur assurée)", function()
		it("kit de base seul : rien d'assurable, rien n'est payé", function()
			local p = profile()
			p.loadout.ranged = create("scrap_laser_pistol", { isKit = true })
			p.loadout.melee = create("shock_crowbar", { isKit = true })
			p.insuranceTier = "premium"
			local before = p.credits
			local departure = MatchLoadout.takeForMatch(p, "m", "easy", 0)
			expect(p.credits).toBe(before)
			expect(departure.insurance).toBeNil()
			expect(departure.insuranceUseless).toBe(true)
			expect(departure.insuranceRefused).toBe(false)
		end)

		it("consommables et cellules ne font pas monter le prix (jamais rendus)", function()
			local light = equipped()
			local heavy = equipped()
			for _ = 1, 6 do
				table.insert(heavy.bag, create("shield_battery"))
				table.insert(heavy.bag, create("cell_standard"))
			end
			local a = MatchLoadout.insuranceCost("standard", light.loadout, light.bag)
			local b = MatchLoadout.insuranceCost("standard", heavy.loadout, heavy.bag)
			expect(a > 0).toBe(true)
			expect(b).toBe(a)
		end)
	end)

	describe("Fin de partie", function()
		it("extraction : retour dans les emplacements libres, le reste au tri, sans perte ni doublon", function()
			local p = equipped()
			local before = uids(p)
			local departure = MatchLoadout.takeForMatch(p, "m", "easy", 0)
			-- Butin ramassé en partie.
			InventoryLogic.store(departure.bag, create("vigil_pistol"))
			-- Entre-temps, un fusil a été équipé (cas d'une restitution d'assurance) : occupé.
			p.loadout.ranged = create("crackler")
			local value = MatchLoadout.settle(p, departure.bag, true, create)
			expect(p.activeMatch).toBeNil()
			expect(p.loadout.melee ~= nil).toBe(true)
			expect(p.loadout.ranged.itemId).toBe("crackler")
			local pendingIds = {}
			for _, item in p.pendingLoot do
				pendingIds[item.itemId] = true
			end
			expect(pendingIds.sentinel_rifle).toBe(true) -- emplacement occupé → tri
			expect(pendingIds.vigil_pistol).toBe(true) -- butin → tri
			expect(value > 0).toBe(true)
			local after = uids(p)
			for uid in before do
				expect(after[uid]).toBe(true) -- rien n'a disparu
			end
		end)

		it("extraction : le kit n'est pas conservé, l'objet temporaire perd une partie", function()
			local p = profile()
			p.loadout.ranged = create("scrap_laser_pistol", { isKit = true })
			p.tempItem = create("smoke_deployer", { tempGamesLeft = 2 })
			local departure = MatchLoadout.takeForMatch(p, "m", "easy", 0)
			MatchLoadout.settle(p, departure.bag, true, create)
			expect(p.loadout.ranged).toBeNil()
			expect(#p.pendingLoot).toBe(0)
			expect(p.tempItem.tempGamesLeft).toBe(1)
		end)

		it("mort sans assurance : rien ne revient, la partie est close", function()
			local p = equipped()
			MatchLoadout.takeForMatch(p, "m", "easy", 0)
			local value = MatchLoadout.settle(p, nil, false, create)
			expect(value).toBe(0)
			expect(p.activeMatch).toBeNil()
			expect(next(p.loadout)).toBeNil()
			expect(#p.pendingLoot).toBe(0)
			expect(p.pendingInsurance).toBeNil()
		end)

		it("mort assurée : équipement rendu dégradé à la partie suivante, consommables exclus", function()
			local p = equipped()
			p.insuranceTier = "basic"
			MatchLoadout.takeForMatch(p, "m", "easy", 0)
			MatchLoadout.settle(p, nil, false, create)
			local loss = Config.Economy.insurance.tiers.basic.conditionLoss
			expect(#p.pendingInsurance).toBe(3) -- fusil, mêlée, sac (pas les soins)
			for _, item in p.pendingInsurance do
				expect(item.condition).toBe(math.max(Config.Conditions.MIN, 4 - loss))
				expect(item.uid ~= nil).toBe(true)
			end
			-- Partie suivante (même une mort) : livraison au tri.
			MatchLoadout.takeForMatch(p, "m2", "easy", 0)
			MatchLoadout.settle(p, nil, false, create)
			expect(#p.pendingLoot).toBe(3)
			expect(p.pendingInsurance).toBeNil()
		end)
	end)

	describe("Partie non terminée (serveur planté)", function()
		it("l'équipement de l'instantané est rendu, sans doublon", function()
			local p = equipped()
			local before = uids(p)
			MatchLoadout.takeForMatch(p, "m", "easy", 0)
			expect(MatchLoadout.restoreAbandoned(p)).toBe(true)
			expect(p.activeMatch).toBeNil()
			local after = uids(p)
			for uid in before do
				expect(after[uid]).toBe(true)
			end
			expect(MatchLoadout.restoreAbandoned(p)).toBe(false) -- rien de plus à rendre
		end)

		it("emplacement occupé entre-temps : l'objet part au tri", function()
			local p = equipped()
			MatchLoadout.takeForMatch(p, "m", "easy", 0)
			p.loadout.ranged = create("crackler")
			MatchLoadout.restoreAbandoned(p)
			expect(p.loadout.ranged.itemId).toBe("crackler")
			expect(p.pendingLoot[1].itemId).toBe("sentinel_rifle")
		end)

		it("le sac préparé ne dépasse jamais sa capacité : l'excédent part au tri", function()
			local p = equipped()
			-- Sac de partie bien rempli (consommables, cellules).
			for _ = 1, 12 do
				table.insert(p.bag, create("cell_standard"))
			end
			MatchLoadout.takeForMatch(p, "m", "easy", 0)
			-- Entre-temps : plus de sac (poches seulement), donc bien moins de place.
			p.activeMatch.snapshot.loadout.backpack = nil
			MatchLoadout.restoreAbandoned(p)
			expect(ItemRules.totalUp(p.bag) <= ItemRules.bagCapacity(p.loadout.backpack)).toBe(true)
			expect(#p.pendingLoot > 0).toBe(true)
		end)
	end)
end
