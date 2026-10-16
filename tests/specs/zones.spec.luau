--!nocheck
-- Zones (Terminus, Arène FFA, partie, tutoriel) : gadgets et munitions prêtées.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local Zone = H.require("ReplicatedStorage/Shared/Match/Zone")
	local Config = H.require("ReplicatedStorage/Shared/Config")
	local Fighter = H.require("ServerScriptService/Server/Combat/Fighter")
	local InventoryLogic = H.require("ReplicatedStorage/Shared/Items/InventoryLogic")
	local Freeze = H.require("ReplicatedStorage/Shared/Util/Freeze")
	local MatchLoadout = H.require("ServerScriptService/Server/Economy/MatchLoadout")
	local ProfileTemplate = H.require("ServerScriptService/Server/Data/ProfileTemplate")

	local function facts(overrides)
		local f = { inMatch = false, inTutorial = false, inArena = false }
		for k, v in overrides or {} do
			f[k] = v
		end
		return f
	end

	describe("Zone.classify", function()
		it("partie > tutoriel > Arène FFA > Terminus", function()
			expect(Zone.classify(facts())).toBe("hub")
			expect(Zone.classify(facts({ inArena = true }))).toBe("arena")
			expect(Zone.classify(facts({ inTutorial = true, inArena = true }))).toBe("tutorial")
			expect(Zone.classify(facts({ inMatch = true, inArena = true }))).toBe("match")
		end)
	end)

	describe("Zone.allows", function()
		it("gadgets : jamais au Terminus ni au tutoriel ; en partie et dans l'Arène FFA", function()
			expect(Zone.allows("hub", "gadgets")).toBe(false)
			expect(Zone.allows("tutorial", "gadgets")).toBe(false)
			expect(Zone.allows("arena", "gadgets")).toBe(true)
			expect(Zone.allows("match", "gadgets")).toBe(true)
		end)

		it("munitions prêtées : au Terminus seulement", function()
			expect(Zone.allows("hub", "freeAmmo")).toBe(true)
			for _, zone in { "arena", "match", "tutorial" } do
				expect(Zone.allows(zone, "freeAmmo")).toBe(false)
			end
		end)

		it("zone inconnue ou absente (serveur de partie dédié) : règles d'une partie", function()
			expect(Zone.allows(nil, "gadgets")).toBe(true)
			expect(Zone.allows(nil, "freeAmmo")).toBe(false)
			expect(Zone.allows("lune", "freeAmmo")).toBe(false)
		end)
	end)

	describe("Munitions prêtées : aucune fuite", function()
		local counter = 0
		local function cells(amount)
			counter += 1
			return { uid = "c" .. counter, itemId = "cell_light", stack = amount }
		end
		-- Combattant hors partie : sac = COPIE du profil (comme CharacterService).
		local function fighterFor(profile)
			local fighter = { bag = InventoryLogic.new(Freeze.copy(profile.loadout), Freeze.copy(profile.bag)) }
			fighter.inventory = Fighter.bagInventory(fighter)
			return fighter
		end

		it("au Terminus : réserve affichée prêtée, rien n'est retiré du sac", function()
			local profile = ProfileTemplate.new(0)
			table.insert(profile.bag, cells(30))
			local fighter = fighterFor(profile)
			expect(Fighter.reserve(fighter, "cell_light", true)).toBe(Config.Zones.lentReserve)
			for _ = 1, 200 do
				expect(Fighter.spendCells(fighter, "cell_light", 3, true)).toBe(0)
			end
			expect(InventoryLogic.count(fighter.bag, "cell_light")).toBe(30)
			-- De retour hors du Terminus (arène) : la vraie réserve, consommée normalement.
			expect(Fighter.reserve(fighter, "cell_light", false)).toBe(30)
			expect(Fighter.spendCells(fighter, "cell_light", 4, false)).toBe(4)
			expect(InventoryLogic.count(fighter.bag, "cell_light")).toBe(26)
		end)

		it(
			"départ en partie après avoir tiré au Terminus : le sac emporté vient du profil, sans cellule prêtée",
			function()
				local profile = ProfileTemplate.new(0)
				table.insert(profile.bag, cells(12))
				local fighter = fighterFor(profile)
				for _ = 1, 50 do
					Fighter.spendCells(fighter, "cell_light", 5, true)
				end
				local departure = MatchLoadout.takeForMatch(profile, "m1", "easy", 0)
				expect(InventoryLogic.count(departure.bag, "cell_light")).toBe(12)
				expect(InventoryLogic.count(departure.bag, "cell_light") < Config.Zones.lentReserve).toBe(true)
				-- Le profil (instantané de secours compris) n'a jamais vu la réserve prêtée.
				expect(profile.activeMatch.snapshot.bag[1].stack).toBe(12)
			end
		)
	end)

	describe("Cartes de partie (Zone.onMatchMap)", function()
		local roblox = require("@lune/roblox")
		local Vector3 = roblox.Vector3

		it("carte de partie, mais ni le Terminus ni l'Arène FFA", function()
			local origin = Config.Maps.origin
			expect(Zone.onMatchMap(origin)).toBe(true)
			expect(Zone.onMatchMap(origin + Vector3.new(Config.Maps.size / 2 - 1, 80, 0))).toBe(true)
			expect(Zone.onMatchMap(Vector3.new(0, 4, 400))).toBe(false) -- Terminus
			expect(Zone.onMatchMap(Vector3.new(0, 3, 0))).toBe(false) -- Arène FFA
			expect(Zone.onMatchMap(origin + Vector3.new(Config.Maps.size, 0, 0))).toBe(false)
		end)
	end)
end
