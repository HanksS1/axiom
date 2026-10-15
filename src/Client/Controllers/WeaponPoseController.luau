--!strict
--[[
	WeaponPoseController : armes tenues comme dans la réalité (côté client).

	Le serveur fixe l'arme devant le haut du torse (joint « WeaponGrip ») ;
	ici, à chaque image et pour chaque combattant proche :
	- l'arme est placée (visée en haut / en bas, recul des tirs, coup de
	  mêlée, recharge, sprint, garde) ;
	- les deux mains vont sur la poignée et le garde-main (bras calculés,
	  Shared/Visuals/WeaponPose), le buste se tourne pour l'épaulé ;
	- les jambes gardent leurs animations (marche, course, saut).

	Chaque client pose tous les personnages qu'il voit, d'après leurs
	attributs (AimPitch, Sprinting, Parrying, Stance, Using, ReloadUntil) et
	les tirs / coups diffusés par le serveur (`kick`, `swing`). Le joueur local
	envoie sa visée au serveur (SetAim) pour que les autres la voient.

	Les Transform des joints sont écrits après les animations (PreSimulation) :
	ceux de la taille et du cou s'ajoutent à l'animation, ceux des bras la
	remplacent.
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
	torso: BasePart,
	grip: Motor6D,
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
	parry: number,
	kick: number,
	jitter: number,
	swingStart: number?,
	swingDuration: number,
	variant: number,
	-- Dernière valeur écrite par joint (et, pour la taille et le cou, celle de
	-- l'animation à laquelle elle s'ajoute).
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

-- Joints d'un personnage R15 qui tient une arme montée sur le torse (sinon nil).
local function resolve(model: Model): Joints?
	local visual = model:FindFirstChild("WeaponVisual")
	local grip = motorIn(if visual then visual:FindFirstChild("Body") else nil, "WeaponGrip")
	-- L'arme du modèle (et non l'attribut WeaponId, qui peut arriver avant le nouveau modèle).
	local itemId = if visual then visual:GetAttribute("ItemId") else nil
	local torso = model:FindFirstChild("UpperTorso")
	if grip == nil or type(itemId) ~= "string" or torso == nil or not torso:IsA("BasePart") then
		return nil
	end
	local right, left = armOf(model, "Right"), armOf(model, "Left")
	if right == nil or left == nil then
		return nil
	end
	return {
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

-- S'ajoute à l'animation : si l'animation n'a pas réécrit le joint depuis la
-- dernière image, on repart de la même base (sinon la rotation s'accumulerait).
local function compose(record: Record, motor: Motor6D, extra: CFrame)
	local last = record.written[motor]
	local base = if last ~= nil and motor.Transform == last
		then record.base[motor] or CFrame.identity
		else motor.Transform
	record.base[motor] = base
	write(record, motor, base * extra)
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

local function solve(record: Record, arm: Arm, target: Vector3, pole: Vector3)
	local shoulder, elbow, wrist = WeaponPose.solveArm(arm.rig, target, pole)
	write(record, arm.shoulder, shoulder)
	write(record, arm.elbow, elbow)
	write(record, arm.wrist, wrist)
end

local function pose(record: Record, joints: Joints, dt: number, clock: number, serverNow: number)
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
	local blend = 1 - math.exp(-Poses.blendRate * dt)
	record.sprint += ((if model:GetAttribute("Sprinting") == true then 1 else 0) - record.sprint) * blend
	record.parry += ((if model:GetAttribute("Parrying") == true then 1 else 0) - record.parry) * blend

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
		ranged
		and type(reloadUntil) == "number"
		and type(reloadTime) == "number"
		and reloadTime > 0
		and serverNow < reloadUntil
	then
		reload = math.clamp(1 - (reloadUntil - serverNow) / reloadTime, 0, 1)
	end

	local swing: number? = nil
	local swingStart = record.swingStart
	if swingStart then
		local progress = (clock - swingStart) / record.swingDuration
		if progress >= 1 then
			record.swingStart = nil
		else
			swing = progress
		end
	end

	local result = WeaponPose.compute({
		itemId = itemId,
		pitch = record.pitch,
		prone = model:GetAttribute("Stance") == "prone",
		sprint = record.sprint,
		parry = record.parry,
		reload = reload,
		kick = record.kick,
		jitter = record.jitter,
		swing = swing,
		variant = record.variant,
		using = model:GetAttribute("Using") == true,
		scale = joints.scale,
	})
	if result == nil then
		release(record)
		return
	end

	-- Arme : Body = torse * C0 * Transform * C1⁻¹ = torse * result.weapon.
	local grip = joints.grip
	write(record, grip, grip.C0:Inverse() * result.weapon * grip.C1)
	solve(record, joints.right, result.right, result.rightPole)
	local left = result.left
	if left then
		solve(record, joints.left, left, result.leftPole)
	else
		-- Main gauche libre : elle reprend l'animation.
		releaseMotor(record, joints.left.shoulder)
		releaseMotor(record, joints.left.elbow)
		releaseMotor(record, joints.left.wrist)
	end
	if joints.waist then
		compose(record, joints.waist, result.waist)
	end
	if joints.neck then
		compose(record, joints.neck, result.neck)
	end
end

-- Visée du joueur local → serveur (attribut AimPitch vu par les autres).
local function sendAim(clock: number)
	local character = player.Character
	local record = if character then records[character] else nil
	if record == nil or record.joints == nil then
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
		if joints and joints.grip.Parent == nil then
			-- Arme changée (le serveur a recréé son modèle) : on relit les joints.
			release(record)
			record.joints = nil
			record.retryAt = 0
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
		pose(record, joints, dt, clock, serverNow)
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
		parry = 0,
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
	Coup de mêlée : l'arme décrit son geste (armé, frappe, retour), les mains
	suivent. Retourne false si le personnage n'a pas d'arme montée sur le
	torse (avatar R6) : l'appelant garde alors l'ancienne animation.
]]
function WeaponPoseController.swing(model: Model?): boolean
	local record = if model then records[model] else nil
	if record == nil then
		return false
	end
	local joints = record.joints or resolve(record.model)
	if joints == nil then
		return false
	end
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
