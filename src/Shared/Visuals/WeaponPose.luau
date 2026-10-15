--!strict
--[[
	WeaponPose : posture des armes tenues (calcul pur, testé).

	Le serveur fixe l'arme devant le haut du torse (joint « WeaponGrip ») ; le
	client calcule ici, à chaque image :
	- où placer l'arme dans le repère du torse (visée en haut / en bas, recul,
	  coup de mêlée, recharge, sprint, garde) : `WeaponPose.compute` ;
	- comment plier chaque bras pour que la main rejoigne la poignée ou le
	  garde-main : `WeaponPose.solveArm` (épaule libre, coude en charnière,
	  poignet aligné sur l'avant-bras).

	Valeurs : Config/WeaponPoses (repères décrits en tête de ce fichier).
]]

local Config = require(script.Parent.Parent.Config)
local PoseConfig = require(script.Parent.Parent.Config.WeaponPoses)

local Poses = Config.WeaponPoses
local Visuals = Config.Visuals

local WeaponPose = {}

-- Joints d'un bras R15 (C0 / C1 des Motor6D épaule, coude, poignet).
export type ArmRig = {
	shoulderC0: CFrame, -- dans le haut du torse
	shoulderC1: CFrame, -- dans le haut du bras
	elbowC0: CFrame, -- dans le haut du bras
	elbowC1: CFrame, -- dans l'avant-bras
	wristC0: CFrame, -- dans l'avant-bras
	wristC1: CFrame, -- dans la main
}

export type State = {
	itemId: string,
	pitch: number, -- visée (radians, > 0 vers le haut), par rapport à l'horizontale
	prone: boolean,
	sprint: number, -- 0..1
	parry: number, -- 0..1
	reload: number?, -- avancement de la recharge 0..1
	kick: number, -- recul 0..1
	jitter: number, -- -1..1 : côté de la bascule du recul
	swing: number?, -- avancement du coup de mêlée 0..1
	variant: number, -- coup alterné (1, 2…)
	using: boolean, -- consommable dans la main gauche : elle lâche l'arme
	scale: number, -- échelle de l'avatar (voir `scaleOf`)
}

