--!strict
--[[
	MapController : carte de la partie (touche « carte », M par défaut ; sur
	mobile, toucher le radar).

	- Plan vu de dessus (murs et masses), le nord en haut, décodé une fois à
	  partir du plan calculé par le serveur (Shared/Match/MapPlan).
	- Repères : le joueur (rond blanc et flèche du regard), le coéquipier,
	  les extractions (anneau orange si ouverte, gris sinon), l'Accélérateur
	  quand un coéquipier est en orbe, les zones à risque, les pings.
	- Clic sur la carte : pose un repère (visible par l'équipe, avec sa
	  distance dans le monde). Clic droit : retire les repères.

	La carte est un panneau (souris libérée, tir bloqué) : on peut continuer
	à se déplacer, et elle se ferme avec la même touche.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MapPlan = require(Shared.Match.MapPlan)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
local PanelState = require(script.Parent.Parent.UI.PanelState)
local Theme = require(script.Parent.Parent.UI.Theme)
local HUDController = require(script.Parent.HUDController)
local InputController = require(script.Parent.InputController)
local NotificationController = require(script.Parent.NotificationController)
local PingController = require(script.Parent.PingController)
local ProfileController = require(script.Parent.ProfileController)

local MapController = {}

local player = Players.LocalPlayer
local t = ProfileController.t
local Maps = Config.Maps

local WALL = Color3.fromRGB(52, 96, 118)
local GRID_STEP = 100 -- studs entre deux lignes du quadrillage
local REFRESH = 0.1

local plan: MapPlan.Plan? = nil
local planDrawn = false
local mapId: string? = nil
local revive: { [string]: any }? = nil
local isOpen = false

local panel: Frame
local title: TextLabel
local canvas: TextButton
local planLayer: Frame
local zoneLayer: Frame
local markerLayer: Frame
local legend: TextLabel
local markers: { [string]: Frame } = {}
local seen: { [string]: boolean } = {}

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function matchRunning(): boolean
	local state = ReplicatedStorage:FindFirstChild("MatchState")
	return state ~= nil and state:GetAttribute("Running") == true
end

local function planPoint(position: Vector3): (number, number, boolean)
	return MapPlan.toPlan(position, Maps.origin, Maps.size)
end

-- Plan ------------------------------------------------------------------------------

local function drawPlan()
	planLayer:ClearAllChildren()
	zoneLayer:ClearAllChildren()
	planDrawn = true
	-- Quadrillage discret (une ligne tous les 100 studs).
	local lines = math.floor(Maps.size / GRID_STEP)
	for index = 1, lines - 1 do
		local ratio = index * GRID_STEP / Maps.size
		Create("Frame", {
			Position = UDim2.fromScale(ratio, 0),
			Size = UDim2.new(0, 1, 1, 0),
			BackgroundColor3 = Theme.cyan,
			BackgroundTransparency = 0.93,
			BorderSizePixel = 0,
			Parent = planLayer,
		})
		Create("Frame", {
			Position = UDim2.fromScale(0, ratio),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Theme.cyan,
			BackgroundTransparency = 0.93,
			BorderSizePixel = 0,
			Parent = planLayer,
		})
	end
	local current = plan
	if current then
		local cells = current.cells
		for _, rect in current.rects do
			Create("Frame", {
				Position = UDim2.fromScale(rect.x / cells, rect.z / cells),
				Size = UDim2.fromScale(rect.w / cells, rect.d / cells),
				BackgroundColor3 = WALL,
				BorderSizePixel = 0,
				Parent = planLayer,
			})
		end
	end
	-- Zones à risque : butin de valeur, garnison de robots (« ! » : repaire du Gardien).
	for _, marker in CollectionService:GetTagged("RiskZone") do
		if marker:IsA("BasePart") and marker:IsDescendantOf(Workspace) then
			local u, v, inside = planPoint(marker.Position)
			if inside then
				local radius = marker:GetAttribute("Radius")
				local diameter = math.max(2 * (if type(radius) == "number" then radius else 20), 30) / Maps.size
				local main = marker:GetAttribute("Main") == true
				Create("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(u, v),
					Size = UDim2.fromScale(diameter, diameter),
					BackgroundColor3 = Theme.red,
					BackgroundTransparency = 0.82,
					BorderSizePixel = 0,
					Parent = zoneLayer,
				}, {
					Corner = Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
					Stroke = Create("UIStroke", { Color = Theme.red, Transparency = 0.5 }),
					Mark = Create("TextLabel", {
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Font = Theme.fontTitle,
						TextSize = 14,
						TextColor3 = Theme.red,
						TextTransparency = 0.2,
						Text = if main then "!" else "",
					}),
				})
			end
		end
	end
end

local function setMap(folder: Instance?)
	plan = nil
	planDrawn = false
	mapId = nil
	if folder == nil then
		return
	end
	local id = folder:GetAttribute("MapId")
	mapId = if type(id) == "string" then id else nil
	task.spawn(function()
		local value = folder:WaitForChild("Plan", 15)
		if value and value:IsA("StringValue") and folder:IsDescendantOf(Workspace) then
			plan = MapPlan.decode(value.Value)
			planDrawn = false
			if isOpen then
				drawPlan()
			end
		end
	end)
end

-- Repères ---------------------------------------------------------------------------

-- Repère de la carte, créé au premier usage puis mis à jour (clé stable).
local function marker(key: string, build: () -> Frame): Frame
	seen[key] = true
	local existing = markers[key]
	if existing then
		return existing
	end
	local created = build()
	created.Name = key
	created.Parent = markerLayer
	markers[key] = created
	return created
end

local function caption(parent: Instance, color: Color3): TextLabel
	return Create("TextLabel", {
		Name = "Caption",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 1),
		Size = UDim2.fromOffset(150, 14),
		BackgroundTransparency = 1,
		Font = Theme.fontText,
		TextSize = 11,
		TextColor3 = color,
		TextStrokeTransparency = 0.35,
		Text = "",
		Parent = parent,
	})
