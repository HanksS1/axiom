--!strict
--[[
	MapEffectsController : effets des cartes côté client (section 12).

	- Nom de la carte et de son Gardien au déploiement.
	- Grondements, effondrements, Gardien qui surgit : tremblement de caméra
	  selon la distance.
	- Coupures de courant (Noyau Zéro) : tout devient sombre, sauf les lampes
	  des armes, les yeux des robots et les néons de secours.
	- Radiation (Terres Brûlées) : voile vert et alerte tant que le joueur est
	  dans une zone irradiée.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
local Theme = require(script.Parent.Parent.UI.Theme)
local CameraController = require(script.Parent.CameraController)
local HUDController = require(script.Parent.HUDController)
local NotificationController = require(script.Parent.NotificationController)
local ProfileController = require(script.Parent.ProfileController)

local MapEffectsController = {}

local player = Players.LocalPlayer
local t = ProfileController.t

-- Tremblements : (intensité en degrés, durée, rayon d'effet en studs).
local SHAKES: { [string]: { intensity: number, duration: number, radius: number } } = {
	rumble = { intensity = 0.6, duration = 4, radius = 500 },
	collapse = { intensity = 1.6, duration = 1.6, radius = 260 },
	surface = { intensity = 1.2, duration = 0.8, radius = 60 },
}

local DARK = {
	Brightness = 0,
	Ambient = Color3.fromRGB(6, 6, 10),
	OutdoorAmbient = Color3.fromRGB(8, 8, 14),
	ExposureCompensation = -0.6,
}

local blackout = false
local saved: { [string]: any }? = nil
local lights: { [Instance]: Instance } = {}
local radiationFrame: Frame
local radiationLabel: TextLabel

local function onMapEvent(kind: string, position: Vector3)
	local shake = SHAKES[kind]
	if shake == nil or typeof(position) ~= "Vector3" then
		return
	end
	local distance = (Workspace.CurrentCamera.CFrame.Position - position).Magnitude
	if distance > shake.radius then
		return
	end
	local scale = math.clamp(1 - distance / shake.radius, 0.25, 1)
	CameraController.shake(shake.intensity * scale, shake.duration)
end

-- Coupures de courant -------------------------------------------------------------

-- Lampe d'arme (personnages) ou lueur des yeux (robots), créée localement.
local function addLight(parent: BasePart, kind: "weapon" | "eye")
	if lights[parent] then
		return
	end
	local light: Instance
	if kind == "weapon" then
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Angle = 50
		spot.Range = 40
		spot.Brightness = 3
		spot.Color = Color3.fromRGB(230, 240, 255)
		light = spot
	else
		local point = Instance.new("PointLight")
		point.Range = 10
		point.Brightness = 2
		point.Color = Color3.fromRGB(255, 40, 40)
		light = point
	end
	light.Name = "BlackoutLight"
	light.Parent = parent
	lights[parent] = light
end

local function refreshLights()
	for _, model in CollectionService:GetTagged("Fighter") do
		if model:IsA("Model") then
			local visual = model:FindFirstChild("WeaponVisual")
			local body = if visual then visual:FindFirstChild("Body") else nil
			if body and body:IsA("BasePart") then
				addLight(body, "weapon")
			end
			local eye = model:FindFirstChild("Eye")
			if eye and eye:IsA("BasePart") then
				addLight(eye, "eye")
			end
		end
	end
	for parent, light in lights do
		if parent.Parent == nil then
			light:Destroy()
			lights[parent] = nil
		end
	end
end

local function setBlackout(on: boolean)
	if on == blackout then
		return
	end
	blackout = on
	local info = TweenInfo.new(if on then 0.4 else 1.5)
	if on then
		saved = {
			Brightness = Lighting.Brightness,
			Ambient = Lighting.Ambient,
			OutdoorAmbient = Lighting.OutdoorAmbient,
			ExposureCompensation = Lighting.ExposureCompensation,
		}
		TweenService:Create(Lighting, info, DARK):Play()
		refreshLights()
	else
		if saved then
			TweenService:Create(Lighting, info, saved :: any):Play()
			saved = nil
		end
		for _, light in lights do
			light:Destroy()
		end
		table.clear(lights)
	end
end

local function watchMap(map: Instance)
	if map.Name ~= "Map" then
		return
	end
	map:GetAttributeChangedSignal("Blackout"):Connect(function()
		setBlackout(map:GetAttribute("Blackout") == true)
	end)
	map.Destroying:Connect(function()
		setBlackout(false)
	end)
	setBlackout(map:GetAttribute("Blackout") == true)
end

-- Radiation ----------------------------------------------------------------------

local function buildRadiation(root: Instance)
	radiationLabel = Create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 110),
		Size = UDim2.fromOffset(300, 30),
		BackgroundTransparency = 1,
		Font = Theme.fontTitle,
		TextSize = 22,
		TextColor3 = Color3.fromRGB(120, 255, 90),
		TextStrokeTransparency = 0.4,
		Text = "",
	})
	radiationFrame = Create("Frame", {
		Name = "Radiation",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(60, 200, 40),
		BackgroundTransparency = 0.88,
		Visible = false,
		ZIndex = 0,
		Parent = root,
	}, { Label = radiationLabel })
end

local function watchCharacter(character: Model)
	local function refresh()
		local on = character:GetAttribute("Irradiated") == true
		radiationFrame.Visible = on
		radiationLabel.Text = t("map.radiation")
	end
	character:GetAttributeChangedSignal("Irradiated"):Connect(refresh)
	refresh()
end

-- Annonce de la carte ------------------------------------------------------------

local function watchMatchState(state: Instance)
	local lastMap: string? = nil
	local function announce()
		local mapId = state:GetAttribute("MapId")
		if state:GetAttribute("Running") ~= true or type(mapId) ~= "string" or mapId == lastMap then
			return
		end
		lastMap = mapId
		local def = (Config.Maps.byId :: any)[mapId]
		if def then
			NotificationController.show(t("map." .. mapId), Theme.cyan)
			NotificationController.show(t("map.guardian", { name = t(def.guardian.nameKey) }), Theme.orange)
		end
	end
	state:GetAttributeChangedSignal("Running"):Connect(function()
		if state:GetAttribute("Running") ~= true then
			lastMap = nil
		end
		announce()
	end)
	state:GetAttributeChangedSignal("MapId"):Connect(announce)
	announce()
end

function MapEffectsController.init() end

function MapEffectsController.start()
	buildRadiation(HUDController.root())
	ClientNet.on("MapEvent", onMapEvent)

	Workspace.ChildAdded:Connect(watchMap)
	local map = Workspace:FindFirstChild("Map")
	if map then
		watchMap(map)
	end

	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end

	task.spawn(function()
		watchMatchState(ReplicatedStorage:WaitForChild("MatchState"))
	end)

	-- Pendant une coupure, les combattants qui apparaissent reçoivent leur lampe.
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		if not blackout then
			return
		end
		accumulator += dt
		if accumulator >= 1 then
			accumulator = 0
			refreshLights()
		end
	end)
end

return MapEffectsController
