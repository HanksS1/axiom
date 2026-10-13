--!nocheck
-- Cartes : repères, caisses posées sur un sol, bornes, nombre de pièces, habillage
-- (décors valides, qui ne recouvrent aucun repère et ne coupent aucun accès).

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local roblox = require("@lune/roblox")
	local Vector3, Enum = roblox.Vector3, roblox.Enum
	local Config = H.require("ReplicatedStorage/Shared/Config")
	local Registry = H.require("ServerScriptService/Server/Maps/Registry")
	local LayoutBuilder = H.require("ServerScriptService/Server/Maps/LayoutBuilder")

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
			local layout = build(LayoutBuilder.random(def.seed))
			local byTag = {}
			for _, marker in layout.markers do
				byTag[marker.tag] = byTag[marker.tag] or {}
				table.insert(byTag[marker.tag], marker)
			end

			it(
				"repères : 8 départs doubles (duo), 3 extractions, 6 Accélérateurs, 2 ou 3 zones à risque",
				function()
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
				end
			)

			it("solo : 16 points de départ répartis sur toute la carte", function()
				local solo = byTag.SoloSpawn or {}
				expect(#solo).toBe(16)
				local inner, quadrants = 0, {}
				for index, marker in solo do
					local p = marker.cframe.Position
					if math.max(math.abs(p.X), math.abs(p.Z)) < 200 then
						inner += 1
					end
					quadrants[(if p.X < 0 then "w" else "e") .. (if p.Z < 0 then "s" else "n")] = true
					-- Espacés les uns des autres.
					for other = index + 1, #solo do
						local q = solo[other].cframe.Position
						if (Vector3.new(p.X, 0, p.Z) - Vector3.new(q.X, 0, q.Z)).Magnitude < 50 then
							error(`points de départ trop proches : {p} et {q}`)
						end
					end
					-- Loin des extractions et hors des zones à risque.
					for _, extraction in byTag.ExtractionPoint do
						local e = extraction.cframe.Position
						expect((Vector3.new(p.X, 0, p.Z) - Vector3.new(e.X, 0, e.Z)).Magnitude >= 45).toBe(true)
					end
					for _, zone in byTag.RiskZone do
						local z = zone.cframe.Position
						local distance = (Vector3.new(p.X, 0, p.Z) - Vector3.new(z.X, 0, z.Z)).Magnitude
						expect(distance >= zone.attributes.Radius + 45).toBe(true)
					end
					-- Hors des zones dangereuses (radiation, métal en fusion).
					for _, hazard in layout.hazards do
						local dx, dz = math.abs(p.X - hazard.center.X), math.abs(p.Z - hazard.center.Z)
						if hazard.radius then
							expect(math.sqrt(dx * dx + dz * dz) > hazard.radius).toBe(true)
						else
							expect(dx > hazard.size.X / 2 or dz > hazard.size.Z / 2).toBe(true)
						end
					end
				end
				-- Pas seulement en bordure : des points au cœur de la carte, dans les 4 quarts.
				expect(inner >= 3).toBe(true)
				expect(quadrants.ws and quadrants.wn and quadrants.es and quadrants.en).toBe(true)
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
				for _, tag in { "CrateSpawn", "ExtractionPoint", "AcceleratorSpot", "DeploySpawn", "SoloSpawn" } do
					for _, marker in byTag[tag] do
						local p = marker.cframe.Position
						local y = p.Y
						if tag == "DeploySpawn" or tag == "SoloSpawn" then
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
				if #layout.parts > 6000 then
					error(`{#layout.parts} pièces`)
				end
			end)

			it("pièces valides : taille, position, matériau, forme, particules", function()
				local emitters = {}
				for _, name in LayoutBuilder.emitterNames do
					emitters[name] = true
				end
				local shapes = { Block = true, Ball = true, Cylinder = true, Wedge = true, CornerWedge = true }
				local materials = {}
				for _, part in layout.parts do
					local size, p = part.size, part.cframe.Position
					for _, value in { size.X, size.Y, size.Z, p.X, p.Y, p.Z } do
						if value ~= value or math.abs(value) > 2048 then
							error(`{part.name} : valeur invalide ({value})`)
						end
					end
					if math.min(size.X, size.Y, size.Z) < 0.05 then
						error(`{part.name} : taille trop petite ({size})`)
					end
					if math.abs(p.X) > HALF + 3 or math.abs(p.Z) > HALF + 3 then
						error(`{part.name} hors de la carte : {p}`)
					end
					if part.shape and not shapes[part.shape] then
						error(`{part.name} : forme inconnue ({part.shape})`)
					end
					if part.emitter and not emitters[part.emitter] then
						error(`{part.name} : particules inconnues ({part.emitter})`)
					end
					if materials[part.material] == nil then
						materials[part.material] = pcall(function()
							return Enum.Material[part.material]
						end)
					end
					if not materials[part.material] then
						error(`{part.name} : matériau inconnu ({part.material})`)
					end
				end
			end)

			it("aucune pièce solide ne recouvre un repère (décors tournés compris)", function()
				local problems = {}
				for _, tag in
					{ "CrateSpawn", "ExtractionPoint", "AcceleratorSpot", "DeploySpawn", "SoloSpawn", "RobotSpawn" }
				do
					for _, marker in byTag[tag] or {} do
						local p = marker.cframe.Position
						local y = p.Y
						if tag == "DeploySpawn" or tag == "SoloSpawn" then
							y -= 3
						elseif tag == "RobotSpawn" then
							y -= 1
						elseif tag ~= "CrateSpawn" then
							y -= 0.2
						end
						-- À hauteur de poitrine, et à hauteur de genou.
						for _, height in { 1.6, 0.8 } do
							local point = Vector3.new(p.X, y + height, p.Z)
							for _, part in layout.parts do
								if part.collide ~= false then
									local centre = part.cframe.Position
									-- Rejet rapide par la sphère englobante.
									if (centre - point).Magnitude <= part.size.Magnitude / 2 then
										local l = part.cframe:PointToObjectSpace(point)
										local half = part.size / 2
										if
											math.abs(l.X) < half.X - 0.05
											and math.abs(l.Y) < half.Y - 0.05
											and math.abs(l.Z) < half.Z - 0.05
										then
											table.insert(problems, `{tag} dans {part.name} en {p}`)
										end
									end
								end
							end
						end
					end
				end
				if #problems > 0 then
					error(table.concat(problems, "\n    "))
				end
			end)

			it("zones d'extraction dégagées (aucun décor dans le cercle)", function()
				for _, marker in byTag.ExtractionPoint do
					local p = marker.cframe.Position
					for _, part in layout.parts do
						if part.collide ~= false then
							local centre, half = part.cframe.Position, part.size / 2
							local reach = math.max(half.X, half.Z)
							local flat = Vector3.new(centre.X - p.X, 0, centre.Z - p.Z).Magnitude
							-- Petites pièces posées au niveau de la zone (les sols et les murs porteurs sont plus grands).
							if
								flat < 7
								and reach < 6
								and centre.Y + half.Y > p.Y + 0.6
								and centre.Y - half.Y < p.Y + 5
							then
								error(`{part.name} dans la zone d'extraction {marker.attributes.NameKey}`)
							end
						end
					end
				end
			end)

			it("budget de lumières et de particules (mobile)", function()
				local lights, emitters = 0, 0
				for _, part in layout.parts do
					if part.light then
						lights += 1
					end
					if part.emitter then
						emitters += 1
					end
				end
				if lights > 200 then
					error(`{lights} lumières`)
				end
				if emitters > 80 then
					error(`{emitters} émetteurs de particules`)
				end
			end)

			it("couverts légers présents (Canon à rayons X)", function()
				local count = 0
				for _, part in layout.parts do
					if part.tags and table.find(part.tags, "LightCover") then
						count += 1
					end
				end
				expect(count >= 30).toBe(true)
			end)

			it("les repères au sol restent accessibles à pied depuis un point de départ", function()
				-- Grille de 2 studs : une case est bloquée si une pièce solide occupe la
				-- hauteur d'un personnage (boîtes englobantes : estimation pessimiste).
				local CELL = 2
				local N = Config.Maps.size / CELL
				local blocked = table.create(N * N, false)
				local function cell(v)
					return math.clamp(math.floor((v + HALF) / CELL), 0, N - 1)
				end
				for _, part in layout.parts do
					if part.collide ~= false then
						local cf, size = part.cframe, part.size
						local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
						local ex = (math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z) / 2
						local ey = (math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z) / 2
						local ez = (math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z) / 2
						local p = cf.Position
						-- Entre le genou et la tête ; une marche basse ne bloque pas.
						if p.Y + ey > 2.4 and p.Y - ey < 4.6 then
							for cx = cell(p.X - ex), cell(p.X + ex) do
								for cz = cell(p.Z - ez), cell(p.Z + ez) do
									blocked[cx * N + cz + 1] = true
								end
							end
						end
					end
				end
				local reached = table.create(N * N, false)
				local queue, head = {}, 1
				for _, marker in byTag.DeploySpawn do
					local p = marker.cframe.Position
					local index = cell(p.X) * N + cell(p.Z) + 1
					if not blocked[index] and not reached[index] then
						reached[index] = true
						table.insert(queue, index)
					end
				end
				while head <= #queue do
					local index = queue[head]
					head += 1
					local cx, cz = math.floor((index - 1) / N), (index - 1) % N
					for _, step in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
						local nx, nz = cx + step[1], cz + step[2]
						if nx >= 0 and nx < N and nz >= 0 and nz < N then
							local nextIndex = nx * N + nz + 1
							if not blocked[nextIndex] and not reached[nextIndex] then
								reached[nextIndex] = true
								table.insert(queue, nextIndex)
							end
						end
					end
				end
				local problems = {}
				for _, tag in
					{ "CrateSpawn", "ExtractionPoint", "AcceleratorSpot", "DeploySpawn", "SoloSpawn", "RobotSpawn" }
				do
					for _, marker in byTag[tag] or {} do
						local p = marker.cframe.Position
						-- Repères au niveau du sol seulement (étages, toits et cratère : par les rampes).
						if p.Y > -0.5 and p.Y < 3.6 then
							local ok = false
							for dx = -1, 1 do
								for dz = -1, 1 do
									local cx, cz = cell(p.X) + dx, cell(p.Z) + dz
									if cx >= 0 and cx < N and cz >= 0 and cz < N and reached[cx * N + cz + 1] then
										ok = true
									end
								end
							end
							if not ok then
								table.insert(problems, `{tag} inaccessible en {p}`)
							end
						end
					end
				end
				if #problems > 0 then
					error(#problems .. " repère(s) :\n    " .. table.concat(problems, "\n    "))
				end
			end)

			it("construction déterministe (même graine)", function()
				local again = build(LayoutBuilder.random(def.seed))
				expect(#again.parts).toBe(#layout.parts)
				expect(#again.markers).toBe(#layout.markers)
			end)
		end)
	end
end