end

local function glyph(text: string, color: Color3, size: number): Frame
	local holder = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, {
		Icon = Create("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Theme.fontTitle,
			TextSize = size,
			TextColor3 = color,
			TextStrokeTransparency = 0.3,
			Text = text,
		}),
	})
	caption(holder, color)
	return holder
end

local function setCaption(frame: Frame, text: string)
	local label = frame:FindFirstChild("Caption")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function distanceText(position: Vector3, origin: Vector3?): string
	if origin == nil then
		return ""
	end
	return `{math.floor((position - origin).Magnitude)} m`
end

local function refreshMarkers()
	table.clear(seen)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local origin: Vector3? = if root and root:IsA("BasePart") then root.Position else nil

	-- Extractions : anneau orange (ouverte) ou gris (fermée).
	local extractions = Workspace:FindFirstChild("Extractions")
	if extractions then
		for index, zone in extractions:GetChildren() do
			if zone:IsA("Model") and zone.PrimaryPart then
				local position = zone.PrimaryPart.Position
				local u, v = planPoint(position)
				local open = zone:GetAttribute("Open") == true
				local frame = marker("extraction" .. tostring(zone:GetAttribute("ZoneId") or index), function()
					local ring = Create("Frame", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Size = UDim2.fromOffset(16, 16),
						BackgroundTransparency = 1,
						ZIndex = 2,
					}, {
						Corner = Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
						Stroke = Create("UIStroke", { Color = Theme.orange, Thickness = 3 }),
					})
					caption(ring, Theme.orange)
					return ring
				end)
				frame.Position = UDim2.fromScale(u, v)
				local stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke
				stroke.Color = if open then Theme.orange else Theme.textDim
				stroke.Thickness = if open then 3 else 1.5
				stroke.Transparency = if open then 0 else 0.4
				local nameKey = zone:GetAttribute("NameKey")
				local name = if type(nameKey) == "string" and ProfileController.has(nameKey)
					then t(nameKey)
					else t("extraction.generic")
				local label = frame:FindFirstChild("Caption") :: TextLabel
				label.TextColor3 = if open then Theme.orange else Theme.textDim
				label.Text = if open then `{name}  ·  {distanceText(position, origin)}` else t("map.closed")
			end
		end
	end

	-- Accélérateur : où ramener l'orbe d'un coéquipier.
	local current = revive
	if current and typeof(current.accelerator) == "Vector3" then
		local u, v = planPoint(current.accelerator)
		local frame = marker("accelerator", function()
			return glyph("◆", Theme.cyan, 18)
		end)
		frame.Position = UDim2.fromScale(u, v)
		setCaption(frame, `{t("revive.accelerator")}  ·  {distanceText(current.accelerator, origin)}`)
	end

	-- Pings et repères de carte.
	for index, ping in PingController.active() do
		local u, v, inside = planPoint(ping.position)
		if inside then
			local color = PingController.color(ping.kind)
			local icon = if ping.waypoint then "▼" else PingController.icon(ping.kind)
			local key = `ping{index}{ping.kind}{if ping.waypoint then "w" else ""}`
			local frame = marker(key, function()
				return glyph(icon, color, 16)
			end)
			frame.Position = UDim2.fromScale(u, v)
			local text = if ping.waypoint then t("ping.waypoint") else t("ping." .. ping.kind)
			setCaption(frame, `{text}  ·  {distanceText(ping.position, origin)}`)
		end
	end

	-- Coéquipier (duo).
	local team = player:GetAttribute("TeamId")
	if team ~= nil then
		for _, other in Players:GetPlayers() do
			if other ~= player and other:GetAttribute("TeamId") == team and other.Character then
				local mateRoot = other.Character:FindFirstChild("HumanoidRootPart")
				if mateRoot and mateRoot:IsA("BasePart") then
					local u, v = planPoint(mateRoot.Position)
					local frame = marker("mate" .. other.UserId, function()
						local dot = Create("Frame", {
							AnchorPoint = Vector2.new(0.5, 0.5),
							Size = UDim2.fromOffset(10, 10),
							BackgroundColor3 = Theme.cyan,
							BorderSizePixel = 0,
							ZIndex = 4,
						}, { Corner = Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
						caption(dot, Theme.cyan)
						return dot
					end)
					frame.Position = UDim2.fromScale(u, v)
					setCaption(frame, other.DisplayName)
				end
			end
		end
	end

	-- Le joueur : rond blanc, flèche dans la direction du regard.
	if origin then
		local u, v = planPoint(origin)
		local frame = marker("me", function()
			return Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(12, 12),
				BackgroundColor3 = Theme.text,
				BorderSizePixel = 0,
				ZIndex = 6,
			}, {
				Corner = Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
				Stroke = Create("UIStroke", { Color = Theme.cyan, Thickness = 2 }),
				Arrow = Create("TextLabel", {
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 0, -1),
					Size = UDim2.fromOffset(14, 12),
					BackgroundTransparency = 1,
					Font = Theme.fontTitle,
					TextSize = 12,
					TextColor3 = Theme.cyan,
					TextStrokeTransparency = 0.4,
					Text = "▲",
					ZIndex = 6,
				}),
			})
		end)
		local look = Workspace.CurrentCamera.CFrame.LookVector
		frame.Position = UDim2.fromScale(math.clamp(u, 0, 1), math.clamp(v, 0, 1))
		frame.Rotation = math.deg(math.atan2(look.X, -look.Z))
	end

	for key, frame in markers do
		if not seen[key] then
			frame:Destroy()
			markers[key] = nil
		end
	end
