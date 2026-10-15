--!nocheck
--[[
	Contrôle des postures des armes à distance (hors Studio) :
	`lune run tests/tools/weapon_pose_check.luau`

	Pour chaque arme et chaque situation (prise, visée haute / basse, recul,
	sprint, recharge) : interpénétration de l'arme avec le corps (torse, tête,
	bassin) et écart des mains à leur cible (bras trop courts). Sert à régler
	Config/WeaponPoses ; les mêmes seuils sont vérifiés par
	tests/specs/weaponpose.spec.luau.
]]

local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

local H = require("../lib/Harness")
local Body = require("../lib/Body")
H.loadProject("./")

local Config = H.require("ReplicatedStorage/Shared/Config")
local ItemModels = H.require("ReplicatedStorage/Shared/Visuals/ItemModels")
local WeaponPose = H.require("ReplicatedStorage/Shared/Visuals/WeaponPose")

local function state(itemId, overrides)
	local s = {
		itemId = itemId,
		pitch = 0,
		prone = false,
		sprint = 0,
		parry = 0,
		kick = 0,
		jitter = 0,
		variant = 1,
		using = false,
		scale = 1,
	}
	for key, value in overrides do
		s[key] = value
	end
	return s
end

local situations = {
	{ "prise", {} },
	{ "visée +45°", { pitch = math.rad(45) } },
	{ "visée -45°", { pitch = math.rad(-45) } },
	{ "recul", { kick = 1, jitter = 1 } },
	{ "sprint", { sprint = 1 } },
	{ "recharge", { reload = 0.5 } },
}

local function handError(rig, target, pole)
	local a, b, c = WeaponPose.solveArm(rig, target, pole)
	local _, _, hand = Body.forward(rig, a, b, c)
	return (hand.Position - target).Magnitude
end

local ids = {}
for id in Config.Weapons.ranged do
	table.insert(ids, id)
end
table.sort(ids)

for _, id in ids do
	local blueprint = ItemModels.blueprint(id)
	for _, situation in situations do
		local pose = WeaponPose.compute(state(id, situation[2]))
		local depth, part, volume = Body.weaponPenetration(blueprint, pose.weapon, pose.waist, pose.neck)
		local right = handError(Body.right, pose.right, pose.rightPole)
		local left = if pose.left then handError(Body.left, pose.left, pose.leftPole) else 0
		local flag = if depth > 0.1 or right > 0.12 or left > 0.12 then "  <<" else ""
		print(
			string.format(
				"%-18s %-11s traverse %.2f (%s / %s)  main D %.2f  main G %.2f%s",
				id,
				situation[1],
				depth,
				part or "-",
				volume or "-",
				right,
				left,
				flag
			)
		)
	end
end

-- Coups de mêlée : arme soudée à la main, main placée et orientée par le geste.
print("")
local meleeIds = {}
for id in Config.WeaponPoses.melee do
	table.insert(meleeIds, id)
end
table.sort(meleeIds)
for _, id in meleeIds do
	local blueprint = ItemModels.blueprint(id)
	local length = Config.Visuals.weapons[id].size.Z
	for variant = 1, 2 do
		for _, progress in { 0.3, 0.35, 0.4, 0.45, 0.5, 0.55 } do
			local pose = WeaponPose.meleeSwing(id, progress, variant, 1)
			local a, b, c = WeaponPose.solveArm(Body.right, Vector3.zero, pose.rightPole, pose.hand)
			local _, _, hand = Body.forward(Body.right, a, b, c)
			local right = (hand.Position - pose.hand.Position).Magnitude
			local left = if pose.left then handError(Body.left, pose.left, pose.leftPole) else 0
			local depth, part, volume = Body.weaponPenetration(blueprint, pose.weapon, pose.waist, nil)
			local tip = pose.weapon * Vector3.new(0, 0, -length / 2)
			local flag = if depth > 0.1 or right > 0.12 or left > 0.12 then "  <<" else ""
			print(
				string.format(
					"%-18s coup %d à %.2f  pointe (%.1f, %.1f, %.1f)  traverse %.2f (%s / %s)  main D %.2f  main G %.2f%s",
					id,
					variant,
					progress,
					tip.X,
					tip.Y,
					tip.Z,
					depth,
					part or "-",
					volume or "-",
					right,
					left,
					flag
				)
			)
		end
	end
end
