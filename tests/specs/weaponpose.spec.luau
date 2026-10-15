--!nocheck
-- Posture des armes tenues : bras calculés, prises des armes à distance, coups de mêlée.
-- Mannequin R15 « bloc » et tests de volumes : tests/lib/Body.luau.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local roblox = require("@lune/roblox")
	local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
	local Body = require("../lib/Body")
	local Config = H.require("ReplicatedStorage/Shared/Config")
	local ItemModels = H.require("ReplicatedStorage/Shared/Visuals/ItemModels")
	local WeaponPose = H.require("ReplicatedStorage/Shared/Visuals/WeaponPose")

	local Poses = Config.WeaponPoses
	local RIGHT, LEFT = Body.right, Body.left

	-- Seuils visuels : une arme qui effleure le corps (joue contre la crosse) ou
	-- une main à quelques centimètres de sa place ne se voient pas ; au-delà, si.
	local MAX_CONTACT = 0.1
	local MAX_HAND_GAP = 0.12
	-- Mêlée, transitions avec l'animation (~0,1 s, mélangées à l'animation réelle
	-- que le mannequin au repos ne fait qu'approcher).
	local MAX_BLEND_CONTACT = 0.2

	local function handGap(rig, target, pole)
		local a, b, c = WeaponPose.solveArm(rig, target, pole)
		local _, _, hand = Body.forward(rig, a, b, c)
		return (hand.Position - target).Magnitude
	end

	local function state(itemId, overrides)
		local s = {
			itemId = itemId,
			pitch = 0,
			prone = false,
			sprint = 0,
			reload = nil,
			kick = 0,
			jitter = 0,
			using = false,
			scale = 1,
		}
		for key, value in overrides or {} do
			s[key] = value
		end
		return s
	end

	-- Cas hors limites (`check() -> (contact, main, limite de contact?)`), affichés.
	local function failures(cases)
		local count = 0
		for _, case in cases do
			local contact, gap, limit = case.check()
			if contact > (limit or MAX_CONTACT) or gap > MAX_HAND_GAP then
				count += 1
				print(string.format("    %s : contact %.2f, main à %.2f", case.label, contact, gap))
			end
		end
		return count
	end

	local function sortedKeys(t)
		local keys = {}
		for key in t do
			table.insert(keys, key)
		end
		table.sort(keys)
		return keys
	end

	describe("Prises des armes (config)", function()
		it("chaque arme à distance a une prise, chaque arme de mêlée un geste", function()
			for id, def in Config.Weapons.ranged do
				local entry = Poses.weapons[id]
				expect(entry ~= nil).toBe(true)
				expect(Poses.styles[entry.style] ~= nil).toBe(true)
				expect(Poses.recoil[def.class] ~= nil).toBe(true)
				expect(WeaponPose.isMounted(id)).toBe(true)
			end
			for id in Config.Weapons.melee do
				local entry = Poses.melee[id]
				expect(entry ~= nil).toBe(true)
				local set = Poses.swings[entry.swing]
				expect(set ~= nil and #set.swings >= 1).toBe(true)
				if set.left == "support" then
					expect(entry.support ~= nil).toBe(true)
				end
				expect(WeaponPose.isMounted(id)).toBe(false)
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
				local upper, _, hand = Body.forward(RIGHT, a, b, c)
				expect((hand.Position - target).Magnitude < 0.02).toBe(true)
				local elbow = (upper * RIGHT.elbowC0).Position
				local shoulder = RIGHT.shoulderC0.Position
				local line = (target - shoulder).Unit
				local offset = (elbow - shoulder) - line * (elbow - shoulder):Dot(line)
				expect(offset:Dot(pole - line * pole:Dot(line)) > 0).toBe(true)
			end
		end)

		it("main imposée (position et orientation) : le poignet l'oriente", function()
			local wanted = CFrame.new(0.6, 0.7, -1.1) * CFrame.Angles(math.rad(70), math.rad(-30), math.rad(20))
			local a, b, c = WeaponPose.solveArm(RIGHT, Vector3.zero, Vector3.new(1, -1, 0.3), wanted)
			local _, _, hand = Body.forward(RIGHT, a, b, c)
			expect((hand.Position - wanted.Position).Magnitude < 0.02).toBe(true)
			expect(hand.LookVector:Dot(wanted.LookVector) > 0.999).toBe(true)
			expect(hand.UpVector:Dot(wanted.UpVector) > 0.999).toBe(true)
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
			local _, _, hand = Body.forward(RIGHT, a, b, c)
			local shoulder = RIGHT.shoulderC0.Position
			expect((hand.Position - shoulder).Unit:Dot((target - shoulder).Unit) > 0.97).toBe(true)
		end)
	end)

	describe("Armes à distance : volumes", function()
		local situations = {
			{ "prise", {} },
			{ "visée +45°", { pitch = math.rad(45) } },
			{ "visée -45°", { pitch = math.rad(-45) } },
			{ "recul", { kick = 1, jitter = 1 } },
			{ "recul (autre côté)", { kick = 1, jitter = -1 } },
			{ "sprint", { sprint = 1 } },
			{ "entrée en sprint", { sprint = 0.5 } },
			{ "début de recharge", { reload = 0.1 } },
			{ "recharge", { reload = 0.5 } },
		}

		it("l'arme ne traverse ni le torse, ni la tête, ni le bassin ; les mains la tiennent", function()
			local cases = {}
			for _, id in sortedKeys(Config.Weapons.ranged) do
				local blueprint = ItemModels.blueprint(id)
				for _, situation in situations do
					table.insert(cases, {
						label = id .. " / " .. situation[1],
						check = function()
							local pose = WeaponPose.compute(state(id, situation[2]))
							local contact = Body.weaponPenetration(blueprint, pose.weapon, pose.waist, pose.neck)
							local gap = handGap(RIGHT, pose.right, pose.rightPole)
							if pose.left then
								gap = math.max(gap, handGap(LEFT, pose.left, pose.leftPole))
							end
							return contact, gap
						end,
					})
				end
			end
			expect(failures(cases)).toBe(0)
		end)

		it("visée extrême (±70°) : l'arme reste près du corps sans s'y enfoncer", function()
			local cases = {}
			for _, id in sortedKeys(Config.Weapons.ranged) do
				for _, degrees in { -70, 70 } do
					table.insert(cases, {
						label = id .. string.format(" / %d°", degrees),
						check = function()
							local pose = WeaponPose.compute(state(id, { pitch = math.rad(degrees) }))
							return Body.weaponPenetration(ItemModels.blueprint(id), pose.weapon, pose.waist, pose.neck),
								0,
								0.25
						end,
					})
				end
			end
			expect(failures(cases)).toBe(0)
		end)
	end)

	describe("Armes à distance : posture", function()
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

		it("l'arme est devant le torse, à hauteur de poitrine ou de joue (fusils)", function()
			local pose = WeaponPose.compute(state("sentinel_rifle"))
			local front = (pose.waist * pose.weapon).Position
			expect(front.Z < -0.5).toBe(true)
			expect(pose.weapon.Position.Y > 0.8).toBe(true)
		end)

		it("le recul relève le canon et recule à peine", function()
			local still = WeaponPose.compute(state("hullbreaker"))
			local kicked = WeaponPose.compute(state("hullbreaker", { kick = 1 }))
			expect(aimed(kicked).Y > aimed(still).Y + 0.1).toBe(true)
			local back = (kicked.right - still.right):Dot(still.weapon.LookVector)
			expect(back < 0 and back > -0.3).toBe(true)
		end)

		it("main gauche : sur l'arme, libre en buvant, va chercher une cellule en rechargeant", function()
			local id = "sentinel_rifle"
			local pose = WeaponPose.compute(state(id))
			local support = pose.weapon * Poses.weapons[id].support
			expect((pose.left - support).Magnitude < 1e-3).toBe(true)
			expect(WeaponPose.compute(state(id, { using = true })).left).toBe(nil)
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
			local hand = rest * WeaponPose.handInWeapon("sentinel_rifle")
			expect((hand - Poses.styles.rifle.ready.hand).Magnitude < 1e-3).toBe(true)
			expect(rest.LookVector.Z < -0.99).toBe(true)
		end)
	end)

	describe("Mêlée", function()
		local IDLE = CFrame.new() -- bras le long du corps (animation au repos)

		-- Arme soudée à la main, d'après les Transform du bras droit.
		local function weaponFrom(id, shoulder, elbow, wrist)
			local _, _, hand = Body.forward(RIGHT, shoulder, elbow, wrist)
			return hand * Config.Visuals.weapons[id].gripOffset, hand
		end

		it("hors des coups : l'arme est dans la main (aucune posture imposée)", function()
			-- Bras au repos : l'arme pend à droite du corps, sans le traverser.
			for id in Config.Weapons.melee do
				local weapon = weaponFrom(id, IDLE, IDLE, IDLE)
				expect(Body.weaponPenetration(ItemModels.blueprint(id), weapon) <= MAX_CONTACT).toBe(true)
			end
		end)

		it("le geste part de l'animation, frappe, puis y revient", function()
			for id in Config.Weapons.melee do
				expect(WeaponPose.meleeSwing(id, 0, 1, 1).weight).toBe(0)
				expect(WeaponPose.meleeSwing(id, Poses.swingTiming.windup, 1, 1).weight).toBe(1)
				expect(WeaponPose.meleeSwing(id, 0.5, 1, 1).weight).toBe(1)
				expect(WeaponPose.meleeSwing(id, 0.999, 1, 1).weight < 0.01).toBe(true)
			end
		end)

		it("l'arme est armée en arrière ou sur le côté, et frappe devant", function()
			local timing = Poses.swingTiming
			for id in Config.Weapons.melee do
				local length = Config.Visuals.weapons[id].size.Z
				for variant = 1, 2 do
					local windup = WeaponPose.meleeSwing(id, timing.windup, variant, 1)
					local strike = WeaponPose.meleeSwing(id, timing.strike - 1e-3, variant, 1)
					local tipBefore = windup.weapon * Vector3.new(0, 0, -length / 2)
					local tipAfter = strike.weapon * Vector3.new(0, 0, -length / 2)
					expect(tipAfter.Z < tipBefore.Z - 0.15).toBe(true)
					expect(tipAfter.Z < -1).toBe(true)
				end
			end
		end)

		it("pendant le coup, l'arme ne traverse pas le corps et la main la tient", function()
			local cases = {}
			for _, id in sortedKeys(Config.Weapons.melee) do
				local blueprint = ItemModels.blueprint(id)
				for variant = 1, 2 do
					for progress = 0.05, 0.95, 0.05 do
						table.insert(cases, {
							label = string.format("%s coup %d à %.2f", id, variant, progress),
							check = function()
								local pose = WeaponPose.meleeSwing(id, progress, variant, 1)
								local a, b, c = WeaponPose.solveArm(RIGHT, Vector3.zero, pose.rightPole, pose.hand)
								-- Mélange avec l'animation au repos, comme le contrôleur.
								local w = pose.weight
								local weapon, hand = weaponFrom(id, IDLE:Lerp(a, w), IDLE:Lerp(b, w), IDLE:Lerp(c, w))
								local contact = Body.weaponPenetration(blueprint, weapon, pose.waist, nil)
								local gap = 0
								if w >= 1 then
									-- Geste complet : la main est à sa place, la gauche aussi.
									gap = (hand.Position - pose.hand.Position).Magnitude
									if pose.left then
										gap = math.max(gap, handGap(LEFT, pose.left, pose.leftPole))
									end
								end
								return contact, gap, if w >= 1 then MAX_CONTACT else MAX_BLEND_CONTACT
							end,
						})
					end
				end
			end
			expect(failures(cases)).toBe(0)
		end)

		it("deux gestes alternés différents", function()
			for id in Config.Weapons.melee do
				local a = WeaponPose.meleeSwing(id, Poses.swingTiming.windup, 1, 1).weapon.Position
				local b = WeaponPose.meleeSwing(id, Poses.swingTiming.windup, 2, 1).weapon.Position
				expect((a - b).Magnitude > 0.3).toBe(true)
			end
		end)
	end)
end
