--!strict
--[[
	MovementController : sprint et postures (section 5.2).

	- Sprint : Maj maintenue (PC), clic du stick gauche (manette, bascule),
	  joystick poussé au maximum ou bouton (mobile).
	- Accroupi / couché : appui court = accroupi, appui long = couché.
	- Le client applique immédiatement la vitesse (prédiction) et envoie
	  son intention au serveur, qui fait autorité (vitesse, saut, contrôle
	  anti-triche des déplacements).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Movement = require(Shared.Combat.Movement)
local Signal = require(Shared.Util.Signal)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local CameraController = require(script.Parent.CameraController)
local InputController = require(script.Parent.InputController)

local M = Config.Combat.movement
local CameraConfig = Config.Combat.camera

local MovementController = {}

MovementController.Changed = Signal.new() :: Signal.Signal<Movement.Stance, boolean>

local player = Players.LocalPlayer

local stance: Movement.Stance = "stand"
local sprintWanted = false
local sprintToggled = false -- manette / mobile : sprint en bascule
local crouchPressedAt: number? = nil
local sentStance: Movement.Stance = "stand"
local sentSprint = false
local controls: any = nil

local function character(): (Model?, Humanoid?)
	local char = player.Character
	local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
	return char, humanoid
end

local function moveVector(): Vector3
	if controls then
		local ok, vector = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(vector) == "Vector3" then
			return vector
		end
	end
	local _, humanoid = character()
	return if humanoid then humanoid.MoveDirection else Vector3.zero
end

local function localMoveState(): Movement.MoveState
	local char = player.Character
	return {
		stance = stance,
		sprinting = sentSprint,
		parrying = char ~= nil and char:GetAttribute("Parrying") == true,
		stunned = char ~= nil and char:GetAttribute("Stunned") == true,
		speedMultiplier = 1,
		usingConsumable = nil,
	}
end

-- Applique localement vitesse, saut et caméra (prédiction), puis informe le serveur.
local function apply()
	local _, humanoid = character()
	local moving = moveVector().Magnitude > 0.1
	local sprinting = sprintWanted and moving and stance == "stand"
	if humanoid then
		local state = localMoveState()
		state.sprinting = sprinting
		humanoid.WalkSpeed = Movement.walkSpeed(state)
		humanoid.JumpHeight = Movement.jumpHeight(state)
	end
	CameraController.setStanceOffset(
		if stance == "crouch"
			then CameraConfig.crouchOffsetY
			elseif stance == "prone" then CameraConfig.proneOffsetY
			else 0
	)
	if stance ~= sentStance or sprinting ~= sentSprint then
		sentStance = stance
		sentSprint = sprinting
		ClientNet.fire("SetMovement", stance, sprinting, Workspace:GetServerTimeNow())
		MovementController.Changed:Fire(stance, sprinting)
	end
end

function MovementController.stance(): Movement.Stance
	return stance
end

function MovementController.isSprinting(): boolean
	return sentSprint
end

function MovementController.isMoving(): boolean
	return moveVector().Magnitude > 0.1
end

-- Le personnage est-il en l'air (saut, chute) ?
function MovementController.isAirborne(): boolean
	local _, humanoid = character()
	if humanoid == nil then
		return false
	end
	local state = humanoid:GetState()
	return humanoid.FloorMaterial == Enum.Material.Air
		or state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Freefall
end

-- Arrête le sprint (le tir et la garde l'interrompent).
function MovementController.stopSprint()
	sprintWanted = false
	sprintToggled = false
	apply()
end

function MovementController.setStance(newStance: Movement.Stance)
	if newStance ~= stance then
		stance = newStance
		if stance ~= "stand" then
			sprintWanted = false
			sprintToggled = false
		end
		apply()
	end
end

function MovementController.reset()
	stance = "stand"
	sprintWanted = false
	sprintToggled = false
	sentStance = "stand"
	sentSprint = false
	crouchPressedAt = nil
	CameraController.setStanceOffset(0)
end

function MovementController.init() end

function MovementController.start()
	-- Repoussement (Gantelet à impulsion) : le client simule son personnage,
	-- c'est donc lui qui applique l'impulsion décidée par le serveur.
	ClientNet.on("Knockback", function(velocity: Vector3)
		local model = player.Character
		local root = if model then model:FindFirstChild("HumanoidRootPart") else nil
		if typeof(velocity) == "Vector3" and root and root:IsA("BasePart") then
			root.AssemblyLinearVelocity = velocity
		end
	end)

	task.spawn(function()
		local playerModule = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
		if playerModule then
			local ok, module = pcall(require, playerModule)
			if ok then
				controls = (module :: any):GetControls()
			end
		end
	end)

	InputController.ActionBegan:Connect(function(action)
		if action == "sprint" then
			if InputController.device() == "keyboard" then
				sprintWanted = true
			else
				sprintToggled = not sprintToggled
				sprintWanted = sprintToggled
			end
			if stance ~= "stand" then
				MovementController.setStance("stand")
			end
			apply()
		elseif action == "crouch" then
			local pressedAt = os.clock()
			crouchPressedAt = pressedAt
			-- Appui long : couché (bascule).
			task.delay(M.proneHoldThreshold, function()
				if crouchPressedAt == pressedAt and InputController.isHeld("crouch") then
					crouchPressedAt = nil
					MovementController.setStance(if stance == "prone" then "stand" else "prone")
				end
			end)
		end
	end)

	InputController.ActionEnded:Connect(function(action)
		if action == "sprint" and InputController.device() == "keyboard" then
			sprintWanted = false
			apply()
		elseif action == "crouch" and crouchPressedAt ~= nil then
			-- Appui court : accroupi (bascule).
			crouchPressedAt = nil
			MovementController.setStance(if stance == "crouch" then "stand" else "crouch")
		end
	end)

	player.CharacterAdded:Connect(function()
		MovementController.reset()
		task.defer(apply)
	end)

	-- Mobile : joystick poussé au maximum = sprint ; arrêt du mouvement = fin du sprint.
	RunService.Heartbeat:Connect(function()
		local vector = moveVector()
		if InputController.device() == "touch" and stance == "stand" and not sprintToggled then
			sprintWanted = vector.Magnitude >= 0.95
		elseif vector.Magnitude < 0.1 and sprintToggled then
			sprintToggled = false
			sprintWanted = false
		end
		apply()
	end)
end

return MovementController
