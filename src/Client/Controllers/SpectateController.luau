--!strict
--[[
	SpectateController : vue spectateur (section 6.10, écran 13).
	En orbe (ou mort / extrait en duo), la caméra suit le coéquipier vivant.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CameraController = require(script.Parent.CameraController)
local MatchHUDController = require(script.Parent.MatchHUDController)

local SpectateController = {}

local player = Players.LocalPlayer
local yaw = 0

local function teammateRoot(): BasePart?
	local team = player:GetAttribute("TeamId")
	if team == nil then
		return nil
	end
	for _, other in Players:GetPlayers() do
		if other ~= player and other:GetAttribute("TeamId") == team and other.Character then
			local root = other.Character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				return root
			end
		end
	end
	return nil
end

local function spectating(): boolean
	local status = MatchHUDController.status()
	return (status == "orb" or status == "dead" or status == "extracted") and player.Character == nil
end

function SpectateController.init() end

function SpectateController.start()
	RunService:BindToRenderStep("AxiomSpectate", Enum.RenderPriority.Camera.Value + 2, function(dt: number)
		if not spectating() then
			CameraController.setEnabled(true)
			return
		end
		local root = teammateRoot()
		if root == nil then
			return
		end
		CameraController.setEnabled(false)
		local camera = Workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		yaw += dt * 0.15 -- lente rotation autour du coéquipier
		local focus = root.Position + Vector3.new(0, 2, 0)
		local offset = CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-20), 0, 0) * Vector3.new(0, 0, 14)
		camera.CFrame = CFrame.lookAt(focus + offset, focus)
	end)
end

return SpectateController
