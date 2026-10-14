--!nocheck
-- Règles d'objets : valeur, UP, SE, capacités, validation.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local ItemRules = H.require("ReplicatedStorage/Shared/Items/ItemRules")

	local function item(itemId, condition, extra)
		local result = { uid = "uid-" .. itemId .. tostring(condition), itemId = itemId, condition = condition }
		for k, v in extra or {} do
			result[k] = v
		end
		return result
	end

	describe("ItemRules.value", function()
		it("valeur de base × multiplicateur d'état", function()
			expect(ItemRules.value(item("vigil_pistol", 4))).toBe(600)
			expect(ItemRules.value(item("vigil_pistol", 5))).toBe(1500)
			expect(ItemRules.value(item("scrap_laser_pistol", 1))).toBe(10)
			expect(ItemRules.value(item("needle", 3))).toBe(750)
			expect(ItemRules.value(item("vest", 2))).toBe(225)
		end)

		it("piles : au prorata de la quantité", function()
			expect(ItemRules.value({ uid = "a", itemId = "nanite_injector", stack = 3 })).toBe(150)
			expect(ItemRules.value({ uid = "b", itemId = "nanite_injector", stack = 1 })).toBe(50)
			expect(ItemRules.value({ uid = "c", itemId = "cell_light", stack = 30 })).toBe(10)
			expect(ItemRules.value({ uid = "d", itemId = "cell_light", stack = 15 })).toBe(5)
		end)

		it("kit de base et objets temporaires : valeur nulle, non vendables", function()
			local kit = item("scrap_laser_pistol", 1, { isKit = true })
			expect(ItemRules.value(kit)).toBe(0)
			expect(ItemRules.isSellable(kit)).toBe(false)
			local temp = item("jump_boots", 4, { tempGamesLeft = 3 })
			expect(ItemRules.value(temp)).toBe(0)
			expect(ItemRules.isSellable(temp)).toBe(false)
			expect(ItemRules.isSellable(item("jump_boots", 4))).toBe(true)
		end)
	end)

	describe("ItemRules.capacités", function()
		it("UP par objet (section 8.2)", function()
			expect(ItemRules.up(item("vigil_pistol", 4))).toBe(2)
			expect(ItemRules.up(item("sentinel_rifle", 4))).toBe(4)
			expect(ItemRules.up(item("needle", 4))).toBe(5)
			expect(ItemRules.up(item("bastion_minigun", 4))).toBe(6)
			expect(ItemRules.up(item("backpack_medium", 4))).toBe(3)
			expect(ItemRules.up({ uid = "x", itemId = "cell_heavy", stack = 1 })).toBe(1)
		end)

		it("capacité du sac selon taille et état, poches sans sac", function()
			expect(ItemRules.bagCapacity(nil)).toBe(4)
			expect(ItemRules.bagCapacity(item("backpack_small", 1))).toBe(8)
			expect(ItemRules.bagCapacity(item("backpack_medium", 4))).toBe(16)
			expect(ItemRules.bagCapacity(item("backpack_large", 5))).toBe(25)
			expect(ItemRules.bagCapacity(item("backpack_large", 5), 6)).toBe(31)
		end)

		it("capacité du coffre : 30, 40 avec l'extension", function()
			expect(ItemRules.vaultCapacity(false)).toBe(30)
			expect(ItemRules.vaultCapacity(true)).toBe(40)
		end)

		it("exemple du document : 26 UP", function()
			local vault = {
				item("sentinel_rifle", 4),
				item("vigil_pistol", 4),
				item("laser_saber", 4),
				item("grappling_hook", 4),
				item("smoke_deployer", 4),
				item("recon_drone", 4),
				item("backpack_medium", 4),
				item("vest", 4),
				item("helmet", 4),
				{ uid = "s1", itemId = "nanite_injector", stack = 3 },
				{ uid = "s2", itemId = "nanite_injector", stack = 3 },
				{ uid = "s3", itemId = "shield_battery", stack = 3 },
				{ uid = "c1", itemId = "cell_light", stack = 30 },
				{ uid = "c2", itemId = "cell_light", stack = 30 },
				{ uid = "c3", itemId = "cell_standard", stack = 30 },
			}
			expect(ItemRules.totalUp(vault)).toBe(26)
		end)
	end)

	describe("ItemRules.combat", function()
		it("bouclier selon le gilet", function()
			expect(ItemRules.maxShield(nil)).toBe(0)
			expect(ItemRules.maxShield(item("vest", 1))).toBe(25)
			expect(ItemRules.maxShield(item("vest", 5))).toBe(100)
		end)

		it("multiplicateur de tête selon le casque", function()
			expect(ItemRules.headMultiplier(nil)).toBe(2.0)
			expect(ItemRules.headMultiplier(item("helmet", 1))).toBe(1.8)
			expect(ItemRules.headMultiplier(item("helmet", 5))).toBe(1.3)
		end)
	end)

	describe("Score d'Équipement", function()
		it("somme des objets portés et du sac", function()
			local loadout = {
				ranged = item("sentinel_rifle", 4), -- 1000
				melee = item("shock_crowbar", 1, { isKit = true }), -- 0
				vest = item("vest", 3), -- 450
			}
			local bag = { { uid = "n", itemId = "nanite_injector", stack = 3 } } -- 150
			expect(ItemRules.equipmentScore(loadout, bag)).toBe(1600)
		end)

		it("accès aux modes et raisons de refus", function()
			expect(ItemRules.modeAccess(0, "easy")).toBe(true)
			expect(ItemRules.modeAccess(2000, "easy")).toBe(true)
			local ok, reason = ItemRules.modeAccess(2450, "easy")
			expect(ok).toBe(false)
			expect(reason).toBe("score_too_high")
			ok, reason = ItemRules.modeAccess(4000, "hard")
			expect(ok).toBe(false)
			expect(reason).toBe("score_too_low")
			expect(ItemRules.modeAccess(1_000_000, "hard")).toBe(true)
			expect(ItemRules.modeAccess(1000, "medium")).toBe(true)
			expect(ItemRules.modeAccess(1000, "nope")).toBe(false)
		end)
	end)

	describe("ItemRules.validate", function()
		it("accepte les objets valides", function()
			expect(ItemRules.validate(item("vigil_pistol", 3))).toBe(true)
			expect(ItemRules.validate({ uid = "a", itemId = "cell_light", stack = 30 })).toBe(true)
			expect(ItemRules.validate({ uid = "a", itemId = "calibration_module" })).toBe(true)
		end)

		it("rejette les objets invalides", function()
			expect(ItemRules.validate(nil)).toBe(false)
			expect(ItemRules.validate({ uid = "a", itemId = "inconnu", condition = 3 })).toBe(false)
			expect(ItemRules.validate({ uid = "", itemId = "vigil_pistol", condition = 3 })).toBe(false)
			expect(ItemRules.validate({ uid = "a", itemId = "vigil_pistol" })).toBe(false)
			expect(ItemRules.validate({ uid = "a", itemId = "vigil_pistol", condition = 6 })).toBe(false)
			expect(ItemRules.validate({ uid = "a", itemId = "vigil_pistol", condition = 2.5 })).toBe(false)
			expect(ItemRules.validate({ uid = "a", itemId = "vigil_pistol", condition = 0 / 0 })).toBe(false)
			expect(ItemRules.validate({ uid = "a", itemId = "cell_light", stack = 31 })).toBe(false)
			expect(ItemRules.validate({ uid = "a", itemId = "cell_light", stack = 0 })).toBe(false)
			expect(ItemRules.validate({ uid = "a", itemId = "cell_light", stack = 5, condition = 3 })).toBe(false)
			expect(ItemRules.validate({ uid = "a", itemId = "vigil_pistol", condition = 3, stack = 2 })).toBe(false)
			expect(ItemRules.validate({ uid = "a", itemId = "vigil_pistol", condition = 3, tempGamesLeft = -1 })).toBe(
				false
			)
		end)
	end)

	describe("Munitions et « Tout prendre »", function()
		local InventoryLogic = H.require("ReplicatedStorage/Shared/Items/InventoryLogic")
		local Config = H.require("ReplicatedStorage/Shared/Config")

		it("chaque arme à distance a sa cellule ; chaque cellule sert au moins une arme", function()
			for id in Config.Weapons.ranged do
				local cell = ItemRules.ammoOf(id)
				expect(cell ~= nil).toBe(true)
				expect(table.find(ItemRules.weaponsUsing(cell), id) ~= nil).toBe(true)
			end
			expect(ItemRules.ammoOf("shock_crowbar")).toBeNil()
			expect(ItemRules.ammoOf("cell_light")).toBeNil()
			for cellId in Config.Cells do
				if type(Config.Cells[cellId]) == "table" and Config.Cells[cellId].stackSize then
					expect(#ItemRules.weaponsUsing(cellId) >= 1).toBe(true)
				end
			end
		end)

		it("tout prendre ne surcharge jamais le sac : ce qui ne tient pas reste dans le conteneur", function()
			-- Poches seulement (aucun sac porté), déjà presque pleines.
			local inventory = InventoryLogic.new({ ranged = item("scrap_laser_pistol", 1) }, {
				item("nanite_injector", nil, { stack = 1 }),
			})
			local crate = {
				item("needle", 3),
				item("vigil_pistol", 4),
				item("vest", 2),
				item("shield_battery", nil, { stack = 1 }),
				item("cell_light", nil, { stack = 30 }),
				item("backpack_small", 1),
				item("nanite_injector", nil, { stack = 2 }),
			}
			local taken, kept = InventoryLogic.takeAll(inventory, crate)
			expect(#taken + #kept).toBe(#crate)
			expect(#kept > 0).toBe(true)
			expect(InventoryLogic.used(inventory) <= InventoryLogic.capacity(inventory)).toBe(true)
			-- Le gilet va dans son emplacement vide, l'arme à distance (emplacement occupé) non.
			expect(inventory.equipped.vest ~= nil).toBe(true)
			-- Un conteneur vide ne change rien.
			local before = InventoryLogic.used(inventory)
			local none, left = InventoryLogic.takeAll(inventory, {})
			expect(#none).toBe(0)
			expect(#left).toBe(0)
			expect(InventoryLogic.used(inventory)).toBe(before)
		end)
	end)
end
