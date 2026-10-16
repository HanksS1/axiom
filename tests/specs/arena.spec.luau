--!nocheck
-- Arène FFA : plan (enceinte, repères, couverts, décor) et règles FFA.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local roblox = require("@lune/roblox")
	local Vector3 = roblox.Vector3
	local Config = H.require("ReplicatedStorage/Shared/Config")
	local LayoutBuilder = H.require("ServerScriptService/Server/Maps/LayoutBuilder")
	local ArenaLayout = H.require("ServerScriptService/Server/Maps/ArenaLayout")

	local A = Config.Arena
	local HALF = Config.Dev.arenaSize / 2
	local layout = ArenaLayout.build(LayoutBuilder.random(A.seed))

	local function inside(spec, point, margin)
		local p = spec.cframe:PointToObjectSpace(point)
		local h = spec.size / 2
		return math.abs(p.X) <= h.X + margin and math.abs(p.Y) <= h.Y + margin and math.abs(p.Z) <= h.Z + margin
	end

	local function solid(spec)
		return spec.collide ~= false
	end

	local ENCLOSURE = { Floor = true, Ceiling = true }
	local function isEnclosure(spec)
		return ENCLOSURE[spec.name] or string.match(spec.name, "^Wall%d") or string.match(spec.name, "^Barrier%d")
	end

	describe("Arène FFA : plan", function()
		it("repères de l'ancienne arène conservés (sert aussi de petite carte en Studio)", function()
			local count = {}
			for _, marker in layout.markers do
				count[marker.tag] = (count[marker.tag] or 0) + 1
			end
			expect(count.DeploySpawn).toBe(8)
			expect(count.ExtractionPoint).toBe(3)
			expect(count.AcceleratorSpot).toBe(6)
			expect(count.RiskZone).toBe(2)
			expect(count.RobotSpawn).toBe(4)
			expect(count.CrateSpawn).toBeNil() -- bac à sable : aucun butin
		end)

		it("enceinte fermée : ni bottes de saut ni grappin ne font sortir de l'arène", function()
			local barriers, ceiling = 0, nil
			local highest = 0
			for _, spec in layout.parts do
				if string.match(spec.name, "^Barrier%d") then
					barriers += 1
					expect(spec.collide ~= false).toBe(true)
					expect(spec.query).toBe(false) -- le grappin (rayon) ne peut pas s'y accrocher
					expect(spec.transparency).toBe(1)
					local top = spec.cframe.Position.Y + spec.size.Y / 2
					expect(top >= A.ceiling).toBe(true)
				elseif spec.name == "Ceiling" then
					ceiling = spec
				elseif solid(spec) and not isEnclosure(spec) then
					highest = math.max(highest, spec.cframe.Position.Y + spec.size.Y / 2)
				end
			end
			expect(barriers).toBe(4)
			expect(ceiling ~= nil and ceiling.query == false and ceiling.collide ~= false).toBe(true)
			-- Point le plus haut atteignable : sommet du plus haut décor + bottes de saut
			-- en parfait état + saut normal.
			local maxEfficiency = 0
			for _, condition in Config.Conditions.list do
				maxEfficiency = math.max(maxEfficiency, condition.efficiency)
			end
			local boots = Config.Equipment.gadgets.jump_boots.stats.jumpHeight * maxEfficiency
			local reach = highest + boots + Config.Combat.movement.jumpHeight
			expect(A.ceiling >= reach).toBe(true)
		end)

		it("décor pur : ni collision ni blocage des tirs ; néons jamais solides", function()
			for _, spec in layout.parts do
				if spec.collide == false then
					expect(spec.query).toBe(false)
				end
				if spec.material == "Neon" then
					expect(spec.collide).toBe(false)
				end
			end
		end)

		it("points de départ dégagés et posés sur le sol", function()
			for _, marker in layout.markers do
				if marker.tag == "DeploySpawn" then
					local p = marker.cframe.Position
					for _, spec in layout.parts do
						if solid(spec) and spec.name ~= "Floor" then
							for _, y in { -1.5, 0, 1.5 } do
								expect(inside(spec, p + Vector3.new(0, y, 0), 0.5)).toBe(false)
							end
						end
					end
					expect(math.abs(p.X) < HALF - 2 and math.abs(p.Z) < HALF - 2).toBe(true)
				end
			end
		end)

		it("mannequins d'entraînement : leur zone reste dégagée", function()
			for _, dummy in Config.Dev.dummies do
				for _, spec in layout.parts do
					if solid(spec) and spec.name ~= "Floor" then
						for _, offset in { Vector3.new(0, 0, 0), Vector3.new(0, 2, -6), Vector3.new(0, 2, 6) } do
							expect(inside(spec, dummy.position + offset, 1)).toBe(false)
						end
					end
				end
			end
		end)

		it("jouable : hauteurs accessibles et couverts en nombre", function()
			local elevated, cover = {}, 0
			for _, spec in layout.parts do
				if solid(spec) and not isEnclosure(spec) then
					local top = spec.cframe.Position.Y + spec.size.Y / 2
					if string.match(spec.name, "^Bastion%d$") or spec.name == "Platform" or spec.name == "Bridge" then
						table.insert(elevated, spec.name)
						expect(top >= 6).toBe(true)
					end
					if spec.size.Y >= 3 and top <= 14 then
						cover += 1
					end
				end
			end
			-- Trois bastions, la plateforme nord-est, la passerelle.
			expect(#elevated).toBe(5)
			expect(cover >= 20).toBe(true)
			-- Chaque hauteur a sa rampe.
			local ramps = 0
			for _, spec in layout.parts do
				if string.match(spec.name, "Ramp") then
					ramps += 1
				end
			end
			expect(ramps >= 6).toBe(true)
		end)

		it("décor animé côté client (néons qui grésillent, hologramme, étincelles) et lumière", function()
			local tags, lights = {}, 0
			for _, spec in layout.parts do
				for _, tag in spec.tags or {} do
					tags[tag] = (tags[tag] or 0) + 1
				end
				if spec.light then
					lights += 1
				end
			end
			expect(tags.Flicker >= 4).toBe(true)
			expect(tags.Spin >= 1 and tags.Hologram >= 1 and tags.SparkBurst >= 1).toBe(true)
			expect(tags.LightCover >= 6).toBe(true)
			expect(lights >= 12).toBe(true)
		end)

		it("construction déterministe (même graine)", function()
			local again = ArenaLayout.build(LayoutBuilder.random(A.seed))
			expect(#again.parts).toBe(#layout.parts)
			expect(#again.markers).toBe(#layout.markers)
		end)
	end)

	describe("Arène FFA : éclairage local (LightingOverlay)", function()
		local LightingOverlay = H.require("ReplicatedStorage/Shared/Visuals/LightingOverlay")
		local Color3 = roblox.Color3

		-- Éclairage « serveur » simulé (Terminus).
		local function hubLighting()
			return LightingOverlay.properties(Config.Maps.hub.lighting)
		end

		it("plus lumineux que le Terminus et sans brouillard à l'échelle de l'arène", function()
			local arena, hub = A.lighting, Config.Maps.hub.lighting
			expect(arena.brightness > hub.brightness).toBe(true)
			expect(arena.fogEnd >= Config.Dev.arenaSize * 4).toBe(true)
			local function luma(c)
				return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
			end
			expect(luma(arena.ambient) > luma(hub.ambient)).toBe(true)
		end)

		it("entrée : valeurs de l'arène écrites, celles du serveur mémorisées ; sortie : rétablies", function()
			local lighting = hubLighting()
			local overlay = LightingOverlay.new(A.lighting)
			local writes = LightingOverlay.enter(overlay, function(property)
				return lighting[property]
			end)
			expect(writes.Brightness).toBe(A.lighting.brightness)
			for property, value in writes do
				lighting[property] = value
			end
			-- Notre propre écriture ne se fait pas passer pour un changement du serveur.
			expect(LightingOverlay.serverChanged(overlay, "Brightness", A.lighting.brightness)).toBe(false)
			for property, value in LightingOverlay.exit(overlay) do
				lighting[property] = value
			end
			for property, value in hubLighting() do
				expect(lighting[property]).toBe(value)
			end
			expect(overlay.active).toBe(false)
		end)

		it(
			"partie lancée pendant qu'on est dans l'arène : l'arène reste lisible, la sortie rend l'éclairage de la carte",
			function()
				local overlay = LightingOverlay.new(A.lighting)
				LightingOverlay.enter(overlay, function(property)
					return hubLighting()[property]
				end)
				-- Le serveur applique l'éclairage d'une carte : réplication.
				local mapAmbient = Color3.fromRGB(10, 10, 20)
				expect(LightingOverlay.serverChanged(overlay, "Ambient", mapAmbient)).toBe(true) -- réécrire l'arène
				expect(LightingOverlay.serverChanged(overlay, "Brightness", 0.4)).toBe(true)
				local restored = LightingOverlay.exit(overlay)
				expect(restored.Ambient).toBe(mapAmbient)
				expect(restored.Brightness).toBe(0.4)
				-- Hors superposition, plus rien n'est intercepté.
				expect(LightingOverlay.serverChanged(overlay, "Ambient", Color3.new(1, 1, 1))).toBe(false)
			end
		)
	end)

	describe("Arène FFA : bouclier de réapparition (SpawnShield)", function()
		local SpawnShield = H.require("ReplicatedStorage/Shared/Combat/SpawnShield")

		it("1,5 s, seulement dans l'arène", function()
			expect(A.spawnShield).toBe(1.5)
			expect(SpawnShield.grant(100, "arena")).toBe(101.5)
			for _, zone in { "hub", "match", "tutorial" } do
				expect(SpawnShield.grant(100, zone)).toBeNil()
			end
		end)

		it("protège pendant le délai, plus après ; jamais hors de l'arène (partie lancée entre-temps)", function()
			local untilTime = SpawnShield.grant(100, "arena")
			expect(SpawnShield.protects(untilTime, 100.2, "arena")).toBe(true)
			expect(SpawnShield.protects(untilTime, 101.6, "arena")).toBe(false)
			expect(SpawnShield.protects(untilTime, 100.2, "match")).toBe(false)
			expect(SpawnShield.protects(nil, 100.2, "arena")).toBe(false)
		end)

		it("tombe à la première attaque (tir, coup, gadget), pas en se déplaçant ni en se soignant", function()
			for _, action in { "fire", "melee", "gadget" } do
				expect(SpawnShield.dropsOn(action)).toBe(true)
			end
			for _, action in { "move", "parry", "reload", "consumable" } do
				expect(SpawnShield.dropsOn(action)).toBe(false)
			end
		end)
	end)

	describe("Arène FFA : tableau des scores (FfaBoard)", function()
		local FfaBoard = H.require("ReplicatedStorage/Shared/Match/FfaBoard")

		local function board(...)
			local b = FfaBoard.new()
			for index, name in { ... } do
				FfaBoard.join(b, index, name)
			end
			return b
		end

		it("un seul joueur : il se voit avec 0 élimination", function()
			local b = board("Ada")
			local view = FfaBoard.view(b, 1, A.scoreboard.top)
			expect(view.kills).toBe(0)
			expect(#view.top).toBe(1)
			expect(view.top[1].me).toBe(true)
			expect(view.players).toBe(1)
		end)

		it("seules comptent les éliminations entre joueurs présents (ni suicide, ni absent, ni mannequin)", function()
			local b = board("Ada", "Bo")
			expect(FfaBoard.recordKill(b, 1, 2)).toBe(true)
			expect(FfaBoard.recordKill(b, 1, 1)).toBe(false) -- suicide
			expect(FfaBoard.recordKill(b, nil, 2)).toBe(false) -- chute, mannequin…
			expect(FfaBoard.recordKill(b, 3, 2)).toBe(false) -- tueur hors de l'arène
			expect(FfaBoard.recordKill(b, 1, 9)).toBe(false) -- victime hors de l'arène
			expect(FfaBoard.view(b, 1, 5).kills).toBe(1)
		end)

		it("top 5 trié ; à égalité, le premier arrivé à ce score devant", function()
			local b = board("A", "B", "C", "D", "E", "F", "G")
			FfaBoard.recordKill(b, 3, 1)
			FfaBoard.recordKill(b, 5, 1)
			FfaBoard.recordKill(b, 5, 2)
			FfaBoard.recordKill(b, 3, 2) -- C rejoint E à 2, mais après lui
			FfaBoard.recordKill(b, 7, 1)
			local view = FfaBoard.view(b, 6, A.scoreboard.top)
			expect(#view.top).toBe(5)
			expect(view.top[1].name).toBe("E")
			expect(view.top[2].name).toBe("C")
			expect(view.top[3].name).toBe("G")
			expect(view.kills).toBe(0) -- F, hors du top, voit quand même son score
			expect(view.players).toBe(7)
			for _, row in view.top do
				expect(row.me).toBe(false)
			end
		end)

		it("éphémère : quitter l'arène remet le score à zéro", function()
			local b = board("Ada", "Bo")
			FfaBoard.recordKill(b, 1, 2)
			FfaBoard.recordKill(b, 1, 2)
			FfaBoard.leave(b, 1)
			expect(FfaBoard.view(b, 2, 5).players).toBe(1)
			FfaBoard.join(b, 1, "Ada")
			expect(FfaBoard.view(b, 1, 5).kills).toBe(0)
			FfaBoard.join(b, 1, "Ada") -- déjà présent : rien ne change
			expect(FfaBoard.view(b, 1, 5).players).toBe(2)
		end)

		it("jamais écrit dans le profil : ni FfaService ni FfaBoard n'utilisent DataService", function()
			local fs = require("@lune/fs")
			for _, path in { "src/Server/Services/FfaService.luau", "src/Shared/Match/FfaBoard.luau" } do
				local source = fs.readFile(path)
				expect(string.find(source, "require%([^)]*DataService%)")).toBeNil()
				expect(string.find(source, "DataService%.update")).toBeNil()
				expect(string.find(source, "playerKills")).toBeNil()
			end
		end)
	end)
end
