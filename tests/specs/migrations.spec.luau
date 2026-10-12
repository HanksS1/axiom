--!nocheck
-- Migrations et assainissement des profils (anti-duplication, bornes, types).

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local Migrations = H.require("ServerScriptService/Server/Data/Migrations")
	local ProfileTemplate = H.require("ServerScriptService/Server/Data/ProfileTemplate")

	local NOW = 1_800_000_000

	describe("Migrations", function()
		it("un profil neuf passe sans modification", function()
			local profile, err, report = Migrations.run(ProfileTemplate.new(NOW), NOW)
			expect(err).toBeNil()
			expect(profile.version).toBe(ProfileTemplate.VERSION)
			expect(report.removedItems).toBe(0)
			expect(report.duplicateUids).toBe(0)
			expect(report.fixedFields).toBe(0)
			expect(profile.settings.language).toBe("auto")
		end)

		it("refuse un profil d'une version plus récente", function()
			local data = ProfileTemplate.new(NOW)
			data.version = ProfileTemplate.VERSION + 1
			local profile, err = Migrations.run(data, NOW)
			expect(profile).toBeNil()
			expect(err).toBe("newer_version")
		end)

		it("refuse des données qui ne sont pas une table", function()
			expect((Migrations.run("x", NOW))).toBeNil()
			expect((Migrations.run({ version = -1 }, NOW))).toBeNil()
		end)

		it("complète un profil vide (clés manquantes)", function()
			local profile = Migrations.run({}, NOW)
			expect(profile.level).toBe(1)
			expect(profile.credits).toBe(0)
			expect(type(profile.vault)).toBe("table")
			expect(type(profile.stats.matchesPlayed)).toBe("number")
		end)

		it("supprime les uid dupliqués (le loadout est prioritaire)", function()
			local data = ProfileTemplate.new(NOW)
			data.loadout.ranged = { uid = "dup", itemId = "vigil_pistol", condition = 5 }
			data.vault = {
				{ uid = "dup", itemId = "vigil_pistol", condition = 5 },
				{ uid = "ok", itemId = "vest", condition = 2 },
				{ uid = "ok", itemId = "vest", condition = 2 },
			}
			local profile, _, report = Migrations.run(data, NOW)
			expect(profile.loadout.ranged.uid).toBe("dup")
			expect(#profile.vault).toBe(1)
			expect(profile.vault[1].uid).toBe("ok")
			expect(report.duplicateUids).toBe(2)
		end)

		it("retire les objets invalides et les champs parasites", function()
			local data = ProfileTemplate.new(NOW)
			data.vault = {
				{ uid = "a", itemId = "objet_inconnu", condition = 3 },
				{ uid = "b", itemId = "vest", condition = 9 },
				{ uid = "c", itemId = "vest", condition = 3, hack = true },
			}
			local profile, _, report = Migrations.run(data, NOW)
			expect(#profile.vault).toBe(1)
			expect(profile.vault[1].uid).toBe("c")
			expect(profile.vault[1].hack).toBeNil()
			expect(report.removedItems).toBe(2)
		end)

		it("range au coffre un objet équipé dans le mauvais emplacement", function()
			local data = ProfileTemplate.new(NOW)
			data.loadout.ranged = { uid = "v", itemId = "vest", condition = 3 }
			local profile = Migrations.run(data, NOW)
			expect(profile.loadout.ranged).toBeNil()
			expect(#profile.vault).toBe(1)
			expect(profile.vault[1].uid).toBe("v")
		end)

		it("borne les monnaies et corrige les nombres invalides", function()
			local data = ProfileTemplate.new(NOW)
			data.credits = 0 / 0
			data.noyaux = -50
			data.level = 2.5
			data.xp = math.huge
			local profile = Migrations.run(data, NOW)
			expect(profile.credits).toBe(0)
			expect(profile.noyaux).toBe(0)
			expect(profile.level).toBe(1)
			expect(profile.xp).toBe(0)
		end)

		it("assainit les paramètres", function()
			local data = ProfileTemplate.new(NOW)
			data.settings = { language = "de", mouseSensitivity = 99, aimAssist = false, inconnu = 1 }
			local profile = Migrations.run(data, NOW)
			expect(profile.settings.language).toBe("auto")
			expect(profile.settings.mouseSensitivity).toBe(1)
			expect(profile.settings.aimAssist).toBe(false)
			expect(profile.settings.inconnu).toBeNil()
		end)

		it("conserve les reçus Robux déjà traités", function()
			local data = ProfileTemplate.new(NOW)
			data.processedReceipts = { r1 = 100, r2 = 200 }
			data.receiptOrder = { "r2" }
			local profile = Migrations.run(data, NOW)
			expect(profile.processedReceipts.r1).toBe(100)
			expect(profile.processedReceipts.r2).toBe(200)
			expect(#profile.receiptOrder).toBe(2)
			expect(profile.receiptOrder[2]).toBe("r2")
		end)

		it("borne la caisse gratuite", function()
			local data = ProfileTemplate.new(NOW)
			data.freeCrate = { stored = 50, lastGrantUnix = NOW + 99999 }
			local profile = Migrations.run(data, NOW)
			expect(profile.freeCrate.stored).toBe(2)
			expect(profile.freeCrate.lastGrantUnix).toBe(NOW)
		end)

		it("v2 : partie en cours conservée, uid déjà présents écartés", function()
			local data = ProfileTemplate.new(NOW)
			data.vault = { { uid = "shared", itemId = "vest", condition = 3 } }
			data.activeMatch = {
				id = "m1",
				startedAt = NOW,
				mode = "easy",
				snapshot = {
					loadout = { ranged = { uid = "r1", itemId = "needle", condition = 4 } },
					bag = {
						{ uid = "shared", itemId = "vest", condition = 3 },
						{ uid = "c1", itemId = "cell_light", stack = 30 },
					},
				},
			}
			local profile = Migrations.run(data, NOW)
			expect(profile.activeMatch.id).toBe("m1")
			expect(profile.activeMatch.snapshot.loadout.ranged.uid).toBe("r1")
			expect(#profile.activeMatch.snapshot.bag).toBe(1)
			expect(#profile.pendingLoot).toBe(0)
		end)

		it("v1 → v2 : migration d'un ancien profil", function()
			local data = ProfileTemplate.new(NOW)
			data.version = 1
			data.pendingLoot = nil
			data.activeMatch = nil
			local profile, err = Migrations.run(data, NOW)
			expect(err).toBeNil()
			expect(profile.version).toBe(3)
			expect(type(profile.pendingLoot)).toBe("table")
		end)
	end)
end
