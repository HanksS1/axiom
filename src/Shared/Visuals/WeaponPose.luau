--!strict
--[[
	WeaponPose : posture des armes tenues (calcul pur, testé).

	- Armes à distance : le serveur les fixe devant le haut du torse (joint
	  « WeaponGrip ») ; `compute` place l'arme dans le repère du torse (visée,
	  recul, recharge, sprint) et donne où vont les deux mains.
	- Mêlée : l'arme reste soudée à la main droite (animations normales) ;
	  `meleeSwing` donne, pendant un coup, la position et l'orientation de la
	  main, la main gauche et la rotation du buste, avec le poids du geste
	  (0 : animation, 1 : geste).
	- `solveArm` plie un bras (épaule libre, coude en charnière) pour que la
	  main rejoigne un point, ou une position et une orientation imposées.

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

-- Arme à distance tenue.
export type State = {
	itemId: string,
	pitch: number, -- visée (radians, > 0 vers le haut), par rapport à l'horizontale
	prone: boolean,
	sprint: number, -- 0..1
	reload: number?, -- avancement de la recharge 0..1
	kick: number, -- recul 0..1
	jitter: number, -- -1..1 : côté de la bascule du recul
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

-- Coup de mêlée en cours.
export type MeleePose = {
	weight: number, -- 0 : animation normale, 1 : geste du coup
	hand: CFrame, -- main droite (position et orientation), repère du torse
	weapon: CFrame, -- cœur de l'arme (soudée à la main), repère du torse
	rightPole: Vector3,
	left: Vector3?, -- nil : main gauche libre (animation)
	leftPole: Vector3,
	waist: CFrame, -- rotation du buste, déjà pondérée par `weight`
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

-- Prise (position de la main droite + orientation de l'arme).
local function frameOf(frame: PoseConfig.Frame, scale: number): CFrame
	return CFrame.new(frame.hand * scale) * orient(frame.tip, frame.up)
end

-- Main gauche libre d'une prise (cellule, poing de garde).
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

-- Style de prise d'une arme à distance (nil : arme de mêlée ou inconnue).
function WeaponPose.styleOf(itemId: string): PoseConfig.Style?
	local entry = Poses.weapons[itemId]
	return if entry then Poses.styles[entry.style] else nil
end

-- L'arme est-elle montée sur le torse (arme à distance) ?
function WeaponPose.isMounted(itemId: string): boolean
	return WeaponPose.styleOf(itemId) ~= nil
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
	Arme à distance au repos (prise de base, visée horizontale, buste non
	tourné), repère du torse : position donnée par le serveur au joint de
	l'arme, vue tant qu'un client ne pose pas le personnage.
]]
function WeaponPose.rest(itemId: string, scale: number): CFrame
	local style = WeaponPose.styleOf(itemId)
	if style == nil then
		return CFrame.new(0.5 * scale, 0, -1 * scale)
	end
	return frameOf(style.ready, scale) * CFrame.new(-WeaponPose.handInWeapon(itemId))
end

--[[
	Posture d'une arme à distance tenue (nil si l'arme n'a pas de style).
	`styleOverride`, `supportOverride` : prise et point de la main gauche à
	essayer à la place de ceux de la config (outil tests/tools/weapon_pose_tune.luau).
]]
function WeaponPose.compute(state: State, styleOverride: PoseConfig.Style?, supportOverride: Vector3?): Pose?
	local itemId = state.itemId
	local style = styleOverride or WeaponPose.styleOf(itemId)
	if style == nil then
		return nil
	end
	local scale = state.scale
	local rangedDef = Config.Weapons.ranged[itemId]

	-- Prise de base, puis sprint et recharge par-dessus.
	local grip = frameOf(style.ready, scale)
	if state.sprint > 0 then
		grip = grip:Lerp(frameOf(style.sprint, scale), smooth(state.sprint))
	end
	local reloadLeft: Vector3? = nil
	local reloadReach = 0
	local reload = state.reload
	if reload then
		local ease = Poses.reloadEase
		local t = smooth(math.min(reload / ease, (1 - reload) / ease, 1))
		grip = grip:Lerp(frameOf(style.reload, scale), t)
		-- La main gauche quitte l'arme, va chercher une cellule et revient.
		reloadLeft = leftOf(style.reload, scale)
		reloadReach = math.sin(math.pi * clamp01((reload - 0.2) / 0.6))
	end

	-- Recul : l'arme recule un peu et le canon se relève autour de la crosse.
	if rangedDef and state.kick > 0 then
		local recoil = Poses.recoil[rangedDef.class]
		if recoil then
			local k = state.kick
			local stock = CFrame.new(0, 0, Poses.recoilPivotBack * scale)
			grip = grip
				* CFrame.new(0, 0, recoil.back * k * scale)
				* stock
				* CFrame.Angles(math.rad(recoil.angle) * k, 0, math.rad(recoil.roll) * k * state.jitter)
				* stock:Inverse()
		end
	end

	-- Visée en haut / en bas : le buste se penche, l'arme fait le reste.
	local P = Poses.pitch
	local pitch = math.clamp(state.pitch, -math.rad(P.max), math.rad(P.max))
	local lean = if state.prone then 0 else pitch * P.waistShare
	local relative = (pitch - lean) * style.pitchFactor
	if state.prone then
		-- Couché, le torse est à l'horizontale : l'arme pivote d'un quart de tour,
		-- ramenée vers le centre pour que les deux mains l'atteignent.
		relative += math.rad(90)
		grip = CFrame.new(Poses.prone.shift * scale) * grip
	end
	local pivot = style.pivot * scale
	local aim = CFrame.new(pivot) * CFrame.Angles(relative, 0, 0) * CFrame.new(-pivot)
	local gripAim = aim * grip

	-- Buste tourné vers la droite (épaulé) : compensé pour viser droit devant.
	local twist = if state.prone
		then 0
		else math.rad(style.twist + (style.sprintTwist - style.twist) * smooth(state.sprint))
	local toTorso = CFrame.Angles(0, twist, 0)
	local gripTorso = toTorso * gripAim
	local weapon = gripTorso * CFrame.new(-WeaponPose.handInWeapon(itemId))

	local leftTarget: Vector3? = nil
	if not state.using and style.left == "support" then
		local entry = Poses.weapons[itemId]
		local support = supportOverride or (if entry then entry.support else nil)
		leftTarget = if support then weapon * support else nil
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

--[[
	Coup de mêlée à l'instant `progress` (0..1) du geste n° `variant` (nil si
	l'arme n'a pas de geste). L'arme suit la main (même prise que dans les
	animations : `gripOffset`) ; le poids passe de 0 à 1 pendant l'armé, puis
	revient à 0 après la frappe (le bras retrouve son animation).
]]
function WeaponPose.meleeSwing(itemId: string, progress: number, variant: number, scale: number): MeleePose?
	local entry = Poses.melee[itemId]
	local set = if entry then Poses.swings[entry.swing] else nil
	local shape = Visuals.weapons[itemId]
	if entry == nil or set == nil or shape == nil or #set.swings == 0 then
		return nil
	end
	local swing = set.swings[(variant - 1) % #set.swings + 1]
	local timing = Poses.swingTiming
	local p = clamp01(progress)

	local windup = frameOf(swing.windup, scale)
	local strike = frameOf(swing.strike, scale)
	local windupLeft, strikeLeft = leftOf(swing.windup, scale), leftOf(swing.strike, scale)
	local windupTwist, strikeTwist = swing.windup.twist or 0, swing.strike.twist or 0
	local grip, left, twist, weight
	if p < timing.windup then
		-- Armer : le bras quitte l'animation, rapide puis ralenti.
		local t = p / timing.windup
		grip, left, twist, weight = windup, windupLeft, windupTwist, 1 - (1 - t) * (1 - t)
	elseif p < timing.strike then
		-- Frapper : accélère jusqu'à l'impact.
		local t = (p - timing.windup) / (timing.strike - timing.windup)
		t = t * t
		local through = swing.through
		if through then
			-- Par le passage obligé : l'arme reste devant le personnage.
			local mid = frameOf(through, scale)
			local midLeft = leftOf(through, scale) or lerpPoint(windupLeft, strikeLeft, 0.5)
			local midTwist = through.twist or (windupTwist + strikeTwist) / 2
			if t < 0.5 then
				local u = t * 2
				grip, left = windup:Lerp(mid, u), lerpPoint(windupLeft, midLeft, u)
				twist = windupTwist + (midTwist - windupTwist) * u
			else
				local u = t * 2 - 1
				grip, left = mid:Lerp(strike, u), lerpPoint(midLeft, strikeLeft, u)
				twist = midTwist + (strikeTwist - midTwist) * u
			end
		else
			grip = windup:Lerp(strike, t)
			left = lerpPoint(windupLeft, strikeLeft, t)
			twist = windupTwist + (strikeTwist - windupTwist) * t
		end
		weight = 1
	else
		-- Revenir à l'animation.
		grip, left, twist = strike, strikeLeft, strikeTwist
		weight = 1 - smooth((p - timing.strike) / (1 - timing.strike))
	end

	-- Arme soudée à la main : main = arme * gripOffset⁻¹.
	local weapon = grip * CFrame.new(-WeaponPose.handInWeapon(itemId))
	local hand = weapon * shape.gripOffset:Inverse()
	local leftTarget: Vector3? = nil
	if set.left == "support" and entry.support then
		leftTarget = weapon * entry.support
	elseif set.left == "fist" then
		leftTarget = left
	end
	return {
		weight = weight,
		hand = hand,
		weapon = weapon,
		rightPole = set.rightPole,
		left = leftTarget,
		leftPole = set.leftPole,
		waist = CFrame.Angles(0, -math.rad(twist) * weight, 0),
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
	Bras à deux segments (repère du torse), coude orienté vers `pole`.
	- Sans `handFrame` : le centre de la main rejoint `target`, la main dans
	  l'axe de l'avant-bras.
	- Avec `handFrame` (position et orientation voulues de la main) : le
	  poignet rejoint sa place et tourne pour orienter la main (`target` est
	  alors ignoré).
	Retourne les Transform des Motor6D de l'épaule, du coude et du poignet, et
	si la cible est à portée.

	Le coude est une charnière (axe X du bras, comme le coude R15).
]]
function WeaponPose.solveArm(
	rig: ArmRig,
	target: Vector3,
	pole: Vector3,
	handFrame: CFrame?
): (CFrame, CFrame, CFrame, boolean)
	local shoulder = rig.shoulderC0.Position
	-- Segments, dans le repère de chaque pièce : épaule → coude, coude → bout
	-- (centre de la main, ou poignet si l'orientation de la main est imposée).
	local upperBone = rig.elbowC0.Position - rig.shoulderC1.Position
	local endInLower = if handFrame then rig.wristC0.Position else (rig.wristC0 * rig.wristC1:Inverse()).Position
	local lowerBone = endInLower - rig.elbowC1.Position
	local goal = if handFrame then handFrame * rig.wristC1.Position else target
	local upperSide, upperPlane = splitHinge(upperBone)
	local lowerSide, lowerPlane = splitHinge(lowerBone)
	local l1, l2 = upperPlane.Magnitude, lowerPlane.Magnitude

	-- Les décalages le long de l'axe du coude (`sides`) ne participent pas au
	-- pli : l'axe est incliné vers la cible juste assez pour les absorber, et
	-- le pli se résout dans le plan perpendiculaire.
	local sides = upperSide + lowerSide
	local toTarget = goal - shoulder
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
	local wristTransform = if handFrame
		-- Rotation seule : hors de portée, la main reste au bout du bras.
		then ((lower * rig.wristC0):Inverse() * handFrame * rig.wristC1).Rotation
		else CFrame.new()
	return shoulderTransform, elbowTransform, wristTransform, distance <= l1 + l2
end

return WeaponPose
