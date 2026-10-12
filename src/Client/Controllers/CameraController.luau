--!strict
--[[
	CameraController : caméra à la troisième personne, par-dessus l'épaule (5.1).

	Caméra entièrement scriptée (CameraType = Scriptable) pour maîtriser :
	- la sensibilité par périphérique (souris, tactile, manette) ;
	- la visée (caméra resserrée + léger zoom) et l'inversion d'épaule ;
	- l'abaissement selon la posture ;
	- l'anti-traversée des murs (la caméra se rapproche en cas d'obstacle) ;
	- l'orientation du personnage, qui suit toujours la caméra (tir précis).

	Le tactile fait tourner la caméra en glissant sur la moitié droite de
	l'écran (hors boutons) ; le bouton de tir transmet aussi ses glissements
	via `addLookDelta` pour viser en tirant.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local InputController = require(script.Parent.InputController)
local ProfileController = require(script.Parent.ProfileController)
local PanelState = require(script.Parent.Parent.UI.PanelState)

local CameraConfig = Config.Combat.camera

local CameraController = {}

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local yaw = 0
local pitch = 0
local aiming = false
local stanceOffsetY = 0
local currentOffset = CameraConfig.shoulderOffset
local currentDistance = CameraConfig.distance
local currentFov = CameraConfig.fieldOfView
local currentStanceY = 0
local enabled = true
local mouseFree = false
-- Tremblement (effondrements, grondements, Gardien qui surgit).
local shakeIntensity = 0
local shakeUntil = 0
local shakeDuration = 1

local MAX_PITCH = math.rad(75)
local MOUSE_FACTOR = math.rad(0.25) -- radians par pixel à sensibilité 1
local TOUCH_FACTOR = math.rad(0.3)
local GAMEPAD_RATE = math.rad(260) -- radians par seconde à sensibilité 1, stick à fond

local occlusionParams = RaycastParams.new()
occlusionParams.FilterType = Enum.RaycastFilterType.Exclude
occlusionParams.RespectCanCollide = true

-- Touches tactiles qui font tourner la caméra (commencées hors interface, moitié droite).
local lookTouches: { [InputObject]: boolean } = {}
local gamepadLook = Vector2.zero

local function setting(key: string, fallback: number): number
	local view = ProfileController.get()
	local value = if view then view.settings[key] else nil
	return if type(value) == "number" then value else fallback
end

local function shoulderSide(): number
	local view = ProfileController.get()
	return if view and view.settings.cameraShoulder == "left" then -1 else 1
end

-- Rotation de la caméra (radians) ; utilisé par la souris, le tactile et le bouton de tir.
function CameraController.addLookDelta(deltaYaw: number, deltaPitch: number)
	yaw -= deltaYaw
	pitch = math.clamp(pitch - deltaPitch, -MAX_PITCH, MAX_PITCH)
end

function CameraController.addTouchDelta(delta: Vector2)
	local factor = TOUCH_FACTOR * setting("touchSensitivity", 1) * (if aiming then 0.6 else 1)
	CameraController.addLookDelta(delta.X * factor, delta.Y * factor)
end

function CameraController.setAiming(value: boolean)
	aiming = value
end

function CameraController.isAiming(): boolean
	return aiming
end

function CameraController.setStanceOffset(offsetY: number)
	stanceOffsetY = offsetY
end

function CameraController.setEnabled(value: boolean)
	enabled = value
end

-- Rayon partant du centre de l'écran (réticule).
function CameraController.centerRay(): Ray
	local viewport = camera.ViewportSize
	return camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
end

function CameraController.lookVector(): Vector3
	return camera.CFrame.LookVector
end

local function lerp(a: number, b: number, alpha: number): number
	return a + (b - a) * alpha
end

local function update(dt: number)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not enabled or root == nil or humanoid == nil then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable

	-- Manette : stick droit.
	if gamepadLook.Magnitude > 0.15 then
		local sensitivity = setting("gamepadSensitivity", 1) * (if aiming then 0.55 else 1)
		local stick = gamepadLook * gamepadLook.Magnitude -- courbe quadratique (précision)
		CameraController.addLookDelta(
			stick.X * GAMEPAD_RATE * sensitivity * dt,
			-stick.Y * GAMEPAD_RATE * sensitivity * dt
		)
	end

	-- Transitions douces (visée, posture).
	local alpha = math.clamp(dt / CameraConfig.transitionTime, 0, 1)
	local targetOffset = if aiming then CameraConfig.aimShoulderOffset else CameraConfig.shoulderOffset
	currentOffset = currentOffset:Lerp(targetOffset, alpha)
	currentDistance = lerp(currentDistance, if aiming then CameraConfig.aimDistance else CameraConfig.distance, alpha)
	currentFov = lerp(currentFov, if aiming then CameraConfig.aimFieldOfView else CameraConfig.fieldOfView, alpha)
	currentStanceY = lerp(currentStanceY, stanceOffsetY, alpha)
	camera.FieldOfView = currentFov

	local focus = root.Position + Vector3.new(0, 1.5 + currentStanceY, 0)
	local rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	local base = CFrame.new(focus) * rotation
	local shoulder = base * CFrame.new(currentOffset.X * shoulderSide(), currentOffset.Y, 0)
	local desired = shoulder * CFrame.new(0, 0, currentDistance)

	-- Anti-traversée : obstacle entre le personnage et l'épaule, puis l'épaule et la caméra.
	occlusionParams.FilterDescendantsInstances = { character :: Instance }
	local position = desired.Position
	local toShoulder = shoulder.Position - focus
	local hit = Workspace:Raycast(focus, toShoulder, occlusionParams)
	if hit then
		position = hit.Position - toShoulder.Unit * 0.3
	else
		local toCamera = desired.Position - shoulder.Position
		hit = Workspace:Raycast(shoulder.Position, toCamera, occlusionParams)
		if hit then
			position = hit.Position - toCamera.Unit * 0.3
		end
	end
	local shake = CFrame.identity
	local clock = os.clock()
	if clock < shakeUntil then
		local fade = (shakeUntil - clock) / shakeDuration
		local amount = math.rad(shakeIntensity) * fade
		shake = CFrame.Angles(
			math.noise(clock * 18, 1.3) * amount,
			math.noise(clock * 18, 7.1) * amount,
			math.noise(clock * 18, 4.7) * amount * 0.5
		)
	end
	camera.CFrame = CFrame.new(position) * rotation * shake

	-- Le personnage regarde toujours dans la direction de la caméra.
	if humanoid.Health > 0 and not root.Anchored then
		humanoid.AutoRotate = false
		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
	end

	-- Souris verrouillée au centre (réticule), sauf si un menu l'a libérée.
	-- Réappliqué à chaque image : les scripts Roblox par défaut peuvent la libérer.
	if not mouseFree and InputController.device() == "keyboard" then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
end

-- Fait trembler la caméra (`intensity` en degrés, décroît sur `duration` secondes).
function CameraController.shake(intensity: number, duration: number)
	local clock = os.clock()
	if clock < shakeUntil and intensity < shakeIntensity then
		return
	end
	shakeIntensity = intensity
	shakeDuration = math.max(0.1, duration)
	shakeUntil = clock + shakeDuration
end

-- Libère / reverrouille la souris (menus, inventaire).
function CameraController.setMouseFree(free: boolean)
	mouseFree = free
	UserInputService.MouseBehavior = if free then Enum.MouseBehavior.Default else Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = free
end

function CameraController.init() end

function CameraController.start()
	CameraController.setMouseFree(false)
	-- Panneau ouvert (sac, conteneur…) : souris libre, actions relâchées.
	PanelState.Changed:Connect(function(anyOpen)
		CameraController.setMouseFree(anyOpen)
		if anyOpen then
			InputController.releaseAll()
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
				local factor = MOUSE_FACTOR * setting("mouseSensitivity", 1) * (if aiming then 0.6 else 1)
				CameraController.addLookDelta(input.Delta.X * factor, input.Delta.Y * factor)
			end
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			gamepadLook = Vector2.new(input.Position.X, input.Position.Y)
		elseif input.UserInputType == Enum.UserInputType.Touch and lookTouches[input] and not processed then
			CameraController.addTouchDelta(input.Delta)
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if input.UserInputType == Enum.UserInputType.Touch and not processed then
			if input.Position.X > camera.ViewportSize.X * 0.4 then
				lookTouches[input] = true
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		lookTouches[input] = nil
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			gamepadLook = Vector2.zero
		end
	end)

	player.CharacterAdded:Connect(function(character)
		local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		if root then
			local _, rootYaw, _ = root.CFrame:ToEulerAnglesYXZ()
			yaw = rootYaw
			pitch = 0
		end
	end)

	RunService:BindToRenderStep("AxiomCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

return CameraController
