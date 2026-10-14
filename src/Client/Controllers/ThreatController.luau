--!strict
--[[
	ThreatController : le détecteur du joueur. Être attaqué par un robot ne
	doit jamais être une surprise.

	- Radar (en haut à gauche, sous la boussole) : le joueur au centre (son
	  avatar), « devant » en haut, un point par robot proche. Gris : ne vous
	  a pas vu. Jaune : en alerte. Orange : vous remarque. Rouge : vous a pris
	  pour cible. Losange : Gardien. Un robot qui vous vise de loin reste
	  indiqué sur le bord. Coéquipier : point cyan.
	- Approche imminente (robot qui vous vise de près, attaque annoncée) : le
	  radar et l'avatar clignotent en rouge.
	- Marqueurs de direction autour du viseur pour les robots qui vous visent
	  hors de votre champ de vision.
	- Attaques annoncées (attributs WindupUntil / WindupKind des robots) :
	  visée rouge du tir chargé, cercle au sol du coup de mêlée lourd et du
	  Gardien qui va surgir. On s'écarte ou on se met à couvert.

	Tout est lu sur les attributs répliqués des robots (Alert, Aggro…) : aucune
	requête au serveur. Les autres joueurs n'apparaissent jamais sur le radar.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Radar = require(Shared.Match.Radar)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
local Theme = require(script.Parent.Parent.UI.Theme)
local HUDController = require(script.Parent.HUDController)
local InputController = require(script.Parent.InputController)
local ProfileController = require(script.Parent.ProfileController)

local ThreatController = {}

local player = Players.LocalPlayer
local t = ProfileController.t
local T = Config.Robots.threat

local SIZE = 132
local DOT_RADIUS = SIZE / 2 - 7
local ARC_RADIUS = 128
local YELLOW = Color3.fromRGB(255, 221, 51)
local LEVEL_COLORS: { [string]: Color3 } = {
	none = Theme.textDim,
	alert = YELLOW,
	noticed = Theme.orange,
	hostile = Theme.red,
	imminent = Theme.red,
}
local STATUS_KEYS: { [string]: string } = {
	noticed = "radar.noticed",
	hostile = "radar.targeted",
	imminent = "radar.danger",
}

type Tracked = {
	model: Model,
	root: BasePart,
	guardian: boolean,
	telegraph: { Instance },
	token: number,
}

type Contact = {
	position: Vector3,
	level: Radar.Level,
	guardian: boolean,
	mate: boolean,
	windup: boolean,
}

local tracked: { [Model]: Tracked } = {}
local trackedCount = 0
local contacts: { Contact } = {}
local worst: Radar.Level = "none"
local guardianHostile = false

local frame: Frame
local scale: UIScale
local stroke: UIStroke
local pulse: Frame
local avatarStroke: UIStroke
local statusLabel: TextLabel
local blips: { Frame } = {}
local arcHolder: Frame
local arcs: { Frame } = {}

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function myRoot(): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function matchRunning(): boolean
	local state = ReplicatedStorage:FindFirstChild("MatchState")
	return state ~= nil and state:GetAttribute("Running") == true
end

-- Attaques annoncées --------------------------------------------------------------

-- Point du sol sous une position (les cercles d'annonce sont posés à plat).
local function groundBelow(position: Vector3): Vector3
	local exclude: { Instance } = {}
	local robotsFolder = Workspace:FindFirstChild("Robots")
	if robotsFolder then
		table.insert(exclude, robotsFolder)
	end
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(exclude, other.Character)
		end
	end
	groundParams.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -60, 0), groundParams)
	return if hit then hit.Position else position
end

local function disc(position: Vector3, diameter: number, transparency: number): Part
	local part = Instance.new("Part")
	part.Name = "ThreatRing"
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.Neon
	part.Color = Theme.red
	part.Transparency = transparency
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = Vector3.new(0.12, diameter, diameter)
	part.CFrame = CFrame.new(position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	part.Parent = Workspace
	return part
end

--[[
	Cercle d'annonce au sol : la zone touchée, et un disque qui la remplit
	jusqu'au coup. Retourne les pièces créées (détruites à la fin).
]]
local function groundRing(position: Vector3, radius: number, duration: number): { Instance }
	local ground = groundBelow(position)
	local zone = disc(ground, radius * 2, 0.82)
	local fill = disc(ground + Vector3.new(0, 0.03, 0), 0.5, 0.55)
	TweenService:Create(fill, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		Size = Vector3.new(0.12, radius * 2, radius * 2),
	}):Play()
	task.delay(duration + 0.15, function()
		zone:Destroy()
		fill:Destroy()
	end)
	return { zone, fill }
end

local function clearTelegraph(entry: Tracked)
	for _, instance in entry.telegraph do
		instance:Destroy()
	end
	table.clear(entry.telegraph)
end

local function onWindup(entry: Tracked)
	entry.token += 1
	local token = entry.token
	clearTelegraph(entry)
	local model = entry.model
	local untilTime = model:GetAttribute("WindupUntil")
	if type(untilTime) ~= "number" then
		return
	end
	local remaining = untilTime - serverNow()
	if remaining <= 0.05 then
		return
	end
	local kind = model:GetAttribute("WindupKind")
	local eye = model:FindFirstChild("Eye")

	-- L'œil s'embrase pendant toute l'annonce.
	if eye and eye:IsA("BasePart") then
		local light = Instance.new("PointLight")
		light.Color = Theme.red
		light.Range = 14
		light.Brightness = 0.5
		light.Parent = eye
		TweenService:Create(light, TweenInfo.new(remaining), { Brightness = 6 }):Play()
		table.insert(entry.telegraph, light)
	end

	if kind == "shot" then
		-- Visée rouge du tir chargé, de l'œil du robot au joueur visé.
		local aggro = model:GetAttribute("Aggro")
		local target = if type(aggro) == "number" then Players:GetPlayerByUserId(aggro) else nil
		local character = if target then target.Character else nil
		local targetRoot = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if eye and eye:IsA("BasePart") and targetRoot and targetRoot:IsA("BasePart") then
			local from = Instance.new("Attachment")
			from.Parent = eye
			local to = Instance.new("Attachment")
			to.Parent = targetRoot
			local beam = Instance.new("Beam")
			beam.Attachment0 = from
			beam.Attachment1 = to
			beam.Color = ColorSequence.new(Theme.red)
			beam.LightEmission = 1
			beam.FaceCamera = true
			beam.Segments = 1
			beam.Transparency = NumberSequence.new(0.35)
			beam.Width0 = 0.05
			beam.Width1 = 0.05
			beam.Parent = eye
			TweenService:Create(beam, TweenInfo.new(remaining), { Width0 = 0.35, Width1 = 0.35 }):Play()
			table.insert(entry.telegraph, beam)
			table.insert(entry.telegraph, from)
			table.insert(entry.telegraph, to)
		end
	elseif kind == "melee" then
		-- Coup lourd : la zone touchée est dessinée au sol (les coups rapides n'en ont pas).
		local radius = model:GetAttribute("WindupRadius")
		if type(radius) == "number" and remaining >= 0.4 then
			for _, part in groundRing(entry.root.Position, radius, remaining) do
				table.insert(entry.telegraph, part)
			end
		end
	end

	task.delay(remaining + 0.1, function()
		if entry.token == token then
			clearTelegraph(entry)
		end
	end)
end

-- Suivi des robots ------------------------------------------------------------------

local function untrack(model: Model)
	local entry = tracked[model]
	if entry then
		entry.token += 1
		clearTelegraph(entry)
		tracked[model] = nil
		trackedCount -= 1
	end
end

local function track(model: Instance)
	if not model:IsA("Model") or tracked[model] then
		return
	end
	task.spawn(function()
		local root = model:WaitForChild("HumanoidRootPart", 5)
		if root == nil or not root:IsA("BasePart") or tracked[model] or not model:IsDescendantOf(Workspace) then
			return
		end
		local entry: Tracked = {
			model = model,
			root = root,
			guardian = model:GetAttribute("Guardian") == true,
			telegraph = {},
			token = 0,
		}
		tracked[model] = entry
		trackedCount += 1
		model:GetAttributeChangedSignal("WindupUntil"):Connect(function()
			onWindup(entry)
		end)
		model:GetAttributeChangedSignal("Guardian"):Connect(function()
			entry.guardian = model:GetAttribute("Guardian") == true
		end)
		model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(Workspace) then
				untrack(model)
			end
		end)
		onWindup(entry)
	end)
end

local function watchFolder(folder: Instance)
	folder.ChildAdded:Connect(track)
	folder.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			untrack(child)
		end
	end)
	for _, child in folder:GetChildren() do
		track(child)
	end
