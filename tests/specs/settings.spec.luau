--!nocheck
-- Paramètres : touches personnalisées, disposition tactile, validation serveur.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local Bindings = H.require("ReplicatedStorage/Shared/Input/Bindings")
	local TouchLayout = H.require("ReplicatedStorage/Shared/Input/TouchLayout")
	local SettingRules = H.require("ReplicatedStorage/Shared/Settings/SettingRules")
	local Config = H.require("ReplicatedStorage/Shared/Config")

	describe("Touches", function()
		it("les touches par défaut sont autorisées et uniques par périphérique", function()
			for _, slot in { "keyboard", "gamepad" } do
				local seen = {}
				for _, action in Bindings.actions do
					local name = Bindings.defaults[action][slot]
					if name then
						expect(Bindings.isAllowed(slot, name)).toBe(true)
						expect(seen[name]).toBeNil()
						seen[name] = true
					end
				end
			end
		end)

		it("réassigner une touche déjà prise l'échange", function()
			local overrides = Bindings.assign({}, "reload", "keyboard", "F") -- F = parade par défaut
			local resolved = Bindings.resolve(overrides)
			expect(resolved.reload.keyboard).toBe("F")
			expect(resolved.parry.keyboard).toBe("R")
			expect(Bindings.validate(overrides)).toBe(true)
		end)

		it("revenir aux touches par défaut ne laisse aucune différence", function()
			local overrides = Bindings.assign({}, "reload", "keyboard", "G")
			overrides = Bindings.assign(overrides, "reload", "keyboard", "R")
			expect(next(overrides)).toBeNil()
		end)

		it("désassigner (« none »)", function()
			local overrides = Bindings.assign({}, "heal", "keyboard", "none")
			expect(Bindings.resolve(overrides).heal.keyboard).toBeNil()
			expect(Bindings.validate(overrides)).toBe(true)
		end)

		it("valeurs envoyées par un client modifié : refusées", function()
			expect(Bindings.validate({ fire = { keyboard = "W" } })).toBe(false) -- déplacement
			expect(Bindings.validate({ fire = { gamepad = "ButtonA" } })).toBe(false) -- saut
			expect(Bindings.validate({ hack = { keyboard = "G" } })).toBe(false)
			expect(Bindings.validate({ fire = { keyboard = "G", extra = "x" } })).toBe(false)
			expect(Bindings.validate({ fire = { keyboard = 5 } })).toBe(false)
			expect(Bindings.validate("G")).toBe(false)
		end)
	end)

	describe("Disposition tactile", function()
		it("positions et tailles bornées", function()
			expect(TouchLayout.validate({ fire = { x = 0.8, y = 0.7, s = 1.2 } })).toBe(true)
			expect(TouchLayout.validate({ fire = { x = 1.4, y = 0.7, s = 1 } })).toBe(false)
			expect(TouchLayout.validate({ fire = { x = 0.5, y = 0.5, s = 3 } })).toBe(false)
			expect(TouchLayout.validate({ fire = { x = 0 / 0, y = 0.5, s = 1 } })).toBe(false)
			expect(TouchLayout.validate({ fire = { x = 0.5, y = 0.5, s = 1, z = 2 } })).toBe(false)
			expect(TouchLayout.validate({ jump = { x = 0.5, y = 0.5, s = 1 } })).toBe(false)
		end)
	end)

	describe("Validation des paramètres", function()
		it("chaque valeur par défaut est valide", function()
			for key in Config.Settings do
				expect(SettingRules.isValid(key, SettingRules.default(key))).toBe(true)
			end
		end)

		it("paramètre inconnu ou hors bornes : refusé", function()
			expect(SettingRules.isValid("godMode", true)).toBe(false)
			expect(SettingRules.isValid("mouseSensitivity", 99)).toBe(false)
			expect(SettingRules.isValid("language", "de")).toBe(false)
			expect(SettingRules.isValid("keybinds", { fire = { keyboard = "G" } })).toBe(true)
		end)
	end)

	describe("Touche d'inventaire", function()
		it("I par défaut ; Tab refusée (réservée par Roblox à la liste des joueurs)", function()
			expect(Bindings.defaults.inventory.keyboard).toBe("I")
			expect(Bindings.isAllowed("keyboard", "Tab")).toBe(false)
			expect(Bindings.isAllowed("keyboard", "I")).toBe(true)
		end)
	end)
end
