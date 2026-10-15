--!nocheck
-- Posture des armes tenues : bras calculés, prises, recul, coups de mêlée, recharge.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local roblox = require("@lune/roblox")
	local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
	local Config = H.require("ReplicatedStorage/Shared/Config")
	local WeaponPose = H.require("ReplicatedStorage/Shared/Visuals/WeaponPose")

	local Poses = Config.WeaponPoses

	-- Bras R15 standard (« bloc ») : l'épaule est au bord du torse, le haut du
	-- bras décalé de 0,5 vers l'extérieur (décalage le long de l'axe du coude).
	local function rig(sign)
		return {
			shoulderC0 = CFrame.new(sign * 1, 0.563, 0),
			shoulderC1 = CFrame.new(-sign * 0.5, 0.42, 0),
			elbowC0 = CFrame.new(0, -0.334, 0),
			elbowC1 = CFrame.new(0, 0.2, 0),
			wristC0 = CFrame.new(0, -0.501, 0),
			wristC1 = CFrame.new(0, 0.125, 0),
		}
	end
	local RIGHT, LEFT = rig(1), rig(-1)

	-- Pièces du bras d'après les Transform (comme le moteur : Part0 * C0 * T * C1⁻¹).
	local function forward(r, shoulder, elbow, wrist)
		local upper = r.shoulderC0 * shoulder * r.shoulderC1:Inverse()
		local lower = upper * r.elbowC0 * elbow * r.elbowC1:Inverse()
		local hand = lower * r.wristC0 * wrist * r.wristC1:Inverse()
		return upper, lower, hand
	end

	local function handError(r, target, pole)
		local a, b, c = WeaponPose.solveArm(r, target, pole)
		local _, _, hand = forward(r, a, b, c)
		return (hand.Position - target).Magnitude
	end

	local function state(itemId, overrides)
		local s = {
			itemId = itemId,
			pitch = 0,
			prone = false,
			sprint = 0,
			parry = 0,
			reload = nil,
			kick = 0,
			jitter = 0,
			swing = nil,
			variant = 1,
			using = false,
			scale = 1,
		}
		for key, value in overrides or {} do
			s[key] = value
		end
		return s
	end

	describe("Prises des armes (config)", function()
		it("chaque arme a une prise, chaque famille d'arme à distance un recul", function()
			for id in Config.Visuals.weapons do
				local entry = Poses.weapons[id]
				expect(entry ~= nil).toBe(true)
				local style = Poses.styles[entry.style]
				expect(style ~= nil).toBe(true)
				if style.left == "support" then
					expect(entry.support ~= nil).toBe(true)
				end
				local ranged = Config.Weapons.ranged[id]
				if ranged then
					expect(Poses.recoil[ranged.class] ~= nil).toBe(true)
					expect(style.reload ~= nil).toBe(true)
				else
					expect(style.swings ~= nil and #style.swings >= 1).toBe(true)
				end
			end
		end)

		it("durée d'un coup de mêlée bornée", function()
			for id in Config.Weapons.melee do
				local duration = WeaponPose.swingDuration(id)
				expect(duration >= Poses.swingMin and duration <= Poses.swingMax).toBe(true)
			end
		end)
	end)

	describe("Bras calculés", function()
		it("la main rejoint une cible à portée, coude orienté vers le pôle", function()
			local pole = Vector3.new(1, -1, 0.3)
			for _, target in
				{
					Vector3.new(0.3, 0.4, -1.2),
					Vector3.new(0.9, -0.4, -0.8),
					Vector3.new(-0.2, 0.9, -0.9),
					Vector3.new(1.4, 0.2, -0.5),
				}
			do
				local a, b, c, reached = WeaponPose.solveArm(RIGHT, target, pole)
				expect(reached).toBe(true)
				local upper, _, hand = forward(RIGHT, a, b, c)
				expect((hand.Position - target).Magnitude < 0.02).toBe(true)
				-- Coude du côté du pôle par rapport à la ligne épaule → main.
				local elbow = (upper * RIGHT.elbowC0).Position
				local shoulder = RIGHT.shoulderC0.Position
				local line = (target - shoulder).Unit
				local offset = (elbow - shoulder) - line * (elbow - shoulder):Dot(line)
				expect(offset:Dot(pole - line * pole:Dot(line)) > 0).toBe(true)
			end
		end)

		it("le coude est une charnière (rotation autour de l'axe X, sans décalage)", function()
			local _, elbow = WeaponPose.solveArm(RIGHT, Vector3.new(0.4, 0.3, -1.1), Vector3.new(1, -1, 0.3))
			expect(elbow.Position.Magnitude < 1e-3).toBe(true)
			expect((elbow.XVector - Vector3.new(1, 0, 0)).Magnitude < 1e-3).toBe(true)
		end)

		it("cible hors de portée : bras tendu dans sa direction", function()
			local target = Vector3.new(0.5, 0.5, -4)
			local a, b, c, reached = WeaponPose.solveArm(RIGHT, target, Vector3.new(1, -1, 0.3))
			expect(reached).toBe(false)
			local _, _, hand = forward(RIGHT, a, b, c)
			local shoulder = RIGHT.shoulderC0.Position
			expect((hand.Position - shoulder).Unit:Dot((target - shoulder).Unit) > 0.97).toBe(true)
		end)

		it("toutes les prises sont à portée d'un bras R15 standard", function()
			local worst, where = 0, ""
			local function check(id, label, s)
				local pose = WeaponPose.compute(s)
				local err = handError(RIGHT, pose.right, pose.rightPole)
				if pose.left then
					err = math.max(err, handError(LEFT, pose.left, pose.leftPole))
				end
				if err > worst then
					worst, where = err, id .. " " .. label
				end
			end
			for id in Poses.weapons do
				check(id, "prise", state(id))
				check(id, "sprint", state(id, { sprint = 1 }))
				check(id, "visée haute", state(id, { pitch = math.rad(50) }))
				if Config.Weapons.ranged[id] then
					check(id, "recharge", state(id, { reload = 0.5 }))
					check(id, "couché", state(id, { prone = true }))
				else
					check(id, "garde", state(id, { parry = 1 }))
					for _, variant in { 1, 2 } do
						for _, progress in { 0.25, 0.5 } do
							check(id, "coup " .. variant, state(id, { swing = progress, variant = variant }))
						end
					end
				end
			end
			if worst > 0.1 then
				print("    prise la plus éloignée : " .. where .. string.format(" (%.2f studs)", worst))
			end
			expect(worst <= 0.1).toBe(true)
		end)
	end)

	describe("Posture", function()
		-- Direction de l'arme dans le repère du personnage (taille penchée et tournée).
		local function aimed(pose)
			return (pose.waist * pose.weapon).LookVector
		end

		it("l'arme vise droit devant malgré le buste tourné, et suit la visée", function()
			for _, id in { "sentinel_rifle", "vigil_pistol", "bastion_minigun", "needle" } do
				for _, degrees in { -40, 0, 30, 60 } do
					local pitch = math.rad(degrees)
					local direction = aimed(WeaponPose.compute(state(id, { pitch = pitch })))
					local expected = Vector3.new(0, math.sin(pitch), -math.cos(pitch))
					expect((direction - expected).Magnitude < 0.06).toBe(true)
				end
			end
		end)

		it("le recul fait reculer l'arme et relève le canon", function()
			local still = WeaponPose.compute(state("hullbreaker"))
			local kicked = WeaponPose.compute(state("hullbreaker", { kick = 1 }))
			expect(aimed(kicked).Y > aimed(still).Y + 0.1).toBe(true)
			local back = (kicked.weapon.Position - still.weapon.Position):Dot(still.weapon.LookVector)
			expect(back < -0.1).toBe(true)
		end)

		it("coup de mêlée : part de la garde, y revient, deux gestes alternés", function()
			local id = "laser_saber"
			local ready = WeaponPose.compute(state(id)).weapon
			local function at(progress, variant)
				return WeaponPose.compute(state(id, { swing = progress, variant = variant })).weapon
			end
			expect((at(0, 1).Position - ready.Position).Magnitude < 1e-3).toBe(true)
			expect((at(0.999, 1).Position - ready.Position).Magnitude < 0.01).toBe(true)
			expect((at(0.5, 1).Position - ready.Position).Magnitude > 0.5).toBe(true)
			expect((at(0.5, 1).Position - at(0.5, 2).Position).Magnitude > 0.5).toBe(true)
		end)

		it("main gauche : sur l'arme, libre en buvant, va chercher une cellule en rechargeant", function()
			local id = "sentinel_rifle"
			local pose = WeaponPose.compute(state(id))
			local support = pose.weapon * Poses.weapons[id].support
			expect((pose.left - support).Magnitude < 1e-3).toBe(true)
			expect(WeaponPose.compute(state(id, { using = true })).left).toBe(nil)
			expect(WeaponPose.compute(state("shock_crowbar")).left).toBe(nil)
			local reloading = WeaponPose.compute(state(id, { reload = 0.5 }))
			local held = reloading.weapon * Poses.weapons[id].support
			expect((reloading.left - held).Magnitude > 0.4).toBe(true)
		end)

		it("couché : l'arme reste pointée devant le personnage", function()
			-- Torse couché : son -Z regarde le sol, son +Y vers l'avant.
			local pose = WeaponPose.compute(state("sentinel_rifle", { prone = true }))
			expect(pose.weapon.LookVector.Y > 0.95).toBe(true)
		end)

		it("position de repos (serveur) = prise de base sans visée", function()
			local rest = WeaponPose.rest("sentinel_rifle", 1)
			local style = Poses.styles.rifle
			local hand = rest * WeaponPose.handInWeapon("sentinel_rifle")
			expect((hand - style.ready.hand).Magnitude < 1e-3).toBe(true)
			expect(rest.LookVector.Z < -0.99).toBe(true)
		end)
	end)
end
