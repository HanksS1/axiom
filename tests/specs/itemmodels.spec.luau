--!nocheck
-- Apparence des objets : chaque objet du jeu a un modèle valide et cohérent.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local roblox = require("@lune/roblox")
	local Enum, Color3 = roblox.Enum, roblox.Color3
	local Config = H.require("ReplicatedStorage/Shared/Config")
	local ItemCatalog = H.require("ReplicatedStorage/Shared/Items/ItemCatalog")
	local ItemModels = H.require("ReplicatedStorage/Shared/Visuals/ItemModels")

	local ROLES = { body = true, plate = true, dark = true, tape = true, accent = true, glass = true, steel = true }
	local SHAPES = { Cylinder = true, Ball = true }

	local function same(a, b)
		return math.abs(a.R - b.R) < 1e-3 and math.abs(a.G - b.G) < 1e-3 and math.abs(a.B - b.B) < 1e-3
	end

	describe("Apparence des objets", function()
		it("chaque objet du catalogue a un modèle", function()
			local missing = {}
			for id in ItemCatalog.all() do
				if not ItemModels.has(id) then
					table.insert(missing, id)
				end
			end
			table.sort(missing)
			if #missing > 0 then
				error("sans modèle : " .. table.concat(missing, ", "))
			end
		end)

		it("pièces valides : « Body » en premier à l'origine, tailles, rôles, matières, formes", function()
			for id in ItemCatalog.all() do
				local blueprint = ItemModels.blueprint(id)
				local parts = blueprint.parts
				expect(parts[1].name).toBe("Body")
				expect(parts[1].cframe.Position.Magnitude < 0.5).toBe(true)
				if #parts < 3 or #parts > 16 then
					error(`{id} : {#parts} pièces`)
				end
				local accents = 0
				for _, part in parts do
					local size, position = part.size, part.cframe.Position
					for _, value in { size.X, size.Y, size.Z, position.X, position.Y, position.Z } do
						if value ~= value or math.abs(value) > 6 then
							error(`{id}.{part.name} : valeur invalide ({value})`)
						end
					end
					if math.min(size.X, size.Y, size.Z) < 0.02 then
						error(`{id}.{part.name} : pièce trop fine ({size})`)
					end
					if not ROLES[part.role] then
						error(`{id}.{part.name} : rôle inconnu ({part.role})`)
					end
					if part.shape and not SHAPES[part.shape] then
						error(`{id}.{part.name} : forme inconnue ({part.shape})`)
					end
					if part.material and not pcall(function()
						return Enum.Material[part.material]
					end) then
						error(`{id}.{part.name} : matière inconnue ({part.material})`)
					end
					if part.role == "accent" then
						accents += 1
					end
				end
				-- Tout objet porte son accent néon (charte).
				expect(accents >= 1).toBe(true)
			end
		end)

		it("arme à distance : accent = couleur de sa cellule, comme le tracé du tir", function()
			for id, def in Config.Weapons.ranged do
				local blueprint = ItemModels.blueprint(id)
				local cell = Config.Cells[def.cell].color
				expect(same(blueprint.accent, cell)).toBe(true)
				expect(same(Config.Visuals.weapons[id].accent, cell)).toBe(true)
			end
			for id in Config.Weapons.melee do
				expect(same(ItemModels.blueprint(id).accent, Config.Visuals.weapons[id].accent)).toBe(true)
			end
		end)

		it("le cœur d'une arme court sur toute sa longueur (bouche à l'avant du cœur)", function()
			for _, list in { Config.Weapons.ranged, Config.Weapons.melee } do
				for id in list do
					local shape = Config.Visuals.weapons[id]
					local body = ItemModels.blueprint(id).parts[1]
					expect(body.size.Z).toBeNear(shape.size.Z)
					-- Aucune pièce ne dépasse la bouche de plus de quelques centimètres.
					local _, extent = ItemModels.bounds(ItemModels.blueprint(id))
					expect(extent.Z >= shape.size.Z - 1e-3).toBe(true)
				end
			end
			-- Arme à distance : rien ne dépasse nettement devant la bouche.
			for id in Config.Weapons.ranged do
				local muzzle = -Config.Visuals.weapons[id].size.Z / 2
				for _, part in ItemModels.blueprint(id).parts do
					local l = part.cframe.LookVector
					local r, u = part.cframe.RightVector, part.cframe.UpVector
					local reach = (
						math.abs(r.Z) * part.size.X
						+ math.abs(u.Z) * part.size.Y
						+ math.abs(l.Z) * part.size.Z
					) / 2
					if part.cframe.Position.Z - reach < muzzle - 0.12 then
						error(`{id}.{part.name} dépasse la bouche`)
					end
				end
			end
		end)

		it("un skin recolore le corps et l'accent, pas les pièces neutres", function()
			local skin =
				{ color = Color3.fromRGB(10, 200, 30), accent = Color3.fromRGB(250, 10, 250), material = "Fabric" }
			local blueprint = ItemModels.blueprint("sentinel_rifle")
			for _, part in blueprint.parts do
				local color, material = ItemModels.appearance(blueprint, part, skin)
				local plain = ItemModels.appearance(blueprint, part, nil)
				if part.role == "body" then
					expect(same(color, skin.color)).toBe(true)
					expect(material).toBe("Fabric")
				elseif part.role == "accent" then
					expect(same(color, skin.accent)).toBe(true)
					expect(material).toBe("Neon")
				elseif part.role == "dark" or part.role == "steel" or part.role == "tape" then
					expect(same(color, plain)).toBe(true)
				end
			end
		end)

		it("boîte englobante cohérente (cadrage des vignettes)", function()
			for id in ItemCatalog.all() do
				local center, extent = ItemModels.bounds(ItemModels.blueprint(id))
				expect(math.max(extent.X, extent.Y, extent.Z) > 0.3).toBe(true)
				expect(math.max(extent.X, extent.Y, extent.Z) < 6).toBe(true)
				expect(center.Magnitude < 3).toBe(true)
			end
		end)
	end)
end