end

-- Ouverture / fermeture -------------------------------------------------------------

local function fit()
	local viewport = Workspace.CurrentCamera.ViewportSize
	local side = math.floor(math.clamp(math.min(viewport.X - 32, viewport.Y - 150), 220, 680))
	panel.Size = UDim2.fromOffset(side + 24, side + 84)
	canvas.Size = UDim2.fromOffset(side, side)
end

local function refreshTexts()
	local id = mapId
	local name = if id and ProfileController.has("map." .. id) then t("map." .. id) else nil
	title.Text = if name then `{t("map.title")}  ·  {name}` else t("map.title")
	legend.Text = if InputController.device() == "keyboard" then t("map.legend") else t("map.legendTouch")
end

function MapController.close()
	if not isOpen then
		return
	end
	isOpen = false
	panel.Visible = false
	PanelState.set("map", false)
end

function MapController.open()
	if isOpen then
		return
	end
	if plan == nil or not matchRunning() then
		NotificationController.show(t("map.unavailable"), Theme.textDim)
		return
	end
	isOpen = true
	fit()
	refreshTexts()
	if not planDrawn then
		drawPlan()
	end
	refreshMarkers()
	panel.Visible = true
	PanelState.set("map", true)
end

function MapController.toggle()
	if isOpen then
		MapController.close()
	else
		MapController.open()
	end
