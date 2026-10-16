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

	describe("Remplissage du sac et du coffre", function()
		local Config = H.require("ReplicatedStorage/Shared/Config")
		it("normal, presque plein à partir du seuil, plein à la limite", function()
			local warning = Config.Equipment.capacityWarning
			expect(ItemRules.fillLevel(0, 10)).toBe("ok")
			expect(ItemRules.fillLevel(math.ceil(10 * warning) - 1, 10)).toBe("ok")
			expect(ItemRules.fillLevel(math.ceil(10 * warning), 10)).toBe("high")
			expect(ItemRules.fillLevel(9, 10)).toBe("high")
			expect(ItemRules.fillLevel(10, 10)).toBe("full")
			expect(ItemRules.fillLevel(12, 10)).toBe("full")
			expect(ItemRules.fillLevel(0, 0)).toBe("full")
		end)
	end)

	describe("Exo-harnais", function()
		local Config = H.require("ReplicatedStorage/Shared/Config")
		local InventoryLogic = H.require("ReplicatedStorage/Shared/Items/InventoryLogic")
		local ConsumableRules = H.require("ReplicatedStorage/Shared/Items/ConsumableRules")
		local exo = Config.Equipment.consumables.exo_harness
		local bonus = exo.effect.bonusUp

		local function fighter(overrides)
			local view = { health = 100, maxHealth = 100, shield = 0, maxShield = 50, exoUsed = false }
			for k, v in overrides or {} do
				view[k] = v
			end
			return view
		end

		it("ajoute sa place à la capacité du sac (avec ou sans sac)", function()
			local pockets = Config.Equipment.pocketsUp
			expect(ItemRules.bagCapacity(nil, bonus)).toBe(pockets + bonus)
			local backpack = item("backpack_small", 4)
			expect(ItemRules.bagCapacity(backpack) > pockets).toBe(true)
			expect(ItemRules.bagCapacity(backpack, bonus)).toBe(ItemRules.bagCapacity(backpack) + bonus)
			local inventory = InventoryLogic.new({ backpack = backpack }, {})
			local before = InventoryLogic.capacity(inventory)
			inventory.bonusUp += bonus
			expect(InventoryLogic.capacity(inventory)).toBe(before + bonus)
			expect(InventoryLogic.free(inventory)).toBe(before + bonus)
		end)

		it("refusé une deuxième fois dans la même partie, avec une raison explicite", function()
			expect(ConsumableRules.refusal(exo.effect, fighter())).toBe(nil)
			expect(ConsumableRules.refusal(exo.effect, fighter({ exoUsed = true }))).toBe("exo_used")
			-- Les autres consommables gardent leurs refus.
			local heal = Config.Equipment.consumables.nanite_injector.effect
			expect(ConsumableRules.refusal(heal, fighter())).toBe("useless")
			expect(ConsumableRules.refusal(heal, fighter({ health = 40 }))).toBe(nil)
		end)

		it("surcapacité : le sac rempli grâce au bonus ne peut pas être retiré", function()
			local backpack = item("backpack_small", 4)
			local inventory = InventoryLogic.new({ backpack = backpack }, {})
			inventory.bonusUp = bonus
			-- Remplir au-delà des poches seules (bonus compris).
			local index = 0
			while InventoryLogic.free(inventory) > 0 do
				index += 1
				local ok =
					InventoryLogic.store(inventory, { uid = "n" .. index, itemId = "nanite_injector", stack = 1 })
				if not ok then
					break
				end
			end
			expect(InventoryLogic.used(inventory) > ItemRules.bagCapacity(nil, bonus)).toBe(true)
			local taken, reason = InventoryLogic.take(inventory, backpack.uid)
			expect(taken).toBe(nil)
			expect(reason).toBe("too_small")
		end)

		it("une partie repart d'un sac sans bonus", function()
			expect(InventoryLogic.new({}, {}).bonusUp).toBe(0)
		end)

		it("obtenable : butin et caisse gratuite", function()
			local inPool = false
			for _, id in Config.Economy.freeCrate.tempItemPool do
				inPool = inPool or id == "exo_harness"
			end
			expect(inPool).toBe(true)
		end)
	end)

	describe("ItemFactory", function()
		local generated = 0
		H.setService("HttpService", {
			GenerateGUID = function()
				generated += 1
				return string.format("guid-%04d", generated)
			end,
		})
		local ItemFactory = H.require("ServerScriptService/Server/Inventory/ItemFactory")
		local Config = H.require("ReplicatedStorage/Shared/Config")

		it("uid uniques sur 1 000 créations (générés par le serveur)", function()
			local seen = {}
			for _ = 1, 1000 do
				local created = ItemFactory.create("cell_light")
				expect(seen[created.uid]).toBeNil()
				seen[created.uid] = true
			end
		end)

		it("pile bornée par stackSize ; pile pleine par défaut ; état par défaut", function()
			expect(ItemFactory.create("nanite_injector", { stack = 99 }).stack).toBe(3)
			expect(ItemFactory.create("nanite_injector", { stack = 0 }).stack).toBe(1)
			expect(ItemFactory.create("nanite_injector").stack).toBe(3)
			local rifle = ItemFactory.create("sentinel_rifle")
			expect(rifle.condition).toBe(Config.Conditions.GOOD)
			expect(rifle.stack).toBeNil()
			expect(rifle.isKit).toBeNil()
			expect(ItemFactory.create("sentinel_rifle", { condition = 5 }).condition).toBe(5)
			-- Sans état (munitions) : jamais de champ `condition`.
			expect(ItemFactory.create("cell_light").condition).toBeNil()
		end)

		it("objet inconnu ou invalide : erreur claire, rien n'est créé", function()
			local ok, message = pcall(ItemFactory.create, "plasma_banana")
			expect(ok).toBe(false)
			expect(string.find(message, "itemId inconnu", 1, true) ~= nil).toBe(true)
			ok, message = pcall(ItemFactory.create, "sentinel_rifle", { condition = 9 })
			expect(ok).toBe(false)
			expect(string.find(message, "objet créé invalide", 1, true) ~= nil).toBe(true)
		end)

		it("kit de base : contenu de Config.Economy.baseKit, tout marqué isKit", function()
			local kit = Config.Economy.baseKit
			local loadout, bag = ItemFactory.createBaseKit()
			expect(loadout.ranged.itemId).toBe(kit.ranged.itemId)
			expect(loadout.ranged.condition).toBe(kit.ranged.condition)
			expect(loadout.melee.itemId).toBe(kit.melee.itemId)
			expect(loadout.backpack.itemId).toBe(kit.backpack.itemId)
			expect(#bag).toBe(#kit.bag)
			for index, entry in kit.bag do
				expect(bag[index].itemId).toBe(entry.itemId)
				expect(bag[index].stack).toBe(entry.stack)
			end
			for _, created in { loadout.ranged, loadout.melee, loadout.backpack, table.unpack(bag) } do
				expect(created.isKit).toBe(true)
			end
		end)
	end)
end
