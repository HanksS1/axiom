--!strict
--[[
	GadgetController : utilisation des gadgets (section 8.5) côté client.

	- E / A (Q en QWERTY), croix gauche / droite, boutons G1 / G2 sur mobile :
	  appui court (un appui long sur E sert à interagir avec les invites).
	- Après validation serveur : saut propulsé, traction du grappin.
	- Affichage : recharges et utilisations restantes ; cibles révélées par
	  un drone (contour rouge à travers les murs).
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
local PanelState = require(script.Parent.Parent.UI.PanelState)
local Theme = require(script.Parent.Parent.UI.Theme)
local CameraController = require(script.Parent.CameraController)
local HUDController = require(script.Parent.HUDController)
local InputController = require(script.Parent.InputController)
local InventoryController = require(script.Parent.InventoryController)
local ProfileController = require(script.Parent.ProfileController)

local GadgetController = {}

local player = Players.LocalPlayer
local G = Config.Match.gadgets
local t = ProfileController.t

type SlotState = { uid: string, usesLeft: number?, cooldownUntil: number }
local slotStates: { [string]: SlotState } = {}
local promptsShown = 0
local labels: { [string]: TextLabel } = {}
local revealed: { [Model]: Highlight } = {}

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local function aimPoint(maxDistance: number): Vector3?
	local ray = CameraController.centerRay()
	params.FilterDescendantsInstances = if player.Character then { player.Character } else {}
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * maxDistance, params)
	return if hit then hit.Position else nil
end

local function use(slot: string)
	if PanelState.anyOpen() then
		return
	end
	local item = InventoryController.state().equipped[slot]
	if item == nil then
		return
	end
	local target = aimPoint(80)
	ClientNet.fire("UseGadget", slot, target)
end

local function rope(from: BasePart, to: Vector3, duration: number)
	local line = Instance.new("Part")
	line.Name = "GrappleRope"
	line.Anchored = true
	line.CanCollide = false
	line.CanQuery = false
	line.CanTouch = false
	line.Material = Enum.Material.Neon
	line.Color = Theme.cyan
	line.Parent = Workspace
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		if os.clock() - started > duration or from.Parent == nil then
			connection:Disconnect()
			line:Destroy()
			return
		end
		local start = from.Position
		local length = (to - start).Magnitude
		line.Size = Vector3.new(0.12, 0.12, length)
		line.CFrame = CFrame.lookAt(start, to) * CFrame.new(0, 0, -length / 2)
	end)
end

local function grapple(target: Vector3)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if root == nil then
		return
	end
	rope(root, target, G.grappleMaxTime)
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local offset = target - root.Position
		if os.clock() - started > G.grappleMaxTime or offset.Magnitude < 4 or root.Parent == nil then
			connection:Disconnect()
			return
		end
		root.AssemblyLinearVelocity = offset.Unit * G.grappleSpeed
	end)
end

local function render()
	local now = Workspace:GetServerTimeNow()
	local equipped = InventoryController.state().equipped
	for _, slot in { "gadget1", "gadget2" } do
		local label = labels[slot]
		local item = equipped[slot]
		label.Visible = item ~= nil
		if item then
			local state = slotStates[slot]
			local status = t("hud.gadgetReady")
			if state and state.uid == item.uid then
				if now < state.cooldownUntil then
					status = string.format("%d s", math.ceil(state.cooldownUntil - now))
				elseif state.usesLeft then
					status = t("hud.gadgetUses", { uses = state.usesLeft })
				end
			else
				local def = Config.Equipment.gadgets[item.itemId]
				if def and def.usesPerMatch then
					status = t("hud.gadgetUses", { uses = def.usesPerMatch })
				end
			end
			label.Text = t("item." .. item.itemId) .. "\n" .. status
		end
	end
end

function GadgetController.init() end

function GadgetController.start()
	local row = Create("Frame", {
		Name = "Gadgets",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, -300, 1, -16),
		Size = UDim2.fromOffset(250, 46),
		BackgroundTransparency = 1,
		Parent = HUDController.root(),
	}, {
		Layout = Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
		}),
	})
	for index, slot in { "gadget1", "gadget2" } do
		labels[slot] = Create("TextLabel", {
			LayoutOrder = index,
			Size = UDim2.fromOffset(120, 46),
			BackgroundColor3 = Theme.panel,
			BackgroundTransparency = Theme.panelTransparency,
			Font = Theme.fontText,
			TextSize = 12,
			TextColor3 = Theme.text,
			TextWrapped = true,
			Visible = false,
			Text = "",
			Parent = row,
		})
	end

	ProximityPromptService.PromptShown:Connect(function()
		promptsShown += 1
	end)
	ProximityPromptService.PromptHidden:Connect(function()
		promptsShown = math.max(0, promptsShown - 1)
	end)

	InputController.Tapped:Connect(function(action)
		if action == "gadget1" then
			-- E sert aussi aux invites : pas de gadget quand une invite est affichée.
			if promptsShown > 0 and InputController.device() == "keyboard" then
				return
			end
			use("gadget1")
		elseif action == "gadget2" then
			use("gadget2")
		end
	end)

	ClientNet.on("GadgetState", function(slot: string, uid: string, usesLeft: number?, cooldownUntil: number)
		if (slot == "gadget1" or slot == "gadget2") and type(uid) == "string" then
			slotStates[slot] = { uid = uid, usesLeft = usesLeft, cooldownUntil = tonumber(cooldownUntil) or 0 }
		end
	end)

	ClientNet.on("GadgetEffect", function(kind: string, value: any)
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		if root == nil then
			return
		end
		if kind == "jump" and type(value) == "number" then
			local velocity = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(velocity.X, value, velocity.Z)
		elseif kind == "grapple" and typeof(value) == "Vector3" then
			grapple(value)
		end
	end)

	ClientNet.on("GadgetVisual", function(other: Player?, kind: string, value: any)
		if kind == "grapple" and other and other.Character and typeof(value) == "Vector3" then
			local root = other.Character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				rope(root, value, 0.8)
			end
		end
	end)

	-- Drone de reconnaissance : contour rouge visible à travers les murs.
	ClientNet.on("Reveal", function(characters: { Model }, duration: number)
		if type(characters) ~= "table" then
			return
		end
		local expires = os.clock() + (tonumber(duration) or 0.7)
		for _, model in characters do
			if typeof(model) == "Instance" and model:IsA("Model") then
				local highlight = revealed[model]
				if highlight == nil or highlight.Parent == nil then
					local newHighlight = Instance.new("Highlight")
					newHighlight.FillTransparency = 0.8
					newHighlight.FillColor = Theme.red
					newHighlight.OutlineColor = Theme.red
					newHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					newHighlight.Parent = model
					revealed[model] = newHighlight
					highlight = newHighlight
				end
				(highlight :: Highlight):SetAttribute("Expires", expires)
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		render()
		local clock = os.clock()
		for model, highlight in revealed do
			local expires = highlight:GetAttribute("Expires")
			if highlight.Parent == nil or type(expires) ~= "number" or clock > expires then
				highlight:Destroy()
				revealed[model] = nil
			end
		end
	end)
end

return GadgetController
