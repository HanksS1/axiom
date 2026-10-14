--!nocheck
-- Administration : caisses offertes (giveaway) et droits d'administrateur.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local Config = H.require("ReplicatedStorage/Shared/Config")
	local ItemCatalog = H.require("ReplicatedStorage/Shared/Items/ItemCatalog")
	local CrateGifts = H.require("ServerScriptService/Server/Economy/CrateGifts")
	local EconomyRules = H.require("ServerScriptService/Server/Economy/EconomyRules")
	local ProfileTemplate = H.require("ServerScriptService/Server/Data/ProfileTemplate")
	local Migrations = H.require("ServerScriptService/Server/Data/Migrations")
	local A = Config.Admin

	local NOW = 1_800_000_000
	local counter = 0
	local function create(itemId, options)
		counter += 1
		options = options or {}
		local info = ItemCatalog.get(itemId)
		return {
			uid = "g" .. counter,
			itemId = itemId,
			condition = if info.hasCondition then (options.condition or 4) else nil,
			stack = if info.stackSize then (options.stack or info.stackSize) else nil,
			tempGamesLeft = options.tempGamesLeft,
		}
	end

	describe("Caisses offertes", function()
		it("toutes les caisses du Holo-Bazar et la caisse gratuite peuvent être offertes", function()
			expect(CrateGifts.isGiftable("free")).toBe(true)
			for crateId in Config.Monetization.crates do
				expect(CrateGifts.isGiftable(crateId)).toBe(true)
			end
			expect(CrateGifts.isGiftable("inconnue")).toBe(false)
			expect(CrateGifts.isGiftable(nil)).toBe(false)
		end)

		it("ajout, cumul et limites", function()
			local profile = ProfileTemplate.new(NOW)
			local ok, _, total = CrateGifts.grant(profile, "neon", 3)
			expect(ok).toBe(true)
			expect(total).toBe(3)
			ok, _, total = CrateGifts.grant(profile, "neon", 2)
			expect(total).toBe(5)
			expect(CrateGifts.count(profile, "neon")).toBe(5)
			expect(CrateGifts.count(profile, "rust")).toBe(0)
			-- Quantités refusées : nulle, négative, fractionnaire, au-delà du maximum par envoi.
			for _, bad in { 0, -1, 1.5, A.maxPerGift + 1 } do
				local refused, reason = CrateGifts.grant(profile, "neon", bad)
				expect(refused).toBe(false)
				expect(reason).toBe("invalid_amount")
			end
			local refused, reason = CrateGifts.grant(profile, "gold", 1)
			expect(refused).toBe(false)
			expect(reason).toBe("unknown_crate")
			-- Stock plein.
			profile.crateTokens.rust = A.maxStock
			refused, reason = CrateGifts.grant(profile, "rust", 1)
			expect(refused).toBe(false)
			expect(reason).toBe("stock_full")
		end)

		it("une caisse offerte s'utilise une fois", function()
			local profile = ProfileTemplate.new(NOW)
			CrateGifts.grant(profile, "prototype", 2)
			expect(CrateGifts.consume(profile, "prototype")).toBe(true)
			expect(CrateGifts.consume(profile, "prototype")).toBe(true)
			expect(CrateGifts.consume(profile, "prototype")).toBe(false)
			expect(profile.crateTokens.prototype).toBeNil()
		end)

		it("caisse gratuite offerte : ouverte quand le compteur normal est vide", function()
			local profile = ProfileTemplate.new(NOW)
			local rng = H.FakeRandom.new(3)
			profile.freeCrate.stored = 0
			profile.freeCrate.lastGrantUnix = NOW
			expect((EconomyRules.openFreeCrate(profile, NOW, rng, create))).toBe(false)
			CrateGifts.grant(profile, "free", 2)
			expect((EconomyRules.openFreeCrate(profile, NOW, rng, create))).toBe(true)
			expect(CrateGifts.count(profile, "free")).toBe(1)
			-- Une caisse accumulée passe avant la caisse offerte.
			profile.freeCrate.stored = 1
			EconomyRules.openFreeCrate(profile, NOW, rng, create)
			expect(profile.freeCrate.stored).toBe(0)
			expect(CrateGifts.count(profile, "free")).toBe(1)
		end)

		it("profil : caisses offertes conservées, valeurs invalides écartées (v4 → v5)", function()
			local data = ProfileTemplate.new(NOW)
			data.version = 4
			data.crateTokens = nil
			local profile = Migrations.run(data, NOW)
			expect(profile.version).toBe(ProfileTemplate.VERSION)
			expect(next(profile.crateTokens)).toBeNil()
			data = ProfileTemplate.new(NOW)
			data.crateTokens = { neon = 4, rust = -2, gold = 9, prototype = A.maxStock + 50 }
			profile = Migrations.run(data, NOW)
			expect(profile.crateTokens.neon).toBe(4)
			expect(profile.crateTokens.rust).toBeNil()
			expect(profile.crateTokens.gold).toBeNil()
			expect(profile.crateTokens.prototype).toBe(A.maxStock)
		end)
	end)

	describe("Crédits offerts", function()
		it("ajout, montants refusés, plafond du profil", function()
			local profile = ProfileTemplate.new(NOW)
			profile.credits = 100
			local ok, _, added = CrateGifts.grantCredits(profile, 500)
			expect(ok).toBe(true)
			expect(added).toBe(500)
			expect(profile.credits).toBe(600)
			for _, bad in { 0, -10, 2.5, A.maxCreditsPerGift + 1 } do
				local refused, reason = CrateGifts.grantCredits(profile, bad)
				expect(refused).toBe(false)
				expect(reason).toBe("invalid_amount")
			end
			expect(profile.credits).toBe(600)
			-- Le total reste borné par le maximum d'un profil.
			profile.credits = Config.Economy.maxCredits - 50
			ok, _, added = CrateGifts.grantCredits(profile, 1000)
			expect(ok).toBe(true)
			expect(added).toBe(50)
			expect(profile.credits).toBe(Config.Economy.maxCredits)
			local refused, reason = CrateGifts.grantCredits(profile, 100)
			expect(refused).toBe(false)
			expect(reason).toBe("credits_full")
		end)

		it("raccourcis du panneau valides", function()
			for _, value in A.creditPresets do
				expect(value >= 1 and value <= A.maxCreditsPerGift).toBe(true)
			end
			expect(A.creditStep >= 1).toBe(true)
		end)
	end)

	describe("Droits d'administrateur", function()
		it("hors Studio : seulement la liste et le groupe configurés", function()
			expect(CrateGifts.isAdmin(424242, 0, false)).toBe(table.find(A.userIds, 424242) ~= nil)
			for _, userId in A.userIds do
				expect(CrateGifts.isAdmin(userId, 0, false)).toBe(true)
			end
			-- Un rang de groupe ne compte que si un groupe est configuré.
			expect(CrateGifts.isAdmin(999999999, 255, false)).toBe(A.groupId ~= 0)
		end)

		it("Studio : selon la config (tests)", function()
			expect(CrateGifts.isAdmin(-1, 0, true)).toBe(A.everyoneInStudio)
		end)
	end)
end
