--!strict
--[[
	WeaponPoseController : armes tenues comme dans la réalité (côté client).

	- Armes à distance : le serveur les fixe devant le haut du torse (joint
	  « WeaponGrip ») ; ici, à chaque image et pour chaque combattant proche,
	  l'arme est placée (visée en haut / en bas, recul, recharge, sprint), les
	  deux mains vont dessus (bras calculés, Shared/Visuals/WeaponPose) et le
	  buste se tourne pour l'épaulé.
	- Mêlée : l'arme reste dans la main et suit les animations ; pendant un
	  coup, le bras (et la main gauche, le buste) décrit le geste, puis rend la
	  main à l'animation.
	Les jambes gardent toujours leurs animations (marche, course, saut).

	Chaque client pose tous les personnages qu'il voit, d'après leurs
	attributs (AimPitch, Sprinting, Stance, Using, ReloadUntil) et les tirs /
	coups diffusés par le serveur (`kick`, `swing`). Le joueur local envoie sa
	visée au serveur (SetAim) pour que les autres la voient.

	Les Transform des joints sont écrits après les animations (PreSimulation) :
	ceux de la taille et du cou s'ajoutent à l'animation ; ceux des bras la
	remplacent (armes à distance) ou s'y mélangent (coup de mêlée).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local WeaponPose = require(Shared.Visuals.WeaponPose)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)

local Poses = Config.WeaponPoses

local WeaponPoseController = {}

type Arm = {
	shoulder: Motor6D,
	elbow: Motor6D,
	wrist: Motor6D,
	rig: WeaponPose.ArmRig,
}

type Joints = {
	visual: Instance, -- modèle de l'arme (recréé par le serveur à chaque changement)
	torso: BasePart,
	grip: Motor6D?, -- arme à distance montée sur le torse (nil : arme de mêlée)
	itemId: string,
	scale: number,
	right: Arm,
	left: Arm,
	waist: Motor6D?,
	neck: Motor6D?,
}

type Record = {
	model: Model,
	joints: Joints?,
	retryAt: number,
	pitch: number,
	sprint: number,
	kick: number,
	jitter: number,
	swingStart: number?,
	swingDuration: number,
	variant: number,
	-- Dernière valeur écrite par joint, et celle de l'animation à laquelle elle
	-- s'ajoute ou se mélange.
	written: { [Motor6D]: CFrame },
	base: { [Motor6D]: CFrame },
}

local player = Players.LocalPlayer
local records: { [Model]: Record } = {}
local random = Random.new()
local sentPitch = 0
local sentAt = -math.huge

-- Nouvelle tentative de lecture des joints (arme changée, personnage en cours de chargement).
local RETRY_INTERVAL = 0.3

local function motorIn(parent: Instance?, name: string): Motor6D?
	local found = if parent then parent:FindFirstChild(name) else nil
	return if found and found:IsA("Motor6D") then found else nil
end

local function armOf(model: Model, side: string): Arm?
	local shoulder = motorIn(model:FindFirstChild(side .. "UpperArm"), side .. "Shoulder")
	local elbow = motorIn(model:FindFirstChild(side .. "LowerArm"), side .. "Elbow")
	local wrist = motorIn(model:FindFirstChild(side .. "Hand"), side .. "Wrist")
	if shoulder == nil or elbow == nil or wrist == nil then
		return nil
	end
	return {
		shoulder = shoulder,
		elbow = elbow,
		wrist = wrist,
		rig = {
			shoulderC0 = shoulder.C0,
			shoulderC1 = shoulder.C1,
			elbowC0 = elbow.C0,
			elbowC1 = elbow.C1,
			wristC0 = wrist.C0,
			wristC1 = wrist.C1,
		},
	}
end

-- Joints d'un personnage R15 qui tient une arme (sinon nil : pas d'arme, avatar R6).
local function resolve(model: Model): Joints?
	local visual = model:FindFirstChild("WeaponVisual")
	-- L'arme du modèle (et non l'attribut WeaponId, qui peut arriver avant le nouveau modèle).
	local itemId = if visual then visual:GetAttribute("ItemId") else nil
	local torso = model:FindFirstChild("UpperTorso")
	if visual == nil or type(itemId) ~= "string" or torso == nil or not torso:IsA("BasePart") then
		return nil
	end
	local grip = motorIn(visual:FindFirstChild("Body"), "WeaponGrip")
	if WeaponPose.isMounted(itemId) and grip == nil then
		return nil -- arme à distance pas encore répliquée
	end
	local right, left = armOf(model, "Right"), armOf(model, "Left")
	if right == nil or left == nil then
		return nil
	end
	return {
		visual = visual,
		torso = torso,
		grip = grip,
		itemId = itemId,
		scale = WeaponPose.scaleOf(torso.Size),
		right = right,
		left = left,
		waist = motorIn(torso, "Waist"),
		neck = motorIn(model:FindFirstChild("Head"), "Neck"),
	}
