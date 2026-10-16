--!nocheck
-- Vue publique du profil (ProfileSync) : rien de privé ne part vers le client.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local ProfileView = H.require("ServerScriptService/Server/Data/ProfileView")
	local ProfileTemplate = H.require("ServerScriptService/Server/Data/ProfileTemplate")
	local Config = H.require("ReplicatedStorage/Shared/Config")

	-- Profil où chaque champ facultatif est rempli (sinon absent de la vue).
	local function full()
		local p = ProfileTemplate.new(1000)
		p.tempItem = { uid = "t1", itemId = "sentinel_rifle", condition = 3, tempGamesLeft = 2 }
		p.insuranceTier = "basic"
		p.pendingInsurance = { { uid = "i1", itemId = "sentinel_rifle", condition = 4 } }
		p.activeMatch = { matchId = "m1", modeId = "easy", joinedAt = 990 }
		p.processedReceipts = { ["r-1"] = true }
		p.receiptOrder = { "r-1" }
		return p
	end

	-- Ce que lit l'interface (contrôleurs et écrans du client).
	local PUBLIC = {
		"level",
		"xp",
		"xpToNext",
		"credits",
		"noyaux",
		"vault",
		"vaultCapacity",
		"loadout",
		"bag",
		"tempItem",
		"hasVaultExtension",
		"freeCrate",
		"pendingLoot",
		"pendingInsuranceCount",
		"insuranceTier",
		"rank",
		"rankingScore",
		"seasonId",
		"top10",
		"seasonHistory",
		"bestScoreByMode",
		"tutorialDone",
		"guidesSeen",
		"crateTokens",
		"settings",
		"pity",
		"cosmeticsOwned",
		"cosmeticsEquipped",
		"stats",
	}

	describe("ProfileView", function()
		it("champs privés jamais envoyés (reçus Robux, partie en cours, assurance détaillée)", function()
			local view = ProfileView.build(full())
			for _, private in
				{
					"processedReceipts",
					"receiptOrder",
					"activeMatch",
					"pendingInsurance",
					"version",
					"createdAt",
					"season",
				}
			do
				expect(view[private]).toBeNil()
			end
			expect(view.freeCrate.lastGrantUnix).toBeNil()
		end)

		it("exactement les champs publics : un nouveau champ du profil reste privé par défaut", function()
			local view = ProfileView.build(full())
			local allowed = {}
			for _, key in PUBLIC do
				allowed[key] = true
				expect(view[key] ~= nil).toBe(true) -- tout ce que lit l'interface existe
			end
			for key in view do
				expect(allowed[key]).toBe(true)
			end
		end)

		it("valeurs dérivées : nombre de remboursements, prochaine caisse gratuite", function()
			local p = full()
			local view = ProfileView.build(p)
			expect(view.pendingInsuranceCount).toBe(1)
			local freeCrate = Config.Economy.freeCrate
			expect(view.freeCrate.nextGrantUnix).toBe(1000 + freeCrate.interval)
			p.freeCrate.stored = freeCrate.maxStored
			p.pendingInsurance = nil
			view = ProfileView.build(p)
			expect(view.freeCrate.nextGrantUnix).toBeNil() -- réserve pleine : plus de compte à rebours
			expect(view.pendingInsuranceCount).toBe(0)
			expect(view.seasonId).toBe(p.season.id)
		end)
	end)
end
