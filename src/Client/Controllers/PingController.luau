--!strict
--[[
	PingController : pings contextuels (section 16.5), indispensables sur mobile.

	Appui court : ping selon ce qui est visé (ennemi → « Ennemi ici »,
	conteneur → « Loot ici », sinon « Je vais là » ; « Besoin de soins » si
	les PV sont bas). Appui long : « Danger ».
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
local Theme = require(script.Parent.Parent.UI.Theme)
local CameraController = require(script.Parent.CameraController)
local InputController = require(script.Parent.InputController)
local ProfileController = require(script.Parent.ProfileController)

local PingController = {}

local player = Players.LocalPlayer
local P = Config.Match.ping

local COLORS: { [string]: Color3 } = {
	enemy = Theme.red,
	loot = Theme.orange,
	go = Theme.cyan,
	danger = Theme.red,
	heal = Theme.green,
}
local ICONS: { [string]: string } = { enemy = "✖", loot = "◆", go = "▲", danger = "!", heal = "+" }

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local function aimed(): (Vector3?, Instance?)
	local ray = CameraController.centerRay()
	local exclude: { Instance } = {}
	if player.Character then
		table.insert(exclude, player.Character)
	end
	params.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * P.maxDistance, params)
	if hit then
		return hit.Position, hit.Instance
	end
	return nil, nil
end

local function contextualKind(target: Instance?): string
	if target then
		local model = target:FindFirstAncestorOfClass("Model")
		while model do
			if CollectionService:HasTag(model, "Fighter") then
				local team = player:GetAttribute("TeamId")
				local owner = Players:GetPlayerFromCharacter(model)
				if owner == nil or team == nil or owner:GetAttribute("TeamId") ~= team then
					return "enemy"
				end
				break
			end
			if model:GetAttribute("ContainerId") then
				return "loot"
			end
			model = model:FindFirstAncestorOfClass("Model")
		end
	end
	local character = player.Character
	local health = if character then character:GetAttribute("Health") else nil
	if type(health) == "number" and health <= P.lowHealthForHealPing then
		return "heal"
	end
	return "go"
end

local function send(kind: string?)
	local position, target = aimed()
	if position == nil then
		return
	end
	ClientNet.fire("Ping", position, kind or contextualKind(target))
end

local function show(senderName: string, position: Vector3, kind: string)
	local anchor = Instance.new("Part")
	anchor.Name = "Ping"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position + Vector3.new(0, 2, 0)
	anchor.Parent = Workspace
	local color = COLORS[kind] or Theme.cyan
	Create("BillboardGui", {
		Size = UDim2.fromOffset(180, 60),
		AlwaysOnTop = true,
		Adornee = anchor,
		Parent = anchor,
	}, {
		Icon = Create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundTransparency = 1,
			Font = Theme.fontTitle,
			TextSize = 26,
			TextColor3 = color,
			TextStrokeTransparency = 0.3,
			Text = ICONS[kind] or "▲",
		}),
		Label = Create("TextLabel", {
			Position = UDim2.fromOffset(0, 28),
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			Font = Theme.fontText,
			TextSize = 13,
			TextColor3 = color,
			TextStrokeTransparency = 0.4,
			Text = ProfileController.t("ping." .. kind) .. "\n" .. senderName,
		}),
	})
	Debris:AddItem(anchor, P.lifetime)
end

function PingController.init() end

function PingController.start()
	InputController.Tapped:Connect(function(action)
		if action == "ping" then
			send(nil)
		end
	end)
	InputController.HeldLong:Connect(function(action)
		if action == "ping" then
			send("danger")
		end
	end)
	ClientNet.on("PingShown", function(_userId: number, senderName: string, position: Vector3, kind: string)
		if typeof(position) == "Vector3" and type(kind) == "string" and type(senderName) == "string" then
			show(senderName, position, kind)
		end
	end)
end

return PingController
