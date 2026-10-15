--!nocheck
--[[
	Recherche de prises d'armes à distance sans contact avec le corps :
	`lune run tests/tools/weapon_pose_tune.luau [style] [prise]`
	(style : pistol | rifle | heavy ; prise : ready | sprint | reload).

	Essaie une grille de positions de la main droite (et, pour la prise de
	base, la rotation du buste et le pivot de visée) ; garde celles où
	aucune arme du style ne traverse le torse, la tête ou le bassin (dans
	toutes les situations) et où les deux mains atteignent leur cible ;
	affiche les meilleures, les plus proches d'une position naturelle.
	Pour la prise de base, choisit aussi jusqu'où la main gauche peut se
	poser devant la droite (`support` de chaque arme).

	Options : 3e argument = n° de la seule situation à tester (pour trouver
	celle qui bloque) ; variables d'environnement MAX_DEPTH (contact toléré,
	0,1 par défaut) et TWIST (rotation du buste imposée, en degrés).
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

local H = require("../lib/Harness")
local Body = require("../lib/Body")
H.loadProject("./")

local Config = H.require("ReplicatedStorage/Shared/Config")
local ItemModels = H.require("ReplicatedStorage/Shared/Visuals/ItemModels")
local WeaponPose = H.require("ReplicatedStorage/Shared/Visuals/WeaponPose")

local styleName = process.args[1] or "rifle"
local frameKey = process.args[2] or "ready"

-- Positions naturelles visées (repère visée) : on préfère s'en approcher.
local PREFERRED = {
	pistol = {
		ready = Vector3.new(0.3, 0.45, -1.35),
		sprint = Vector3.new(0.4, -0.3, -0.9),
		reload = Vector3.new(0.3, 0.1, -1.1),
	},
	rifle = {
		ready = Vector3.new(0.55, 0.6, -1.0),
		sprint = Vector3.new(0.4, 0.0, -0.9),
		reload = Vector3.new(0.4, 0.2, -1.0),
	},
	heavy = {
		ready = Vector3.new(0.8, -0.2, -0.9),
		sprint = Vector3.new(0.8, -0.35, -0.8),
		reload = Vector3.new(0.7, -0.3, -0.9),
	},
}

local MAX_DEPTH = tonumber(process.env.MAX_DEPTH) or 0.1
local MAX_REACH = 0.12

local ids = {}
for id, entry in Config.WeaponPoses.weapons do
	if entry.style == styleName then
		table.insert(ids, id)
	end
end
table.sort(ids)
assert(#ids > 0, "style inconnu : " .. styleName)
local blueprints = {}
for _, id in ids do
	blueprints[id] = ItemModels.blueprint(id)
end

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

local only = tonumber(process.args[3])
local situations = if frameKey == "ready"
	then {
		{ kick = 0 },
		{ pitch = math.rad(45) },
		{ pitch = math.rad(-45) },
		{ kick = 1, jitter = 1 },
		{ kick = 1, jitter = -1 },
	}
	elseif frameKey == "sprint" then { { sprint = 1 }, { sprint = 0.5 } }
	else { { reload = 0.5 }, { reload = 0.1 } }

if only then
	situations = { situations[only] }
end

local function reachError(rig, target, pole)
	local a, b, c = WeaponPose.solveArm(rig, target, pole)
	local _, _, hand = Body.forward(rig, a, b, c)
	return (hand.Position - target).Magnitude
end

-- Copie de style modifiable.
local function copy(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in value do
		result[key] = copy(child)
	end
	return result
end

local base = Config.WeaponPoses.styles[styleName]

-- Main gauche : sous l'arme, `ahead` studs devant la main droite (le plus loin
-- possible : garde-main, sinon puits du chargeur).
local AHEADS = { 1.3, 1.1, 0.9, 0.75, 0.6 }
local function supportAt(id, ahead)
	local hand = WeaponPose.handInWeapon(id)
	return Vector3.new(0, hand.Y - 0.05, hand.Z - ahead)
end

local function passes(style, id, support)
	for _, overrides in situations do
		local pose = WeaponPose.compute(state(id, overrides), style, support)
		if reachError(Body.right, pose.right, pose.rightPole) > MAX_REACH then
			return false
		end
		if pose.left and reachError(Body.left, pose.left, pose.leftPole) > MAX_REACH then
			return false
		end
		if Body.weaponPenetration(blueprints[id], pose.weapon, pose.waist, pose.neck) > MAX_DEPTH then
			return false
		end
	end
	return true
end

-- Prise valable pour toutes les armes du style : distance de la main gauche retenue par arme.
local function valid(style)
	local chosen = {}
	for _, id in ids do
		local found = nil
		if style.left == "support" and frameKey == "ready" and styleName ~= "pistol" then
			for _, ahead in AHEADS do
				if passes(style, id, supportAt(id, ahead)) then
					found = ahead
					break
				end
			end
		elseif passes(style, id, nil) then
			found = 0
		end
		if found == nil then
			return nil
		end
		chosen[id] = found
	end
	return chosen
end

local preferred = PREFERRED[styleName][frameKey]
local results = {}
local twists = if frameKey == "ready" then { 20, 30, 40, 50, 60 } else { base.twist }
if process.env.TWIST then
	twists = { tonumber(process.env.TWIST) }
end
local backs = if frameKey == "ready" then { 0, 0.6, 1.2 } else { false }
local tested = 0
for x = -0.4, 1.4, 0.1 do
	for y = -0.7, 1.5, 0.1 do
		for z = -1.9, -0.4, 0.1 do
			local hand = Vector3.new(x, y, z)
			for _, twist in twists do
				for _, back in backs do
					local style = copy(base)
					style[frameKey].hand = hand
					if frameKey == "ready" then
						style.twist = twist
						style.sprintTwist = twist
						style.pivot = hand + Vector3.new(0, 0.25, back)
					end
					tested += 1
					local chosen = valid(style)
					if chosen then
						local short = 0
						for _, ahead in chosen do
							short += (AHEADS[1] - ahead) / #ids
						end
						local cost = (hand - preferred).Magnitude
							+ (if frameKey == "ready" then twist * 0.004 else 0)
							+ short * 0.8
						table.insert(results, { cost = cost, hand = hand, twist = twist, back = back, chosen = chosen })
					end
				end
			end
		end
	end
end

table.sort(results, function(a, b)
	return a.cost < b.cost
end)
print(string.format("%s / %s : %d prises valides sur %d essayées", styleName, frameKey, #results, tested))
for index = 1, math.min(12, #results) do
	local r = results[index]
	print(
		string.format(
			"  coût %.2f  main (%.1f, %.1f, %.1f)  buste %d°  pivot %s",
			r.cost,
			r.hand.X,
			r.hand.Y,
			r.hand.Z,
			r.twist,
			if r.back then string.format("%.1f derrière la main", r.back) else "-"
		)
	)
	if index <= 3 then
		local parts = {}
		for _, id in ids do
			table.insert(parts, string.format("%s %.2f", id, r.chosen[id]))
		end
		print("      main gauche devant la droite : " .. table.concat(parts, ", "))
	end
end
