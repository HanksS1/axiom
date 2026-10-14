--!nocheck
-- Combats lisibles : tours d'attaque, précision, équilibrage, radar, plan de carte.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local roblox = require("@lune/roblox")
	local Vector3, CFrame = roblox.Vector3, roblox.CFrame
	local Config = H.require("ReplicatedStorage/Shared/Config")
	local Engagement = H.require("ReplicatedStorage/Shared/Robots/Engagement")
	local RobotBrain = H.require("ReplicatedStorage/Shared/Robots/RobotBrain")
	local MapPlan = H.require("ReplicatedStorage/Shared/Match/MapPlan")
	local Radar = H.require("ReplicatedStorage/Shared/Match/Radar")
	local Registry = H.require("ServerScriptService/Server/Maps/Registry")
	local LayoutBuilder = H.require("ServerScriptService/Server/Maps/LayoutBuilder")

	describe("Tours d'attaque (Engagement)", function()
		it("au plus `limit` attaquants à la fois sur une cible", function()
			local state = Engagement.new()
			expect(Engagement.request(state, "joueur", "r1", 0, 2, 2)).toBe(true)
			expect(Engagement.request(state, "joueur", "r2", 0, 2, 2)).toBe(true)
			expect(Engagement.request(state, "joueur", "r3", 0, 2, 2)).toBe(false)
			expect(Engagement.count(state, "joueur", 0)).toBe(2)
			-- Une autre cible a ses propres tours.
			expect(Engagement.request(state, "autre", "r3", 0, 2, 2)).toBe(true)
		end)

		it("un attaquant garde son tour tant qu'il attaque ; il le perd sinon", function()
			local state = Engagement.new()
			Engagement.request(state, "joueur", "r1", 0, 1, 2)
			-- r1 renouvelle son tour : r2 attend toujours.
			expect(Engagement.request(state, "joueur", "r1", 1.5, 1, 2)).toBe(true)
			expect(Engagement.request(state, "joueur", "r2", 3, 1, 2)).toBe(false)
			-- r1 n'attaque plus : son tour expire, r2 prend la place.
			expect(Engagement.request(state, "joueur", "r2", 3.6, 1, 2)).toBe(true)
			expect(Engagement.request(state, "joueur", "r1", 3.7, 1, 2)).toBe(false)
		end)

		it("un robot détruit ou étourdi libère sa place tout de suite", function()
			local state = Engagement.new()
			Engagement.request(state, "joueur", "r1", 0, 1, 2)
			Engagement.release(state, "r1")
			expect(Engagement.request(state, "joueur", "r2", 0.1, 1, 2)).toBe(true)
			Engagement.forget(state, "joueur")
			expect(Engagement.count(state, "joueur", 0.1)).toBe(0)
		end)
	end)

	describe("Précision des robots", function()
		local A = Config.Robots.ai.accuracy

		it("pleine de près, réduite au loin et sur une cible qui court", function()
			expect(RobotBrain.hitChance(0.6, 5, 70, 0)).toBeNear(0.6)
			expect(RobotBrain.hitChance(0.6, 70 * A.nearRatio, 70, 0)).toBeNear(0.6)
			expect(RobotBrain.hitChance(0.6, 70, 70, 0)).toBeNear(0.6 * A.farFactor)
			expect(RobotBrain.hitChance(0.6, 200, 70, 0)).toBeNear(0.6 * A.farFactor)
			expect(RobotBrain.hitChance(0.6, 5, 70, A.sprintSpeed + 1)).toBeNear(0.6 * A.sprintFactor)
			-- Décroissance régulière avec la distance.
			local previous = 1
			for distance = 0, 70, 5 do
				local chance = RobotBrain.hitChance(0.8, distance, 70, 0)
				expect(chance <= previous + 1e-9).toBe(true)
				previous = chance
			end
		end)

		it("sprinter met bien la cible « en course »", function()
			local movement = Config.Combat.movement
			expect(movement.sprintSpeed >= A.sprintSpeed).toBe(true)
			expect(movement.walkSpeed < A.sprintSpeed).toBe(true)
		end)

		it("un Gardien qui réapparaît ne frappe pas dans l'instant", function()
			local brain = RobotBrain.new()
			brain.state = "combat"
			brain.readyAt = 0
			RobotBrain.delayAttack(brain, 10, 1)
			expect(RobotBrain.canAttack(brain, 10.5)).toBe(false)
			expect(RobotBrain.canAttack(brain, 11)).toBe(true)
		end)
	end)

	describe("Équilibrage des robots", function()
		local sprint = Config.Combat.movement.sprintSpeed
		local health = Config.Combat.maxHealth

		it("on peut semer n'importe quel robot au sol en sprintant", function()
			for id, def in Config.Robots.byId do
				if not def.flying and def.speed >= sprint then
					error(`{id} est aussi rapide qu'un joueur qui sprinte`)
				end
			end
		end)

		it("tout coup lourd est annoncé (aucun gros dégât sans préavis)", function()
			local heavy = health * 0.2
			local function check(id, def)
				if def.attack ~= "ranged" and def.damage >= heavy and (def.meleeWindup or 0) < 0.4 then
					error(`{id} : mêlée de {def.damage} sans annonce`)
				end
				local shot = def.rangedDamage or (if def.attack == "ranged" then def.damage else 0)
				if shot >= heavy and (def.windup or 0) < 0.5 then
					error(`{id} : tir de {shot} sans annonce`)
				end
			end
			for id, def in Config.Robots.byId do
				check(id, def)
			end
			-- Gardiens propres à chaque carte.
			for mapId, map in Config.Maps.byId do
				local merged = table.clone(Config.Robots.byId[map.guardian.robotId])
				for key, value in map.guardian.overrides do
					merged[key] = value
				end
				check(mapId .. ".guardian", merged)
				expect(merged.guardian).toBe(true)
			end
		end)

		it("aucun coup ne tue d'un seul geste un joueur en pleine santé, même en Difficile", function()
			local hard = Config.Modes.byId.hard.robots.damage
			local function worst(def)
				return math.max(def.damage, def.rangedDamage or 0) * hard
			end
			for id, def in Config.Robots.byId do
				expect(worst(def) < health).toBe(true)
				if worst(def) >= health then
					error(id)
				end
			end
			for _, map in Config.Maps.byId do
				local merged = table.clone(Config.Robots.byId[map.guardian.robotId])
				for key, value in map.guardian.overrides do
					merged[key] = value
				end
				expect(worst(merged) < health).toBe(true)
			end
			local burrow = Config.Maps.guardianBehaviors.burrow
			expect(burrow.surfaceDamage * hard < health).toBe(true)
			-- Le surgissement est annoncé assez tôt pour sortir du cercle en marchant.
			expect(burrow.warning * Config.Combat.movement.walkSpeed > burrow.surfaceRadius).toBe(true)
			expect(burrow.warning < burrow.hidden).toBe(true)
		end)

		it("modes : plus dur = réaction plus vive et plus d'attaquants à la fois", function()
			local previous
			for _, modeId in Config.Modes.list do
				local robots = Config.Modes.byId[modeId].robots
				expect(robots.maxAttackers >= 1).toBe(true)
				-- Toujours une vraie fenêtre d'alerte avant la première attaque.
				expect(robots.reactionTime >= 0.5).toBe(true)
				if previous then
					expect(robots.reactionTime < previous.reactionTime).toBe(true)
					expect(robots.maxAttackers >= previous.maxAttackers).toBe(true)
				end
				previous = robots
			end
		end)

		it("apparitions : assez de points de patrouille loin des points de départ", function()
			local clearance = Config.Robots.density.spawnClearance
			for _, mapId in Config.Maps.list do
				local layout = Registry[mapId](LayoutBuilder.random(Config.Maps.byId[mapId].seed))
				local starts, patrols = {}, {}
				for _, marker in layout.markers do
					if marker.tag == "DeploySpawn" or marker.tag == "SoloSpawn" then
						table.insert(starts, marker.cframe.Position)
					elseif marker.tag == "RobotSpawn" and not (marker.attributes and marker.attributes.Garrison) then
						table.insert(patrols, marker.cframe.Position)
					end
				end
				local far = 0
				for _, patrol in patrols do
					local nearest = math.huge
					for _, start in starts do
						local dx, dz = patrol.X - start.X, patrol.Z - start.Z
						nearest = math.min(nearest, math.sqrt(dx * dx + dz * dz))
					end
					if nearest >= clearance then
						far += 1
					end
				end
				if far < 4 then
					error(`{mapId} : seulement {far} repères de patrouille loin des points de départ`)
				end
			end
		end)
	end)

	describe("Radar", function()
		local north = Vector3.new(0, 0, -1)
		local ranges = Config.Robots.threat

		it("devant = en haut, à droite = à droite, hors de portée = sur le bord", function()
			local x, y, clamped = Radar.project(Vector3.new(0, 0, -45), north, 90)
			expect(x).toBeNear(0)
			expect(y).toBeNear(-0.5)
			expect(clamped).toBe(false)
			x, y = Radar.project(Vector3.new(45, 12, 0), north, 90)
			expect(x).toBeNear(0.5)
			expect(y).toBeNear(0)
			x, y, clamped = Radar.project(Vector3.new(0, 0, 300), north, 90)
			expect(y).toBeNear(1)
			expect(clamped).toBe(true)
			-- Le radar tourne avec le regard : en regardant à l'est, l'est passe en haut.
			x, y = Radar.project(Vector3.new(45, 0, 0), Vector3.new(1, 0, 0), 90)
			expect(x).toBeNear(0)
			expect(y).toBeNear(-0.5)
			-- Regard à la verticale : pas d'erreur, le nord sert de repère.
			x, y = Radar.project(Vector3.new(0, 0, -45), Vector3.new(0, -1, 0), 90)
			expect(y).toBeNear(-0.5)
		end)

		it("cap : 0 devant, positif à droite, π derrière", function()
			expect(Radar.bearing(Vector3.new(0, 0, -10), north)).toBeNear(0)
			expect(Radar.bearing(Vector3.new(10, 0, 0), north)).toBeNear(math.pi / 2)
			expect(Radar.bearing(Vector3.new(-10, 0, 0), north)).toBeNear(-math.pi / 2)
			expect(math.abs(Radar.bearing(Vector3.new(0, 0, 10), north))).toBeNear(math.pi)
		end)

		it("niveaux de menace", function()
			local function level(alert, aggro, distance, windup, guardian)
				return Radar.level({
					alert = alert,
					aggro = aggro,
					distance = distance,
					windup = windup == true,
					guardian = guardian == true,
				}, ranges)
			end
			expect(level(nil, false, 20)).toBe("none")
			expect(level("search", false, 20)).toBe("alert")
			-- En combat contre quelqu'un d'autre : simple alerte pour moi.
			expect(level("combat", false, 5)).toBe("alert")
			expect(level("suspicion", true, 20)).toBe("noticed")
			expect(level("combat", true, ranges.imminentRange + 10)).toBe("hostile")
			expect(level("combat", true, ranges.imminentRange - 1)).toBe("imminent")
			expect(level("combat", true, 80, true)).toBe("imminent")
			expect(level("combat", true, ranges.guardianImminentRange - 1, false, true)).toBe("imminent")
			expect(Radar.worst("alert", "hostile")).toBe("hostile")
			expect(Radar.worst("imminent", "noticed")).toBe("imminent")
		end)

		it("le radar voit plus loin que la zone de danger", function()
			expect(ranges.radarRange > ranges.guardianImminentRange).toBe(true)
			expect(ranges.guardianImminentRange > ranges.imminentRange).toBe(true)
			expect(ranges.edgeRange > ranges.radarRange).toBe(true)
		end)
	end)

	describe("Plan de carte (MapPlan)", function()
		local band = { min = 1.5, max = 6, minSpan = 7 }
		local function solid(x, y, z, sx, sy, sz, collide)
			return { size = Vector3.new(sx, sy, sz), cframe = CFrame.new(x, y, z), collide = collide }
		end

		it("murs à hauteur d'homme seulement : ni sol, ni étage, ni petit décor, ni fantôme", function()
			local grid, cells = MapPlan.rasterize({
				solid(0, 0, 0, 100, 1, 100), -- sol
				solid(0, 5, -20, 20, 10, 1), -- mur
				solid(0, 20, 20, 20, 1, 20), -- étage
				solid(30, 2, 30, 3, 3, 3), -- baril
				solid(-30, 5, -30, 20, 10, 1, false), -- non solide
			}, 100, 4, band)
			expect(cells).toBe(25)
			local full = 0
			for _, value in grid do
				if value then
					full += 1
				end
			end
			-- Le mur : 20 studs de long = 5 cases de 4 studs (à cheval sur une ou deux rangées).
			expect(full >= 5 and full <= 12).toBe(true)
			-- Case sous le milieu du mur (x = 0, z = -20).
			local cx, cz = math.floor(50 / 4), math.floor(30 / 4)
			expect(grid[cz * cells + cx + 1]).toBe(true)
		end)

		it("les rectangles recouvrent exactement les cases pleines, sans chevauchement", function()
			local grid, cells = MapPlan.rasterize({
				solid(0, 5, 0, 40, 10, 12),
				solid(20, 5, 20, 12, 10, 40),
				solid(-30, 5, -30, 8, 10, 8),
			}, 100, 4, band)
			local rects = MapPlan.rects(grid, cells)
			local covered = table.create(cells * cells, 0)
			for _, rect in rects do
				for z = rect.z, rect.z + rect.d - 1 do
					for x = rect.x, rect.x + rect.w - 1 do
						covered[z * cells + x + 1] += 1
					end
				end
			end
			for index, value in grid do
				expect(covered[index]).toBe(if value then 1 else 0)
			end
		end)

		it("encodage : aller-retour fidèle, chaîne invalide refusée sans erreur", function()
			local plan = { cells = 25, rects = { { x = 0, z = 0, w = 3, d = 1 }, { x = 10, z = 12, w = 2, d = 6 } } }
			local decoded = MapPlan.decode(MapPlan.encode(plan))
			expect(decoded).toEqual(plan)
			expect(MapPlan.decode(MapPlan.encode({ cells = 8, rects = {} }))).toEqual({ cells = 8, rects = {} })
			expect(MapPlan.decode(nil)).toBeNil()
			expect(MapPlan.decode("n'importe quoi")).toBeNil()
			expect(MapPlan.decode("25|24,0,5,1")).toBeNil() -- dépasse la grille
			expect(MapPlan.decode("0|")).toBeNil()
		end)

		it("monde ↔ plan : le nord en haut, aller-retour exact", function()
			local origin, size = Config.Maps.origin, Config.Maps.size
			local u, v, inside = MapPlan.toPlan(origin, origin, size)
			expect(u).toBeNear(0.5)
			expect(v).toBeNear(0.5)
			expect(inside).toBe(true)
			-- Nord (Z négatif) en haut du plan, est (X positif) à droite.
			u, v = MapPlan.toPlan(origin + Vector3.new(100, 0, -200), origin, size)
			expect(u > 0.5 and v < 0.5).toBe(true)
			local back = MapPlan.toWorld(u, v, origin, size)
			expect(back.X).toBeNear(origin.X + 100)
			expect(back.Z).toBeNear(origin.Z - 200)
			local _, _, outside = MapPlan.toPlan(origin + Vector3.new(size, 0, 0), origin, size)
			expect(outside).toBe(false)
		end)

		it("chaque carte : plan lisible, léger, et dégagé aux extractions", function()
			local P = Config.Maps.plan
			for _, mapId in Config.Maps.list do
				local layout = Registry[mapId](LayoutBuilder.random(Config.Maps.byId[mapId].seed))
				local grid, cells = MapPlan.rasterize(layout.parts, Config.Maps.size, P.cell, P.band)
				local plan = { cells = cells, rects = MapPlan.rects(grid, cells) }
				local encoded = MapPlan.encode(plan)
				-- Assez de murs pour s'orienter, assez peu de rectangles pour l'interface.
				if #plan.rects < 80 or #plan.rects > 1200 then
					error(`{mapId} : {#plan.rects} rectangles`)
				end
				expect(#encoded < 30000).toBe(true)
				expect(MapPlan.decode(encoded)).toEqual(plan)
				-- Une extraction est un espace ouvert : sa case n'est pas un mur.
				for _, marker in layout.markers do
					-- (Extractions au sol seulement : un toit est au-dessus de la tranche dessinée.)
					if marker.tag == "ExtractionPoint" and marker.cframe.Position.Y < P.band.min then
						local position = marker.cframe.Position
						local cx = math.floor((position.X + Config.Maps.size / 2) / P.cell)
						local cz = math.floor((position.Z + Config.Maps.size / 2) / P.cell)
						if grid[cz * cells + cx + 1] then
							error(`{mapId} : extraction dessinée dans un mur`)
						end
					end
				end
			end
		end)
	end)
end