export type Pose = {
	weapon: CFrame, -- cœur de l'arme (pièce « Body »), repère du torse
	right: Vector3, -- centre de la main droite, repère du torse
	rightPole: Vector3,
	left: Vector3?, -- nil : main gauche libre
	leftPole: Vector3,
	waist: CFrame, -- rotation ajoutée à la taille (après l'animation)
	neck: CFrame, -- rotation ajoutée au cou
}

local X_AXIS = Vector3.new(1, 0, 0)
local Y_AXIS = Vector3.new(0, 1, 0)
local Z_AXIS = Vector3.new(0, 0, 1)

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function smooth(x: number): number
	local t = clamp01(x)
	return t * t * (3 - 2 * t)
end

-- Orientation dont -Z suit `tip` (bouche de l'arme) et +Y tend vers `up`.
local function orient(tip: Vector3?, up: Vector3?): CFrame
	local forward = if tip and tip.Magnitude > 1e-4 then tip.Unit else Vector3.new(0, 0, -1)
	local hint = if up and up.Magnitude > 1e-4 then up.Unit else Y_AXIS
	if math.abs(forward:Dot(hint)) > 0.95 then
		-- Arme presque à la verticale : le dessus regarde vers l'arrière.
		hint = if forward.Y > 0 then Z_AXIS else -Z_AXIS
	end
	return CFrame.lookAt(Vector3.zero, forward, hint)
end

-- Prise (position de la main droite + orientation de l'arme), repère visée.
local function frameOf(frame: PoseConfig.Frame, scale: number): CFrame
	return CFrame.new(frame.hand * scale) * orient(frame.tip, frame.up)
end

-- Main gauche libre d'une prise (poing de garde, cellule) : position, repère visée.
local function leftOf(frame: PoseConfig.Frame, scale: number): Vector3?
	return if frame.left then frame.left * scale else nil
end

local function lerpPoint(a: Vector3?, b: Vector3?, t: number): Vector3?
	if a and b then
		return a:Lerp(b, t)
	end
	return if t < 0.5 then a else b
end

-- Échelle de l'avatar d'après la hauteur du haut de son torse.
function WeaponPose.scaleOf(torsoSize: Vector3): number
	return torsoSize.Y / Poses.referenceTorsoHeight
end

-- Style de prise d'une arme (nil : pas de posture, arme inconnue).
function WeaponPose.styleOf(itemId: string): PoseConfig.Style?
	local entry = Poses.weapons[itemId]
	return if entry then Poses.styles[entry.style] else nil
end

-- Main droite dans le repère de l'arme (d'après `gripOffset`, Config/Visuals).
function WeaponPose.handInWeapon(itemId: string): Vector3
	local shape = Visuals.weapons[itemId]
	return if shape then shape.gripOffset:Inverse().Position else Vector3.zero
end

-- Durée d'un coup de mêlée (secondes).
function WeaponPose.swingDuration(itemId: string): number
	local def = Config.Weapons.melee[itemId]
	local rate = if def then def.attacksPerSecond else 1.5
	return math.clamp(Poses.swingScale / rate, Poses.swingMin, Poses.swingMax)
end

--[[
	Arme au repos (prise de base, visée horizontale, buste non tourné), repère
	du torse : position donnée par le serveur au joint de l'arme, et posture
	vue tant qu'un client ne pose pas le personnage.
]]
function WeaponPose.rest(itemId: string, scale: number): CFrame
	local style = WeaponPose.styleOf(itemId)
	if style == nil then
		return CFrame.new(0.5 * scale, 0, -1 * scale)
	end
	return frameOf(style.ready, scale) * CFrame.new(-WeaponPose.handInWeapon(itemId))
end

-- Prise pendant un coup : départ → armé → frappe → retour.
local function swingFrame(
	style: PoseConfig.Style,
	base: CFrame,
	baseLeft: Vector3?,
	progress: number,
	variant: number,
	scale: number
): (CFrame, Vector3?)
	local swings = style.swings
	if swings == nil or #swings == 0 then
		return base, baseLeft
	end
	local swing = swings[(variant - 1) % #swings + 1]
	local windup = frameOf(swing.windup, scale)
	local strike = frameOf(swing.strike, scale)
	local windupLeft = leftOf(swing.windup, scale) or baseLeft
	local strikeLeft = leftOf(swing.strike, scale) or baseLeft
	local timing = Poses.swingTiming
	local p = clamp01(progress)
	if p < timing.windup then
		-- Armer : rapide puis ralenti.
		local t = p / timing.windup
		t = 1 - (1 - t) * (1 - t)
		return base:Lerp(windup, t), lerpPoint(baseLeft, windupLeft, t)
	elseif p < timing.strike then
		-- Frapper : accélère jusqu'à l'impact.
		local t = (p - timing.windup) / (timing.strike - timing.windup)
		t = t * t
		return windup:Lerp(strike, t), lerpPoint(windupLeft, strikeLeft, t)
	end
	local t = smooth((p - timing.strike) / (1 - timing.strike))
	return strike:Lerp(base, t), lerpPoint(strikeLeft, baseLeft, t)
end

--[[
	Posture complète d'une arme tenue (nil si l'arme n'a pas de style).
]]
function WeaponPose.compute(state: State): Pose?
	local itemId = state.itemId
	local style = WeaponPose.styleOf(itemId)
	if style == nil then
		return nil
	end
	local scale = state.scale
	local rangedDef = Config.Weapons.ranged[itemId]

	-- Prise de base, puis sprint, garde et recharge par-dessus.
	local grip = frameOf(style.ready, scale)
	local left = leftOf(style.ready, scale)
	if state.sprint > 0 then
		local t = smooth(state.sprint)
		grip = grip:Lerp(frameOf(style.sprint, scale), t)
		left = lerpPoint(left, leftOf(style.sprint, scale) or left, t)
	end
	local parryFrame = style.parry
	if parryFrame and state.parry > 0 then
		local t = smooth(state.parry)
		grip = grip:Lerp(frameOf(parryFrame, scale), t)
		left = lerpPoint(left, leftOf(parryFrame, scale) or left, t)
	end
	local reloadFrame = style.reload
	local reloadLeft: Vector3? = nil
	local reloadReach = 0
	local reload = state.reload
	if reloadFrame and reload then
		local ease = Poses.reloadEase
		local t = smooth(math.min(reload / ease, (1 - reload) / ease, 1))
		grip = grip:Lerp(frameOf(reloadFrame, scale), t)
		-- La main gauche quitte l'arme, va chercher une cellule et revient.
		reloadLeft = leftOf(reloadFrame, scale)
		reloadReach = math.sin(math.pi * clamp01((reload - 0.2) / 0.6))
	end
	if state.swing then
		grip, left = swingFrame(style, grip, left, state.swing, state.variant, scale)
	end

	-- Recul : l'arme recule et le canon se relève, autour de la poignée.
	if rangedDef and state.kick > 0 then
		local recoil = Poses.recoil[rangedDef.class]
		if recoil then
			local k = state.kick
			grip = grip
				* CFrame.new(0, 0, recoil.back * k * scale)
				* CFrame.Angles(math.rad(recoil.angle) * k, 0, math.rad(recoil.roll) * k * state.jitter)
		end
	end

	-- Visée en haut / en bas : le buste se penche un peu, l'arme fait le reste.
	local P = Poses.pitch
	local pitch = math.clamp(state.pitch, -math.rad(P.max), math.rad(P.max))
	local lean = if state.prone then 0 else pitch * P.waistShare
	local relative = (pitch - lean) * style.pitchFactor
	if state.prone then
		-- Couché, le torse est à l'horizontale : l'arme pivote d'un quart de tour,
		-- ramenée vers le centre pour que les deux mains l'atteignent.
		relative += math.rad(90)
		local shift = CFrame.new(Poses.prone.shift * scale)
		grip = shift * grip
		left = if left then shift * left else nil
	end
	local pivot = style.pivot * scale
	local aim = CFrame.new(pivot) * CFrame.Angles(relative, 0, 0) * CFrame.new(-pivot)
	local gripAim = aim * grip
	local leftAim = if left then aim * left else nil

	-- Buste tourné vers la droite (épaulé) : compensé pour viser droit devant.
	local twist = if state.prone
		then 0
		else math.rad(style.twist + (style.sprintTwist - style.twist) * smooth(state.sprint))
	local toTorso = CFrame.Angles(0, twist, 0)
	local gripTorso = toTorso * gripAim
	local weapon = gripTorso * CFrame.new(-WeaponPose.handInWeapon(itemId))

	local leftTarget: Vector3? = nil
	if not state.using then
		if style.left == "support" then
			local support = Poses.weapons[itemId].support
			leftTarget = if support then weapon * support else nil
		elseif style.left == "fist" and leftAim then
			leftTarget = toTorso * leftAim
		end
		if leftTarget and reloadLeft and reloadReach > 0 then
			leftTarget = leftTarget:Lerp(toTorso * reloadLeft, reloadReach)
		end
	end

	local headPitch = (pitch - lean) * P.headShare + (if state.prone then math.rad(Poses.prone.head) else 0)
	return {
		weapon = weapon,
		right = gripTorso.Position,
		rightPole = toTorso:VectorToWorldSpace(style.rightPole),
		left = leftTarget,
		leftPole = toTorso:VectorToWorldSpace(style.leftPole),
		waist = CFrame.Angles(lean, 0, 0) * CFrame.Angles(0, -twist, 0),
		neck = CFrame.Angles(0, twist, 0) * CFrame.Angles(headPitch, 0, 0),
	}
end

-- Rotation qui amène le repère (xA, yA) sur (xB, yB) (axes unitaires et orthogonaux).
local function alignFrames(xA: Vector3, yA: Vector3, xB: Vector3, yB: Vector3): CFrame
	local a = CFrame.fromMatrix(Vector3.zero, xA, yA, xA:Cross(yA))
	local b = CFrame.fromMatrix(Vector3.zero, xB, yB, xB:Cross(yB))
	return b * a:Inverse()
end

-- Sépare un vecteur en sa composante le long de l'axe du coude (X) et le reste.
local function splitHinge(vector: Vector3): (number, Vector3)
	return vector.X, Vector3.new(0, vector.Y, vector.Z)
end

--[[
	Bras à deux segments (repère du torse) : la main (son centre) rejoint
	`target`, le coude pointe vers `pole`. Retourne les Transform des Motor6D
	de l'épaule, du coude et du poignet, et si la cible est à portée.

	Le coude est une charnière (axe X du bras, comme le coude R15) ; le
	poignet garde la main dans l'axe de l'avant-bras.
]]
function WeaponPose.solveArm(rig: ArmRig, target: Vector3, pole: Vector3): (CFrame, CFrame, CFrame, boolean)
	local shoulder = rig.shoulderC0.Position
	-- Segments, dans le repère de chaque pièce : épaule → coude, coude → centre de la main.
	local upperBone = rig.elbowC0.Position - rig.shoulderC1.Position
	local handInLower = (rig.wristC0 * rig.wristC1:Inverse()).Position
	local lowerBone = handInLower - rig.elbowC1.Position
	local upperSide, upperPlane = splitHinge(upperBone)
	local lowerSide, lowerPlane = splitHinge(lowerBone)
	local l1, l2 = upperPlane.Magnitude, lowerPlane.Magnitude

	-- Les décalages le long de l'axe du coude (`sides`) ne participent pas au
	-- pli : l'axe est incliné vers la cible juste assez pour les absorber, et
	-- le pli se résout dans le plan perpendiculaire.
	local sides = upperSide + lowerSide
	local toTarget = target - shoulder
	local targetDistance = toTarget.Magnitude
	local toward = if targetDistance > 1e-4 then toTarget / targetDistance else Vector3.new(0, -1, 0)
	local side = pole - toward * pole:Dot(toward)
	if side.Magnitude < 1e-4 then
		side = Z_AXIS - toward * toward.Z
	end
	local across = side.Unit:Cross(toward).Unit
	local along = math.clamp(sides / math.max(targetDistance, 1e-4), -0.95, 0.95)
	local hinge = (toward * along + across * math.sqrt(1 - along * along)).Unit
	local planeOffset = toTarget - hinge * sides
	planeOffset -= hinge * planeOffset:Dot(hinge)
	local distance = planeOffset.Magnitude
	local direction = if distance > 1e-4 then planeOffset / distance else Vector3.new(0, -1, 0)
	local towardElbow = direction:Cross(hinge).Unit
	local reach = math.clamp(distance, math.abs(l1 - l2) + 1e-3, l1 + l2 - 1e-3)
	local cosA = math.clamp((l1 * l1 + reach * reach - l2 * l2) / (2 * l1 * reach), -1, 1)
	local sinA = math.sqrt(1 - cosA * cosA)
	local upperVector = (direction * cosA + towardElbow * sinA) * l1
	local lowerVector = direction * reach - upperVector

	-- Orientation des deux segments : axe X sur la charnière, os dans le plan.
	local upperRotation = alignFrames(X_AXIS, -upperPlane.Unit, hinge, -upperVector.Unit)
	local lowerRotation = alignFrames(X_AXIS, -lowerPlane.Unit, hinge, -lowerVector.Unit)
	local upper = CFrame.new(shoulder - upperRotation * rig.shoulderC1.Position) * upperRotation
	local elbow = upper * rig.elbowC0.Position
	local lower = CFrame.new(elbow - lowerRotation * rig.elbowC1.Position) * lowerRotation

	local shoulderTransform = rig.shoulderC0:Inverse() * upper * rig.shoulderC1
	local elbowTransform = rig.elbowC0:Inverse() * upper:Inverse() * lower * rig.elbowC1
	return shoulderTransform, elbowTransform, CFrame.new(), distance <= l1 + l2
end

return WeaponPose
