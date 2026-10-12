--!nocheck
-- Cartes greybox : repères, caisses posées sur un sol, bornes, nombre de pièces.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local Config = H.require("ReplicatedStorage/Shared/Config")
	local Registry = H.require("ServerScriptService/Server/Maps/Registry")

	local HALF = Config.Maps.size / 2

	-- Pièce alignée sur les axes (pas de rotation) ?
	local function axisAligned(cframe)
		local up, look = cframe.UpVector, cframe.LookVector
		return math.abs(up.Y - 1) < 1e-3 and math.abs(look.Z + 1) < 1e-3
	end

	local function contains(part, x, y, z, margin)
		local half = part.size / 2
		local center = part.cframe.Position
		return math.abs(x - center.X) <= half.X + margin
			and math.abs(z - center.Z) <= half.Z + margin
			and math.abs(y - center.Y) <= half.Y + margin
	end

	-- Un sol (dessus d'une pièce alignée) juste sous le point, et rien de solide autour.
	local function supported(layout, x, y, z)
		local floor = false
		for _, part in layout.parts do
			if part.collide ~= false and axisAligned(part.cframe) and part.group == nil then
				local center, half = part.cframe.Position, part.size / 2
				local top = center.Y + half.Y
				if
					math.abs(x - center.X) <= half.X
					and math.abs(z - center.Z) <= half.Z
					and y - top >= -0.6
					and y - top <= 1.2
				then
					floor = true
				end
			end
		end
		return floor
	end

	local function obstructed(layout, x, y, z)
		for _, part in layout.parts do
			if part.collide ~= false and axisAligned(part.cframe) and contains(part, x, y + 1.6, z, -0.05) then
				return part.name
			end
		end
		return nil
	end

	for _, mapId in Config.Maps.list do
		local build = Registry[mapId]
		if build == nil then
			continue
		end
		describe("Carte " .. mapId, function()
			local def = Config.Maps.byId[mapId]
			local layout = build(H.FakeRandom.new(def.seed))
			local byTag = {}
			for _, marker in layout.markers do
				byTag[marker.tag] = byTag[marker.tag] or {}
				table.insert(byTag[marker.tag], marker)
			end

			it("repères : 8 départs, 3 extractions, 6 Accélérateurs, 2 ou 3 zones à risque", function()
				expect(#byTag.DeploySpawn).toBe(8)
				expect(#byTag.ExtractionPoint).toBe(3)
				expect(#byTag.AcceleratorSpot).toBe(6)
				local zones, main = #byTag.RiskZone, 0
				for _, zone in byTag.RiskZone do
					if zone.attributes.Main then
						main += 1
					end
				end
				expect(zones >= 2 and zones <= 3).toBe(true)
				expect(main).toBe(1)
				local names = {}
				for _, marker in byTag.ExtractionPoint do
					local key = marker.attributes.NameKey
					expect(type(key)).toBe("string")
					expect(names[key]).toBeNil()
					names[key] = true
				end
			end)

			it("environ 60 caisses de types connus", function()
				local count = #byTag.CrateSpawn
				if count < 50 or count > 75 then
					error(`{count} caisses`)
				end
				for _, marker in byTag.CrateSpawn do
					expect(Config.Loot.crates[marker.attributes.CrateType] ~= nil).toBe(true)
				end
			end)

			it("tout est dans les limites ; départs en bordure", function()
				for _, marker in layout.markers do
					local p = marker.cframe.Position
					if math.abs(p.X) > HALF - 5 or math.abs(p.Z) > HALF - 5 then
						error(`{marker.tag} hors limites : {p}`)
					end
				end
				for _, marker in byTag.DeploySpawn do
					local p = marker.cframe.Position
					expect(math.max(math.abs(p.X), math.abs(p.Z)) >= 340).toBe(true)
				end
			end)

			it("caisses, extractions, Accélérateurs et départs posés sur un sol libre", function()
				local problems = {}
				for _, tag in { "CrateSpawn", "ExtractionPoint", "AcceleratorSpot", "DeploySpawn" } do
					for _, marker in byTag[tag] do
						local p = marker.cframe.Position
						local y = p.Y
						if tag == "DeploySpawn" then
							y -= 3
						elseif tag ~= "CrateSpawn" then
							y -= 0.2
						end
						local where = string.format("(%.0f, %.1f, %.0f)", p.X, y, p.Z)
						if not supported(layout, p.X, y, p.Z) then
							table.insert(problems, `{tag} sans sol en {where}`)
						end
						local blocker = obstructed(layout, p.X, y, p.Z)
						if blocker then
							table.insert(problems, `{tag} dans {blocker} en {where}`)
						end
					end
				end
				if #problems > 0 then
					error(table.concat(problems, "\n    "))
				end
			end)

			it("budget de pièces raisonnable", function()
				if #layout.parts > 2600 then
					error(`{#layout.parts} pièces`)
				end
			end)

			it("construction déterministe (même graine)", function()
				local again = build(H.FakeRandom.new(def.seed))
				expect(#again.parts).toBe(#layout.parts)
				expect(#again.markers).toBe(#layout.markers)
			end)
		end)
	end
end
