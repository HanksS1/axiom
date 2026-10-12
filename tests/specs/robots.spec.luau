--!nocheck
-- IA des robots : machine à états, cône de vision, ciblage, loot et config.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local roblox = require("@lune/roblox")
	local Vector3 = roblox.Vector3
	local RobotBrain = H.require("ReplicatedStorage/Shared/Robots/RobotBrain")
	local Config = H.require("ReplicatedStorage/Shared/Config")

	local function perception(now, visible, extra)
		local p = { now = now, dt = 0.125, visible = visible or {} }
		for k, v in extra or {} do
			p[k] = v
		end
		return p
	end
	local target = { id = "p1", position = Vector3.new(0, 0, -20), distance = 20 }

	describe("RobotBrain", function()
		it("patrouille → suspicion → combat après 1 s de vue", function()
			local brain = RobotBrain.new()
			local now = 0
			local result
			for _ = 1, 7 do
				now += 0.125
				result = RobotBrain.step(brain, perception(now, { target }), 0.5)
			end
			expect(brain.state).toBe("suspicion")
			expect(result).toBeNil()
			now += 0.125
			result = RobotBrain.step(brain, perception(now, { target }), 0.5)
			expect(brain.state).toBe("combat")
			expect(result.id).toBe("p1")
			-- Temps de réaction avant le premier tir.
			expect(RobotBrain.canAttack(brain, now)).toBe(false)
			expect(RobotBrain.canAttack(brain, now + 0.5)).toBe(true)
		end)

		it("combat → recherche (dernière position connue) → patrouille", function()
			local brain = RobotBrain.new()
			brain.state = "combat"
			brain.targetId = "p1"
			RobotBrain.step(brain, perception(10, { target }), 0.3)
			RobotBrain.step(brain, perception(10.2, {}), 0.3)
			expect(brain.state).toBe("search")
			expect(brain.lastKnown).toBe(target.position)
			RobotBrain.step(brain, perception(10.2 + Config.Robots.ai.searchTime + 0.1, {}), 0.3)
			expect(brain.state).toBe("patrol")
		end)

		it("un bruit envoie le robot en recherche ; il réagit alors sans délai de suspicion", function()
			local brain = RobotBrain.new()
			RobotBrain.step(brain, perception(1, {}, { noise = Vector3.new(5, 0, 5) }), 0.3)
			expect(brain.state).toBe("search")
			RobotBrain.step(brain, perception(1.1, { target }), 0.3)
			expect(brain.state).toBe("combat")
		end)

		it("l'attaquant devient la cible prioritaire", function()
			local brain = RobotBrain.new()
			brain.state = "combat"
			local near = { id = "near", position = Vector3.new(0, 0, -5), distance = 5 }
			local shooter = { id = "shooter", position = Vector3.new(0, 0, -40), distance = 40 }
			RobotBrain.onDamaged(brain, "shooter", shooter.position, 1)
			local chosen = RobotBrain.step(brain, perception(1.1, { near, shooter }), 0.3)
			expect(chosen.id).toBe("shooter")
			-- Mémoire de menace expirée : la plus proche.
			chosen = RobotBrain.step(brain, perception(1.1 + Config.Robots.ai.threatMemory + 1, { near, shooter }), 0.3)
			expect(chosen.id).toBe("near")
		end)

		it("cône de vision de 90°", function()
			local forward = Vector3.new(0, 0, -1)
			expect(RobotBrain.inCone(forward, Vector3.new(0, 0, -10), 90)).toBe(true)
			expect(RobotBrain.inCone(forward, Vector3.new(9, 0, -10), 90)).toBe(true) -- ~42°
			expect(RobotBrain.inCone(forward, Vector3.new(11, 0, -10), 90)).toBe(false) -- ~48°
			expect(RobotBrain.inCone(forward, Vector3.new(0, 0, 10), 90)).toBe(false)
		end)
	end)

	describe("Config des robots", function()
		it("toutes les familles ont un comportement cohérent", function()
			for id, def in Config.Robots.byId do
				expect(def.speed > 0 or def.stationary == true).toBe(true)
				if def.attack ~= "melee" then
					expect(def.fireInterval ~= nil).toBe(true)
				end
				if def.attack ~= "ranged" then
					expect(def.meleeRange ~= nil and def.meleeInterval ~= nil).toBe(true)
				end
			end
			for _, group in { "garrison", "patrol", "wave" } do
				for robotId in Config.Robots.density[group] do
					expect(Config.Robots.byId[robotId] ~= nil).toBe(true)
				end
			end
		end)
	end)
end