end

-- Radar -----------------------------------------------------------------------------

local function ring(ratio: number): Frame
	return Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(ratio, ratio),
		BackgroundTransparency = 1,
	}, {
		Corner = Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Stroke = Create("UIStroke", { Color = Theme.cyan, Transparency = 0.8 }),
	})
end

local function build(root: Instance)
	stroke = Create("UIStroke", { Color = Theme.cyan, Thickness = 2, Transparency = 0.45 })
	avatarStroke = Create("UIStroke", { Color = Theme.cyan, Thickness = 2, Transparency = 0.2 })
	pulse = Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.red,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, { Corner = Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	local avatar = Create("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = Theme.panel,
		BorderSizePixel = 0,
		Image = "",
		ZIndex = 4,
	}, {
		Corner = Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Stroke = avatarStroke,
		-- Tant que le portrait n'est pas chargé : une flèche (le joueur regarde vers le haut).
		Fallback = Create("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Theme.fontTitle,
			TextSize = 16,
			TextColor3 = Theme.cyan,
			Text = "▲",
			ZIndex = 4,
		}),
	})
	statusLabel = Create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 4),
		Size = UDim2.fromOffset(SIZE + 60, 16),
		BackgroundTransparency = 1,
		Font = Theme.fontTitle,
		TextSize = 12,
		TextColor3 = Theme.textDim,
		TextStrokeTransparency = 0.5,
		Text = "",
	})
	scale = Create("UIScale", {})
	-- Le radar est aussi un bouton : il ouvre la carte (indispensable sur mobile).
	local button = Create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 6,
	}, { Corner = Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	frame = Create("Frame", {
		Name = "Radar",
		Position = UDim2.fromOffset(16, 58),
		Size = UDim2.fromOffset(SIZE, SIZE),
		BackgroundColor3 = Theme.background,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Visible = false,
		Parent = root,
	}, {
		Corner = Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Stroke = stroke,
		Scale = scale,
		Pulse = pulse,
		Inner = ring(0.34),
		Middle = ring(0.67),
		-- Repère « devant ».
		Front = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 2),
			Size = UDim2.fromOffset(2, 9),
			BackgroundColor3 = Theme.cyan,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
		}),
		Avatar = avatar,
		Status = statusLabel,
		Button = button,
	})
	for index = 1, T.maxBlips do
		blips[index] = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(7, 7),
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 3,
			Parent = frame,
		}, { Corner = Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	end

	arcHolder = Create("Frame", {
		Name = "ThreatArcs",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		Parent = root,
	})
	for index = 1, T.arcs do
		arcs[index] = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(40, 3),
			BorderSizePixel = 0,
			Visible = false,
			Parent = arcHolder,
		}, {
			Corner = Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
			-- Pointe vers l'extérieur : c'est de là que vient la menace.
			Tip = Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 0, -3),
				Size = UDim2.fromOffset(14, 3),
				BorderSizePixel = 0,
			}, { Corner = Create("UICorner", { CornerRadius = UDim.new(1, 0) }) }),
		})
	end

	button.Activated:Connect(function()
		InputController.press("map")
		InputController.release("map")
	end)

	-- Portrait du joueur au centre du radar.
	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(
				player.UserId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size100x100
			)
		end)
		if ok and type(image) == "string" and image ~= "" then
			avatar.Image = image
			local fallback = avatar:FindFirstChild("Fallback")
			if fallback then
				fallback:Destroy()
			end
		end
	end)
