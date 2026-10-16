--!nocheck
-- Localisation : parité FR / EN, clés obligatoires, formatage.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local Localization = H.require("ReplicatedStorage/Shared/Localization")
	local Config = H.require("ReplicatedStorage/Shared/Config")
	local ItemCatalog = H.require("ReplicatedStorage/Shared/Items/ItemCatalog")

	describe("Localization", function()
		it("FR et EN ont exactement les mêmes clés", function()
			local tables = Localization._tables()
			for key in tables.fr do
				if tables.en[key] == nil then
					error("clé absente en EN : " .. key)
				end
			end
			for key in tables.en do
				if tables.fr[key] == nil then
					error("clé absente en FR : " .. key)
				end
			end
		end)

		it('chaque clé écrite en toutes lettres dans le client (t("…")) existe', function()
			local fs = require("@lune/fs")
			local tables = Localization._tables()
			local missing = {}
			local function scan(dir)
				for _, entry in fs.readDir(dir) do
					local path = dir .. "/" .. entry
					if fs.isDir(path) then
						scan(path)
					elseif string.sub(entry, -5) == ".luau" then
						local source = fs.readFile(path)
						-- t("clé") ou t("clé", …) : clé littérale complète (pas de « .. »).
						for key in string.gmatch(source, '%f[%w_]t%("([%w%._]+)"%s*[,%)]') do
							if tables.fr[key] == nil then
								table.insert(missing, `{path} : {key}`)
							end
						end
					end
				end
			end
			scan("src/Client")
			table.sort(missing)
			expect(table.concat(missing, "\n")).toBe("")
		end)

		it("mêmes paramètres {x} dans les deux langues", function()
			local tables = Localization._tables()
			for key, fr in tables.fr do
				local function params(text)
					local found = {}
					for name in string.gmatch(text, "{(%w+)}") do
						found[name] = true
					end
					return found
				end
				local a, b = params(fr), params(tables.en[key])
				for name in a do
					if not b[name] then
						error(key .. " : paramètre {" .. name .. "} absent en EN")
					end
				end
				for name in b do
					if not a[name] then
						error(key .. " : paramètre {" .. name .. "} absent en FR")
					end
				end
			end
		end)

		it("chaque objet, état, mode, robot et rang a un nom traduit", function()
			for _, lang in Localization.languages do
				for itemId in ItemCatalog.all() do
					expect(Localization.has(lang, "item." .. itemId)).toBe(true)
				end
				for _, condition in Config.Conditions.list do
					expect(Localization.has(lang, "condition." .. condition.key)).toBe(true)
				end
				for _, modeId in Config.Modes.list do
					expect(Localization.has(lang, "mode." .. modeId)).toBe(true)
				end
				for robotId in Config.Robots.byId do
					expect(Localization.has(lang, "robot." .. robotId)).toBe(true)
				end
				for _, rank in Config.Progression.season.ranks do
					expect(Localization.has(lang, "rank." .. rank.id)).toBe(true)
				end
			end
		end)

		it("résolution de la langue", function()
			expect(Localization.resolve("auto", "fr-fr")).toBe("fr")
			expect(Localization.resolve("auto", "fr-ca")).toBe("fr")
			expect(Localization.resolve("auto", "en-us")).toBe("en")
			expect(Localization.resolve("auto", "de-de")).toBe("en")
			expect(Localization.resolve("en", "fr-fr")).toBe("en")
			expect(Localization.resolve(nil, nil)).toBe("en")
		end)

		it("formatage des nombres", function()
			expect(Localization.formatNumber("en", 2450)).toBe("2,450")
			expect(Localization.formatNumber("fr", 2450)).toBe("2\u{202F}450")
			expect(Localization.formatNumber("en", 1234567)).toBe("1,234,567")
			expect(Localization.formatNumber("en", 999)).toBe("999")
			expect(Localization.formatNumber("en", 0)).toBe("0")
			expect(Localization.formatNumber("en", -1500)).toBe("-1,500")
			expect(Localization.formatNumber("fr", 4.5)).toBe("4,5")
			expect(Localization.formatNumber("en", 0.25)).toBe("0.25")
			expect(Localization.formatNumber("en", 1.999)).toBe("2")
			expect(Localization.formatNumber("en", 0 / 0)).toBe("?")
		end)

		it("substitution des paramètres", function()
			expect(Localization.get("fr", "mode.refused.score_too_high", { score = 2450, limit = 2000 })).toBe(
				"SE trop élevé : 2\u{202F}450 / 2\u{202F}000 max"
			)
			expect(Localization.get("en", "common.level", { level = 3 })).toBe("Level 3")
			-- Paramètre manquant : le motif reste visible.
			expect(Localization.get("en", "common.level", {})).toBe("Level {level}")
		end)

		it("clé inconnue : retourne la clé et avertit", function()
			expect(Localization.get("fr", "cle.inexistante")).toBe("cle.inexistante")
		end)
	end)
end