end

local function write(record: Record, motor: Motor6D, value: CFrame)
	motor.Transform = value
	record.written[motor] = value
end

-- Valeur donnée par l'animation à cette image. Si l'animation n'a pas réécrit
-- le joint depuis la dernière image, on repart de la même base (sinon nos
-- rotations s'accumuleraient).
local function animated(record: Record, motor: Motor6D): CFrame
	local last = record.written[motor]
	local base = if last ~= nil and motor.Transform == last
		then record.base[motor] or CFrame.identity
		else motor.Transform
	record.base[motor] = base
	return base
end

-- S'ajoute à l'animation (taille, cou).
local function compose(record: Record, motor: Motor6D, extra: CFrame)
	write(record, motor, animated(record, motor) * extra)
end

-- Mélange l'animation et une pose (0 : animation, 1 : pose).
local function blend(record: Record, motor: Motor6D, target: CFrame, weight: number)
	write(record, motor, animated(record, motor):Lerp(target, weight))
end

-- Rend un joint à l'animation (ou à sa position de repos si rien ne l'anime).
local function releaseMotor(record: Record, motor: Motor6D)
	local last = record.written[motor]
	if last == nil then
		return
	end
	if motor.Parent ~= nil and motor.Transform == last then
		motor.Transform = record.base[motor] or CFrame.identity
	end
	record.written[motor] = nil
	record.base[motor] = nil
end

local function release(record: Record)
	for motor in record.written do
		releaseMotor(record, motor)
	end
end

local function releaseArm(record: Record, arm: Arm)
	releaseMotor(record, arm.shoulder)
	releaseMotor(record, arm.elbow)
	releaseMotor(record, arm.wrist)
end

local function solve(record: Record, arm: Arm, target: Vector3, pole: Vector3, handFrame: CFrame?, weight: number?)
	local shoulder, elbow, wrist = WeaponPose.solveArm(arm.rig, target, pole, handFrame)
	if weight then
		blend(record, arm.shoulder, shoulder, weight)
		blend(record, arm.elbow, elbow, weight)
		blend(record, arm.wrist, wrist, weight)
	else
		write(record, arm.shoulder, shoulder)
		write(record, arm.elbow, elbow)
		write(record, arm.wrist, wrist)
	end
end

-- Arme à distance montée sur le torse.
local function poseRanged(record: Record, joints: Joints, grip: Motor6D, dt: number, serverNow: number)
	local model = record.model
	local itemId = joints.itemId

	-- Visée : la caméra pour soi, l'attribut AimPitch (lissé) pour les autres.
	if model == player.Character then
		local camera = Workspace.CurrentCamera
		record.pitch = if camera then math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1)) else 0
	else
		local degrees = model:GetAttribute("AimPitch")
		local target = if type(degrees) == "number" then math.rad(degrees) else 0
		record.pitch += (target - record.pitch) * (1 - math.exp(-Poses.aimSmoothing * dt))
	end
	local rate = 1 - math.exp(-Poses.blendRate * dt)
	record.sprint += ((if model:GetAttribute("Sprinting") == true then 1 else 0) - record.sprint) * rate

	local ranged = Config.Weapons.ranged[itemId]
	if record.kick > 0 then
		local recoil = if ranged then Poses.recoil[ranged.class] else nil
		record.kick *= math.exp(-(if recoil then recoil.recover else 12) * dt)
		if record.kick < 0.01 then
			record.kick = 0
		end
	end

	local reload: number? = nil
	local reloadUntil = model:GetAttribute("ReloadUntil")
	local reloadTime = model:GetAttribute("ReloadTime")
	if
		type(reloadUntil) == "number"
		and type(reloadTime) == "number"
		and reloadTime > 0
		and serverNow < reloadUntil
	then
		reload = math.clamp(1 - (reloadUntil - serverNow) / reloadTime, 0, 1)
	end

	local result = WeaponPose.compute({
		itemId = itemId,
		pitch = record.pitch,
		prone = model:GetAttribute("Stance") == "prone",
		sprint = record.sprint,
		reload = reload,
		kick = record.kick,
		jitter = record.jitter,
		using = model:GetAttribute("Using") == true,
		scale = joints.scale,
	})
	if result == nil then
		release(record)
		return
	end

	-- Arme : Body = torse * C0 * Transform * C1⁻¹ = torse * result.weapon.
	write(record, grip, grip.C0:Inverse() * result.weapon * grip.C1)
	solve(record, joints.right, result.right, result.rightPole)
	local left = result.left
	if left then
		solve(record, joints.left, left, result.leftPole)
	else
		releaseArm(record, joints.left) -- main gauche libre : elle reprend l'animation
	end
	if joints.waist then
		compose(record, joints.waist, result.waist)
	end
	if joints.neck then
		compose(record, joints.neck, result.neck)
	end