end

-- Relevé des robots et des coéquipiers proches (10 fois par seconde).
local function scan()
	table.clear(contacts)
	worst = "none"
	guardianHostile = false
	local root = myRoot()
	if root == nil then
		return
	end
	local origin = root.Position
	local time = serverNow()
	for model, entry in tracked do
		if model:GetAttribute("Dead") == true or model:GetAttribute("Hidden") == true then
			continue
		end
		local position = entry.root.Position
		local distance = (position - origin).Magnitude
		local untilTime = model:GetAttribute("WindupUntil")
		local aggro = model:GetAttribute("Aggro") == player.UserId
		local windup = aggro and type(untilTime) == "number" and untilTime > time
		local alert = model:GetAttribute("Alert")
		local level = Radar.level({
			alert = if type(alert) == "string" then alert else nil,
			aggro = aggro,
			windup = windup,
			guardian = entry.guardian,
			distance = distance,
		}, T)
		local hostile = level == "hostile" or level == "imminent"
		if distance <= T.radarRange or (hostile and distance <= T.edgeRange) then
			table.insert(contacts, {
				position = position,
				level = level,
				guardian = entry.guardian,
				mate = false,
				windup = windup,
			})
			worst = Radar.worst(worst, level)
			if hostile and entry.guardian then
				guardianHostile = true
			end
		end
	end
	-- Les plus menaçants d'abord (ce sont eux qui gardent un point si le radar est plein).
	table.sort(contacts, function(a, b)
		local ra, rb = Radar.rank(a.level), Radar.rank(b.level)
		if ra ~= rb then
			return ra > rb
		end
		return (a.position - origin).Magnitude < (b.position - origin).Magnitude
	end)
	-- Coéquipier (duo).
	local team = player:GetAttribute("TeamId")
	if team ~= nil then
		for _, other in Players:GetPlayers() do
			if other ~= player and other:GetAttribute("TeamId") == team and other.Character then
				local mateRoot = other.Character:FindFirstChild("HumanoidRootPart")
				if mateRoot and mateRoot:IsA("BasePart") then
					table.insert(contacts, 1, {
						position = mateRoot.Position,
						level = "none" :: Radar.Level,
						guardian = false,
						mate = true,
						windup = false,
					})
				end
			end
		end
	end
