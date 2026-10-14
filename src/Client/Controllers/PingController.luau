--!strict
--[[
	PingController : pings contextuels (section 16.5), indispensables sur mobile.

	Appui court : ping selon ce qui est visé (ennemi → « Ennemi ici »,
	conteneur → « Loot ici », sinon « Je vais là » ; « Besoin de soins » si
	les PV sont bas). Appui long : « Danger ».

	Repère de carte : posé en cliquant sur la carte (MapController). Il reste
	affiché plus longtemps, avec sa distance, et disparaît quand on l'atteint.
	Un seul repère par joueur : en poser un autre remplace le précédent.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Signal = require(Shared.Util.Signal)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
local Theme = require(script.Parent.Parent.UI.Theme)
local CameraController = require(script.Parent.CameraController)
local InputController = require(script.Parent.InputController)
local ProfileController = require(script.Parent.ProfileController)

local PingController = {}

export type Ping = {
	userId: number,
	senderName: string,
	position: Vector3,
	kind: string,
	waypoint: boolean,
	expiresAt: number,
	anchor: Part,
	label: TextLabel,
}

-- La liste des pings affichés a changé (la carte les redessine).
PingController.Changed = Signal.new() :: Signal.Signal<>

local pings: { Ping } = {}

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

function PingController.color(kind: string): Color3
	return COLORS[kind] or Theme.cyan
end

function PingController.icon(kind: string): string
	return ICONS[kind] or "▲"
end

-- Pings actuellement affichés (lecture seule).
function PingController.active(): { Ping }
	return pings
end

local function remove(ping: Ping)
	local index = table.find(pings, ping)
	if index then
		table.remove(pings, index)
	end
	ping.anchor:Destroy()
end

local function caption(ping: Ping, distance: number?): string
	local text = ProfileController.t(if ping.waypoint then "ping.waypoint" else "ping." .. ping.kind)
	if distance then
		text ..= `  ·  {math.floor(distance)} m`
	end
	return text .. "\n" .. ping.senderName
end

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

local function show(userId: number, senderName: string, position: Vector3, kind: string, waypoint: boolean)
	-- Un seul repère de carte par joueur.
	if waypoint then
		for _, existing in table.clone(pings) do
			if existing.waypoint and existing.userId == userId then
				remove(existing)
			end
		end
	end
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
	local color = PingController.color(kind)
	local label = Create("TextLabel", {
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		Font = Theme.fontText,
		TextSize = 13,
		TextColor3 = color,
		TextStrokeTransparency = 0.4,
		Text = "",
	})
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
			Text = if waypoint then "▼" else PingController.icon(kind),
		}),
		Label = label,
	})
	local ping: Ping = {
		userId = userId,
		senderName = senderName,
		position = position,
		kind = kind,
		waypoint = waypoint,
		expiresAt = os.clock() + (if waypoint then P.waypointLifetime else P.lifetime),
		anchor = anchor,
		label = label,
	}
	label.Text = caption(ping, nil)
	table.insert(pings, ping)
	PingController.Changed:Fire()
end

-- Repère posé depuis la carte (le serveur vérifie qu'il est bien sur la carte).
function PingController.sendFromMap(position: Vector3)
	ClientNet.fire("Ping", position, "go", true)
end

-- Retire les repères de carte (clic droit sur la carte). Local : chacun gère les siens.
function PingController.clearWaypoints()
	local changed = false
	for _, ping in table.clone(pings) do
		if ping.waypoint then
			remove(ping)
			changed = true
		end
	end
	if changed then
		PingController.Changed:Fire()
	end
end

-- Expiration, distance des repères de carte, repère atteint.
local function sweep()
	local time = os.clock()
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local origin = if root and root:IsA("BasePart") then root.Position else nil
	local changed = false
	local state = ReplicatedStorage:FindFirstChild("MatchState")
	local running = state ~= nil and state:GetAttribute("Running") == true
	for _, ping in table.clone(pings) do
		local distance = if origin then (ping.position - origin).Magnitude else nil
		local reached = distance ~= nil and distance <= P.waypointReach
		if time >= ping.expiresAt or (ping.waypoint and (reached or not running)) then
			remove(ping)
			changed = true
		elseif ping.waypoint then
			ping.label.Text = caption(ping, distance)
		end
	end
	if changed then
		PingController.Changed:Fire()
	end
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
	ClientNet.on(
		"PingShown",
		function(userId: number, senderName: string, position: Vector3, kind: string, waypoint: boolean?)
			if typeof(position) == "Vector3" and type(kind) == "string" and type(senderName) == "string" then
				show(tonumber(userId) or 0, senderName, position, kind, waypoint == true)
			end
		end
	)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.25 then
			accumulator = 0
			if #pings > 0 then
				sweep()
			end
		end
	end)
end

return PingController