end

-- Clic sur la carte : repère posé au sol, à cet endroit de la carte.
local function onClick(input: InputObject)
	local size = canvas.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	local u = (input.Position.X - canvas.AbsolutePosition.X) / size.X
	local v = (input.Position.Y - canvas.AbsolutePosition.Y) / size.Y
	if u < 0 or u > 1 or v < 0 or v > 1 then
		return
	end
	local flat = MapPlan.toWorld(u, v, Maps.origin, Maps.size)
	local exclude: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(exclude, other.Character)
		end
	end
	groundParams.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(flat + Vector3.new(0, 400, 0), Vector3.new(0, -900, 0), groundParams)
	PingController.sendFromMap(if hit then hit.Position else flat)
end

local function build(root: Instance)
	title = Create("TextLabel", {
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -70, 0, 30),
		BackgroundTransparency = 1,
		Font = Theme.fontTitle,
		TextSize = 20,
		TextColor3 = Theme.cyan,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
	})
	local close = Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 2),
		Size = UDim2.fromOffset(Theme.minButtonSize, Theme.minButtonSize - 8),
		BackgroundTransparency = 1,
		Font = Theme.fontTitle,
		TextSize = 22,
		TextColor3 = Theme.textDim,
		Text = "✕",
	})
	planLayer = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	zoneLayer = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	markerLayer = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 })
	canvas = Create("TextButton", {
		Position = UDim2.fromOffset(12, 40),
		Size = UDim2.fromOffset(400, 400),
		BackgroundColor3 = Theme.background,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		ClipsDescendants = true,
		Text = "",
	}, {
		Stroke = Create("UIStroke", { Color = Theme.cyan, Transparency = 0.5 }),
		Plan = planLayer,
		Zones = zoneLayer,
		Markers = markerLayer,
		-- Nord en haut.
		North = Create("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 4),
			Size = UDim2.fromOffset(20, 16),
			BackgroundTransparency = 1,
			Font = Theme.fontTitle,
			TextSize = 13,
			TextColor3 = Theme.textDim,
			Text = "N",
			ZIndex = 3,
		}),
	})
	legend = Create("TextLabel", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -6),
		Size = UDim2.new(1, -24, 0, 32),
		BackgroundTransparency = 1,
		Font = Theme.fontText,
		TextSize = 12,
		TextColor3 = Theme.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Text = "",
	})
	panel = Create("Frame", {
		Name = "MapPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(424, 484),
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 8,
		Parent = root,
	}, {
		Stroke = Create("UIStroke", { Color = Theme.cyan, Transparency = 0.4 }),
		Title = title,
		Close = close,
		Canvas = canvas,
		Legend = legend,
	})

	close.Activated:Connect(MapController.close)
	canvas.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			onClick(input)
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			PingController.clearWaypoints()
		end
	end)
end

function MapController.init() end

function MapController.start()
	build(HUDController.root())

	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Map" then
			setMap(child)
		end
	end)
	Workspace.ChildRemoved:Connect(function(child)
		if child.Name == "Map" then
			setMap(nil)
			MapController.close()
		end
	end)
	setMap(Workspace:FindFirstChild("Map"))

	InputController.ActionBegan:Connect(function(action)
		if action == "map" then
			MapController.toggle()
		elseif action == "inventory" and isOpen then
			MapController.close()
		end
	end)
	ClientNet.on("ReviveState", function(payload: { [string]: any }?)
		revive = if type(payload) == "table" then payload else nil
	end)
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if isOpen then
			fit()
		end
	end)
	InputController.DeviceChanged:Connect(function()
		if isOpen then
			refreshTexts()
		end
	end)

	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		if not isOpen then
			return
		end
		-- Fin de partie ou mort : la carte se referme.
		if not matchRunning() then
			MapController.close()
			return
		end
		accumulator += dt
		if accumulator >= REFRESH then
			accumulator = 0
			refreshMarkers()
		end
	end)
end

return MapController