end

-- Coup de mêlée en cours : le geste se mélange à l'animation (poids 0 → 1 → 0).
local function poseMelee(record: Record, joints: Joints, progress: number)
	local result = WeaponPose.meleeSwing(joints.itemId, progress, record.variant, joints.scale)
	if result == nil then
		release(record)
		return
	end
	local weight = result.weight
	solve(record, joints.right, Vector3.zero, result.rightPole, result.hand, weight)
	local left = result.left
	if left then
		solve(record, joints.left, left, result.leftPole, nil, weight)
	else
		releaseArm(record, joints.left)
	end
	if joints.waist then
		compose(record, joints.waist, result.waist)
	end
end

-- Visée du joueur local → serveur (attribut AimPitch vu par les autres).
local function sendAim(clock: number)
	local character = player.Character
	local record = if character then records[character] else nil
	if record == nil or record.joints == nil or record.joints.grip == nil then
		return
	end
	local degrees = math.clamp(math.round(math.deg(record.pitch)), -90, 90)
	if math.abs(degrees - sentPitch) >= Poses.aimSendStep and clock - sentAt >= Poses.aimSendInterval then
		sentPitch = degrees
		sentAt = clock
		ClientNet.fire("SetAim", degrees)
	end
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
	local clock = os.clock()
	local serverNow = Workspace:GetServerTimeNow()
	for model, record in records do
		local joints = record.joints
		if joints and joints.visual.Parent == nil then
			-- Arme changée (le serveur a recréé son modèle) : on relit les joints.
			release(record)
			record.joints = nil
			record.retryAt = 0
			record.swingStart = nil
			joints = nil
		end
		if joints == nil and clock >= record.retryAt then
			record.retryAt = clock + RETRY_INTERVAL
			joints = resolve(model)
			record.joints = joints
		end
		if
			joints == nil
			or model:GetAttribute("Dead") == true
			or (joints.torso.Position - cameraPosition).Magnitude > Poses.maxDistance
		then
			if next(record.written) ~= nil then
				release(record)
			end
			continue
		end
		local grip = joints.grip
		if grip then
			poseRanged(record, joints, grip, dt, serverNow)
		else
			local swingStart = record.swingStart
			local progress = if swingStart then (clock - swingStart) / record.swingDuration else 1
			if progress < 1 then
				poseMelee(record, joints, progress)
			else
				record.swingStart = nil
				if next(record.written) ~= nil then
					release(record) -- hors des coups : animations normales
				end
			end
		end
	end
	sendAim(clock)
end

local function track(instance: Instance)
	if not instance:IsA("Model") or records[instance] ~= nil then
		return
	end
	records[instance] = {
		model = instance,
		joints = nil,
		retryAt = 0,
		pitch = 0,
		sprint = 0,
		kick = 0,
		jitter = 0,
		swingStart = nil,
		swingDuration = 0.4,
		variant = 1,
		written = {},
		base = {},
	}
end

local function untrack(instance: Instance)
	local record = if instance:IsA("Model") then records[instance] else nil
	if record then
		release(record)
		records[instance :: Model] = nil
	end
end

-- Recul d'un tir (le sien, ou celui d'un autre diffusé par le serveur).
function WeaponPoseController.kick(model: Model?)
	local record = if model then records[model] else nil
	if record then
		record.kick = 1
		record.jitter = random:NextNumber(-1, 1)
	end
end

--[[
	Coup de mêlée : le bras décrit le geste (armé, frappe, retour à
	l'animation). Retourne false si le personnage n'a pas de bras articulés
	(avatar R6) : l'appelant garde alors l'ancienne animation.
]]
function WeaponPoseController.swing(model: Model?): boolean
	local record = if model then records[model] else nil
	if record == nil then
		return false
	end
	local joints = record.joints or resolve(record.model)
	if joints == nil or joints.grip ~= nil then
		return false
	end
	record.joints = joints
	record.swingStart = os.clock()
	record.swingDuration = WeaponPose.swingDuration(joints.itemId)
	record.variant = record.variant % 2 + 1
	return true
end

function WeaponPoseController.init() end

function WeaponPoseController.start()
	for _, instance in CollectionService:GetTagged("Fighter") do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal("Fighter"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("Fighter"):Connect(untrack)
	-- Après les animations, avant la physique (qui place les pièces d'après les joints).
	RunService.PreSimulation:Connect(step)
end

return WeaponPoseController
