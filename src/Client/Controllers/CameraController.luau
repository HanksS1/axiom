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

local CollectionService = game:GetService("CollectionService")
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
local AimAssist = Config.Combat.aimAssist

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
-- Lunette de l'arme en main (nil : aucune) et progression du passage à la première
-- personne (0 : vue à l'épaule, 1 : dans la lunette).
local scope: { fieldOfView: number, spreadMultiplier: number }? = nil
local scopeProgress = 0
local hiddenForScope = false

-- Sensibilité réduite à proportion du zoom (une lunette ×3 tourne 3 fois moins vite).
local function zoomFactor(): number
	return math.clamp(currentFov / CameraConfig.fieldOfView, 0.15, 1)
end
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

-- Visée assistée : cible sous le réticule (point visé) et dernière entrée de visée.
local assistPoint: Vector3? = nil
local assistRefreshAt = 0
local lastLookInputAt = 0
local findAssistTarget: (character: Model) -> Vector3?
local assistParams = RaycastParams.new()
assistParams.FilterType = Enum.RaycastFilterType.Exclude

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

-- Visée assistée active (manette / mobile, paramètre activé ; jamais à la souris).
local function assistStrength(): number
	if InputController.device() == "keyboard" then
		return 0
	end
	local view = ProfileController.get()
	if view == nil or view.settings.aimAssist == false then
		return 0
	end
	return setting("aimAssistStrength", 0.5)
end

-- Ralentissement de la rotation quand une cible est sous le réticule.
local function assistSlowdown(): number
	if assistPoint == nil then
		return 1
	end
	return 1 - AimAssist.slowdown * assistStrength()
end

function CameraController.addTouchDelta(delta: Vector2)
	lastLookInputAt = os.clock()
	local factor = TOUCH_FACTOR
		* setting("touchSensitivity", 1)
		* (if aiming then 0.6 else 1)
		* (if scopeProgress > 0 then zoomFactor() else 1)
		* assistSlowdown()
	CameraController.addLookDelta(delta.X * factor, delta.Y * factor)
end

function CameraController.setAiming(value: boolean)
	aiming = value
end

function CameraController.isAiming(): boolean
	return aiming
end

-- Lunette de l'arme en main (WeaponController la renseigne à chaque image).
function CameraController.setScope(value: { fieldOfView: number, spreadMultiplier: number }?)
	scope = value
end

-- 0 : vue normale ; 1 : complètement dans la lunette (première personne, zoom).
function CameraController.scopeProgress(): number
	return scopeProgress
end

-- Première personne dans la lunette : le personnage (et son arme) ne doit pas boucher la vue.
local function hideCharacter(hidden: boolean)
	if hidden == hiddenForScope then
		return
	end
	hiddenForScope = hidden
	local character = player.Character
	if character == nil then
		return
	end
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			descendant.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
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

-- Cible la plus proche du centre de l'écran (cône étroit, ligne de vue dégagée).
findAssistTarget = function(character: Model): Vector3?
	local origin = camera.CFrame.Position
	local look = camera.CFrame.LookVector
	local myTeam = player:GetAttribute("TeamId")
	local cosCone = math.cos(math.rad(AimAssist.cone))
	local best: Vector3?, bestDot, bestModel = nil, cosCone, nil :: Model?
	for _, model in CollectionService:GetTagged("Fighter") do
		if model == character or not model:IsA("Model") then
			continue
		end
		if model:GetAttribute("FighterKind") == "object" or model:GetAttribute("Dead") == true then
			continue
		end
		if model:GetAttribute("Hidden") == true then
			continue
		end
		local owner = Players:GetPlayerFromCharacter(model)
		if owner and myTeam ~= nil and owner:GetAttribute("TeamId") == myTeam then
			continue
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		if root == nil or not root:IsA("BasePart") then
			continue
		end
		local point = root.Position + Vector3.new(0, 0.8, 0)
		local offset = point - origin
		local distance = offset.Magnitude
		if distance > AimAssist.range or distance < 1 then
			continue
		end
		local dot = look:Dot(offset / distance)
		if dot > bestDot then
			best, bestDot, bestModel = point, dot, model
		end
	end
	if best and bestModel then
		assistParams.FilterDescendantsInstances = { character, bestModel }
		if Workspace:Raycast(origin, best - origin, assistParams) then
			return nil
		end
	end
	return best
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
		lastLookInputAt = os.clock()
		local sensitivity = setting("gamepadSensitivity", 1)
			* (if aiming then 0.55 else 1)
			* (if scopeProgress > 0 then zoomFactor() else 1)
			* assistSlowdown()
		local stick = gamepadLook * gamepadLook.Magnitude -- courbe quadratique (précision)
		CameraController.addLookDelta(
			stick.X * GAMEPAD_RATE * sensitivity * dt,
			-stick.Y * GAMEPAD_RATE * sensitivity * dt
		)
	end

	-- Transitions douces (visée, posture).
	local alpha = math.clamp(dt / CameraConfig.transitionTime, 0, 1)
	-- Lunette : en visant avec une arme à lunette, passage progressif à la première personne.
	local scoped = aiming and scope ~= nil
	local step = dt / CameraConfig.scopeTransitionTime
	scopeProgress = math.clamp(scopeProgress + (if scoped then step else -step), 0, 1)
	local s = scopeProgress * scopeProgress * (3 - 2 * scopeProgress) -- départ et arrivée en douceur
	local targetOffset = if aiming then CameraConfig.aimShoulderOffset else CameraConfig.shoulderOffset
	currentOffset = currentOffset:Lerp(targetOffset:Lerp(Vector3.zero, s), alpha)
	local aimDistance = lerp(CameraConfig.aimDistance, 0, s)
	currentDistance = lerp(currentDistance, if aiming then aimDistance else CameraConfig.distance, alpha)
	local scopeFov = if scope then scope.fieldOfView else CameraConfig.aimFieldOfView
	local aimFov = lerp(CameraConfig.aimFieldOfView, scopeFov, s)
	currentFov = lerp(currentFov, if aiming then aimFov else CameraConfig.fieldOfView, alpha)
	currentStanceY = lerp(currentStanceY, stanceOffsetY, alpha)
	camera.FieldOfView = currentFov
	hideCharacter(scopeProgress > 0.7)

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

	-- Visée assistée : légère adhérence vers la cible pendant que le joueur vise.
	local strength = assistStrength()
	if strength > 0 then
		local clock2 = os.clock()
		if clock2 >= assistRefreshAt then
			assistRefreshAt = clock2 + AimAssist.refresh
			assistPoint = findAssistTarget(character :: Model)
		end
		local point = assistPoint
		if point and clock2 - lastLookInputAt < 0.3 then
			local direction = (point - camera.CFrame.Position).Unit
			local targetYaw = math.atan2(-direction.X, -direction.Z)
			local targetPitch = math.asin(math.clamp(direction.Y, -1, 1))
			local maxStep = math.rad(AimAssist.pull) * strength * dt
			local yawDiff = (targetYaw - yaw + math.pi) % (2 * math.pi) - math.pi
			yaw += math.clamp(yawDiff, -maxStep, maxStep)
			pitch = math.clamp(pitch + math.clamp(targetPitch - pitch, -maxStep, maxStep), -MAX_PITCH, MAX_PITCH)
		end
	else
		assistPoint = nil
	end

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
				local factor = MOUSE_FACTOR
					* setting("mouseSensitivity", 1)
					* (if aiming then 0.6 else 1)
					* (if scopeProgress > 0 then zoomFactor() else 1)
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
		hiddenForScope = false
		scopeProgress = 0
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