end

local function render()
	local root = myRoot()
	local visible = root ~= nil and (trackedCount > 0 or matchRunning())
	frame.Visible = visible
	arcHolder.Visible = visible
	if not visible or root == nil then
		return
	end
	local origin = root.Position
	local look = Workspace.CurrentCamera.CFrame.LookVector
	local blink = math.floor(os.clock() * 5) % 2 == 0

	local arcIndex = 0
	for index, blip in blips do
		local contact = contacts[index]
		if contact == nil then
			blip.Visible = false
			continue
		end
		local offset = contact.position - origin
		local x, y, clamped = Radar.project(offset, look, T.radarRange)
		local color = if contact.mate then Theme.cyan else LEVEL_COLORS[contact.level]
		local size = if contact.guardian then 11 elseif clamped then 5 else 7
		blip.Position = UDim2.new(0.5, x * DOT_RADIUS, 0.5, y * DOT_RADIUS)
		blip.Size = UDim2.fromOffset(size, size)
		blip.Rotation = if contact.guardian then 45 else 0
		local corner = blip:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = if contact.guardian then UDim.new(0, 1) else UDim.new(1, 0)
		end
		blip.BackgroundColor3 = color
		blip.BackgroundTransparency = if contact.level == "imminent" and not blink
			then 0.6
			elseif contact.level == "none" and not contact.mate then 0.35
			else 0
		blip.Visible = true

		-- Marqueur de direction : robot qui vous vise hors du champ (ou attaque annoncée).
		local hostile = contact.level == "hostile" or contact.level == "imminent"
		if hostile and arcIndex < #arcs then
			local bearing = Radar.bearing(offset, look)
			if contact.windup or math.abs(math.deg(bearing)) > T.arcMinAngle then
				arcIndex += 1
				local arc = arcs[arcIndex]
				local arcColor = if contact.level == "imminent" then Theme.red else Theme.orange
				local transparency = if contact.level == "imminent" then (if blink then 0.05 else 0.45) else 0.35
				arc.Position = UDim2.fromOffset(math.sin(bearing) * ARC_RADIUS, -math.cos(bearing) * ARC_RADIUS)
				arc.Rotation = math.deg(bearing)
				arc.BackgroundColor3 = arcColor
				arc.BackgroundTransparency = transparency
				local tip = arc:FindFirstChild("Tip") :: Frame
				tip.BackgroundColor3 = arcColor
				tip.BackgroundTransparency = transparency
				arc.Visible = true
			end
		end
	end
	for index = arcIndex + 1, #arcs do
		arcs[index].Visible = false
	end

	-- État général : couleur du cadre, clignotement, message.
	local color = if worst == "imminent" or worst == "hostile"
		then Theme.red
		elseif worst == "noticed" then Theme.orange
		else Theme.cyan
	stroke.Color = color
	stroke.Transparency = if worst == "none" or worst == "alert" then 0.45 else 0.1
	avatarStroke.Color = color
	pulse.BackgroundTransparency = if worst == "imminent" then (if blink then 0.6 else 0.88) else 1
	local key = STATUS_KEYS[worst]
	if guardianHostile and worst ~= "imminent" then
		key = "radar.guardian"
	end
	if key then
		statusLabel.Text = t(key)
		statusLabel.TextColor3 = color
		statusLabel.TextTransparency = if worst == "imminent" and not blink then 0.4 else 0
	else
		local mapKey = InputController.hint("map")
		statusLabel.Text = if mapKey then `[{mapKey}] {t("radar.map")}` else t("radar.map")
		statusLabel.TextColor3 = Theme.textDim
		statusLabel.TextTransparency = 0.2
	end
end

function ThreatController.init() end

function ThreatController.start()
	build(HUDController.root())

	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Robots" then
			watchFolder(child)
		end
	end)
	local existing = Workspace:FindFirstChild("Robots")
	if existing then
		watchFolder(existing)
	end

	-- Gardien enfoui : le point d'émergence est annoncé par un cercle au sol.
	ClientNet.on("MapEvent", function(kind: string, position: Vector3, radius: number?, duration: number?)
		if kind == "surfaceWarning" and typeof(position) == "Vector3" then
			groundRing(position, tonumber(radius) or 8, math.clamp(tonumber(duration) or 1.2, 0.2, 5))
		end
	end)

	-- Petit écran : le radar rétrécit.
	local function fit()
		local viewport = Workspace.CurrentCamera.ViewportSize
		scale.Scale = if math.min(viewport.X, viewport.Y) < 520 then 0.78 else 1
	end
	fit()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		accumulator += dt
		if accumulator >= T.refresh then
			accumulator = 0
			scan()
		end
		render()
	end)
end

return ThreatController
