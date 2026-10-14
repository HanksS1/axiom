--!strict
--[[
	MatchHUDController : affichage de la partie (section 17.3, écrans 11, 13, 14, 15).

	- En haut au centre : chrono (orange à 12:00, rouge clignotant la dernière minute).
	- En haut à gauche : boussole et direction / distance des extractions ouvertes
	  (orange) et des repères posés sur la carte (cyan).
	- En haut à droite : fil des éliminations (« X a été désintégré »).
	- Annonces d'AXIOM (bandeau central).
	- Extraction : barre circulaire de 30 s (jaune en pause, rouge si bloquée).
	- Orbe (duo) : compte à rebours, marqueur de l'Accélérateur.
	- Fin de partie : résumé, score détaillé, record, XP.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MatchRules = require(Shared.Match.MatchRules)
local Signal = require(Shared.Util.Signal)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
local PanelState = require(script.Parent.Parent.UI.PanelState)
local Theme = require(script.Parent.Parent.UI.Theme)
local HUDController = require(script.Parent.HUDController)
local PingController = require(script.Parent.PingController)
local ProfileController = require(script.Parent.ProfileController)

local MatchHUDController = {}

-- Statut du joueur dans la partie ("none" hors partie).
MatchHUDController.StatusChanged = Signal.new() :: Signal.Signal<string>

local player = Players.LocalPlayer
local t = ProfileController.t

local status = "none"
local revive: { [string]: any }? = nil
local extraction: { zoneId: string?, progress: number, status: string } =
	{ zoneId = nil, progress = 0, status = "idle" }

local timerLabel: TextLabel
local compass: Frame
local compassMarkers: { [Instance]: TextLabel } = {}
local feed: Frame
local banner: TextLabel
local extractionFrame: Frame
local extractionRing: Frame
local extractionLabel: TextLabel
local reviveLabel: TextLabel
local acceleratorMarker: BillboardGui?
local resultPanel: Frame

local function matchState(): Instance?
	return ReplicatedStorage:FindFirstChild("MatchState")
end

local function isRunning(): boolean
	local state = matchState()
	return state ~= nil and state:GetAttribute("Running") == true
end

local function elapsed(): number
	local state = matchState()
	local start = if state then state:GetAttribute("StartTime") else nil
	if type(start) ~= "number" then
		return 0
	end
	return Workspace:GetServerTimeNow() - start
end

function MatchHUDController.status(): string
	return status
end

local function formatTime(seconds: number): string
	local total = math.max(0, math.ceil(seconds))
	return string.format("%02d:%02d", math.floor(total / 60), total % 60)
end

-- Bandeau d'annonce d'AXIOM (voix synthétique : texte en P3, voix en P10).
local function announce(key: string)
	banner.Text = t(key)
	banner.TextTransparency = 0
	banner.TextStrokeTransparency = 0.4
	banner.Visible = true
	local stamp = os.clock()
	banner:SetAttribute("Stamp", stamp)
	task.delay(4, function()
		if banner:GetAttribute("Stamp") == stamp then
			TweenService:Create(banner, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

local function addFeed(victim: string, killer: string?)
	local text = if killer
		then t("killfeed.by", { killer = killer, victim = victim })
		else t("killfeed.disintegrated", { victim = victim })
	local label = Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = 0.3,
		Font = Theme.fontText,
		TextSize = 14,
		TextColor3 = Theme.text,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = text .. "  ",
		Parent = feed,
	})
	task.delay(6, function()
		label:Destroy()
	end)
	local count = 0
	for _, child in feed:GetChildren() do
		if child:IsA("TextLabel") then
			count += 1
		end
	end
	if count > 5 then
		(feed:FindFirstChildWhichIsA("TextLabel") :: TextLabel):Destroy()
	end
end

-- Boussole : cap actuel, repères des extractions ouvertes et des repères de carte.
local function updateCompass()
	local camera = Workspace.CurrentCamera
	local look = camera.CFrame.LookVector
	local heading = math.atan2(-look.X, -look.Z)
	local origin = camera.CFrame.Position
	local seen: { [Instance]: boolean } = {}
	-- Place (ou crée) le repère d'un point sur la boussole.
	local function place(key: Instance, target: Vector3, color: Color3)
		seen[key] = true
		local marker = compassMarkers[key]
		if marker == nil then
			marker = Create("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0),
				Size = UDim2.fromOffset(90, 30),
				BackgroundTransparency = 1,
				Font = Theme.fontNumbers,
				TextSize = 12,
				TextColor3 = color,
				Parent = compass,
			})
			compassMarkers[key] = marker
		end
		local offset = target - origin
		local bearing = math.atan2(-offset.X, -offset.Z)
		local delta = (bearing - heading + math.pi) % (2 * math.pi) - math.pi
		local x = math.clamp(0.5 - delta / math.pi, 0, 1)
		marker.Position = UDim2.new(x, 0, 0, 2)
		marker.Text = "▼\n" .. tostring(math.floor(Vector3.new(offset.X, 0, offset.Z).Magnitude)) .. "m"
		marker.TextTransparency = if math.abs(delta) > math.pi / 2 then 0.5 else 0
	end
	local folder = Workspace:FindFirstChild("Extractions")
	if folder then
		for _, zone in folder:GetChildren() do
			if zone:IsA("Model") and zone:GetAttribute("Open") == true and zone.PrimaryPart then
				place(zone, (zone.PrimaryPart :: BasePart).Position, Theme.orange)
			end
		end
	end
	for _, ping in PingController.active() do
		if ping.waypoint then
			place(ping.anchor, ping.position, Theme.cyan)
		end
	end
	for zone, marker in compassMarkers do
		if not seen[zone] then
			marker:Destroy()
			compassMarkers[zone] = nil
		end
	end
	local cardinal = compass:FindFirstChild("Cardinal") :: TextLabel
	local degrees = math.floor((-math.deg(heading)) % 360)
	cardinal.Text = string.format("%03d°", degrees)
end

local function updateTimer()
	local running = isRunning()
	timerLabel.Visible = running
	compass.Visible = running
	if not running then
		return
	end
	local time = elapsed()
	local remaining = MatchRules.remaining(time)
	local phase = MatchRules.phase(time)
	timerLabel.Text = formatTime(remaining)
	if phase == "final" or phase == "purge" then
		-- Rouge clignotant la dernière minute.
		timerLabel.TextColor3 = Theme.red
		timerLabel.TextTransparency = if math.floor(os.clock() * 2) % 2 == 0 then 0 else 0.5
	elseif phase == "alert" then
		timerLabel.TextColor3 = Theme.orange
		timerLabel.TextTransparency = 0
	else
		timerLabel.TextColor3 = Theme.text
		timerLabel.TextTransparency = 0
	end
end

local function updateExtraction()
	local current = extraction
	local visible = current.zoneId ~= nil and current.status ~= "idle" and status == "alive"
	extractionFrame.Visible = visible
	if not visible then
		return
	end
	local hold = Config.Match.extraction.holdTime
	local fill = extractionRing:FindFirstChild("Fill") :: Frame
	fill.Size = UDim2.fromScale(math.clamp(current.progress / hold, 0, 1), 1)
	local color = Theme.green
	local text = t("extraction.running", { seconds = math.ceil(hold - current.progress) })
	if current.status == "paused" then
		color = Color3.fromRGB(255, 221, 51)
		text = t("extraction.paused")
	elseif current.status == "blocked" then
		color = Theme.red
		text = t("extraction.blocked")
	elseif current.status == "done" then
		text = t("extraction.done")
	end
	fill.BackgroundColor3 = color
	extractionLabel.TextColor3 = color
	extractionLabel.Text = text
end

local function updateRevive()
	local current = revive
	if current == nil then
		reviveLabel.Visible = false
		if acceleratorMarker then
			acceleratorMarker:Destroy()
			acceleratorMarker = nil
		end
		return
	end
	local remaining = math.max(0, (current.expiresAt :: number) - Workspace:GetServerTimeNow())
	local time = formatTime(remaining)
	reviveLabel.Visible = true
	if current.deadUserId == player.UserId then
		reviveLabel.Text = t("revive.waiting", { time = time })
	else
		reviveLabel.Text = t("revive.orb", { time = time })
			.. (if current.carried then "  ·  " .. t("revive.carry") else "")
	end
	-- Marqueur de l'Accélérateur (visible à travers les murs pour le duo).
	if acceleratorMarker == nil and typeof(current.accelerator) == "Vector3" then
		local anchor = Instance.new("Part")
		anchor.Name = "AcceleratorAnchor"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one
		anchor.Position = current.accelerator + Vector3.new(0, 6, 0)
		anchor.Parent = Workspace
		local gui = Create("BillboardGui", {
			Size = UDim2.fromOffset(160, 40),
			AlwaysOnTop = true,
			Adornee = anchor,
			Parent = anchor,
		}, {
			Label = Create("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Font = Theme.fontTitle,
				TextSize = 16,
				TextColor3 = Theme.cyan,
				TextStrokeTransparency = 0.3,
				Text = "◆ " .. t("revive.accelerator"),
			}),
		})
		gui.Destroying:Connect(function()
			anchor:Destroy()
		end)
		acceleratorMarker = gui
	end
end

-- Écran de fin de partie.
local function showResult(result: { [string]: any })
	for _, child in resultPanel:GetChildren() do
		if child:IsA("TextLabel") or child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local lines: { { text: string, color: Color3?, size: number? } } = {}
	local outcome = tostring(result.outcome)
	table.insert(lines, {
		text = t("result." .. outcome),
		color = if outcome == "extracted" then Theme.green else Theme.red,
		size = 32,
	})
	local kills = result.kills or {}
	table.insert(lines, { text = t("result.kills", { players = kills.players or 0, bots = kills.bots or 0 }) })
	table.insert(lines, { text = t("result.robots", { points = kills.robotPoints or 0 }) })
	table.insert(lines, { text = t("result.loot", { value = result.lootValue or 0 }) })
	local duration = tonumber(result.duration) or 0
	table.insert(lines, {
		text = t("result.duration", {
			minutes = math.floor(duration / 60),
			seconds = string.format("%02d", duration % 60),
		}),
	})
	local score = result.score or {}
	table.insert(lines, { text = t("result.multiplier", { value = score.modeMultiplier or 1 }), color = Theme.textDim })
	if score.deathPenalty then
		table.insert(lines, { text = t("result.penalty"), color = Theme.orange })
	end
	table.insert(lines, { text = t("result.score", { score = score.total or 0 }), color = Theme.cyan, size = 26 })
	if result.topPosition then
		table.insert(
			lines,
			{ text = t("result.record", { position = result.topPosition }), color = Theme.orange, size = 20 }
		)
	end
	table.insert(lines, {
		text = t("result.xp", { xp = result.xpGained or 0 })
			.. "  ·  "
			.. t("result.level", { level = result.level or 1 }),
		color = Theme.green,
	})
	for index, line in lines do
		Create("TextLabel", {
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, (line.size or 18) + 8),
			BackgroundTransparency = 1,
			Font = if line.size then Theme.fontTitle else Theme.fontText,
			TextSize = line.size or 18,
			TextColor3 = line.color or Theme.text,
			Text = line.text,
			Parent = resultPanel,
		})
	end
	-- Barre d'XP animée.
	local xpBar = Create("Frame", {
		LayoutOrder = #lines + 1,
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = Theme.panel,
		BorderSizePixel = 0,
		Parent = resultPanel,
	}, {
		Fill = Create("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.green, BorderSizePixel = 0 }),
	})
	local ratio = math.clamp((tonumber(result.xp) or 0) / math.max(1, tonumber(result.xpToNext) or 1), 0, 1)
	TweenService:Create(xpBar:FindFirstChild("Fill") :: Frame, TweenInfo.new(1.2, Enum.EasingStyle.Quad), {
		Size = UDim2.fromScale(ratio, 1),
	}):Play()
	local continue = Create("TextButton", {
		LayoutOrder = #lines + 2,
		Size = UDim2.new(1, 0, 0, Theme.minButtonSize),
		BackgroundColor3 = Theme.panel,
		Font = Theme.fontTitle,
		TextSize = 18,
		TextColor3 = Theme.cyan,
		Text = t("result.returnHub"),
		Parent = resultPanel,
	}, { Stroke = Create("UIStroke", { Color = Theme.cyan, Transparency = 0.4 }) })
	continue.Activated:Connect(function()
		resultPanel.Visible = false
		PanelState.set("result", false)
		-- Retour au Terminus sans attendre la fin de la partie.
		ClientNet.fire("ReturnToHub")
	end)
	resultPanel.Visible = true
	PanelState.set("result", true)
end

function MatchHUDController.init() end

function MatchHUDController.start()
	local root = HUDController.root()

	timerLabel = Create("TextLabel", {
		Name = "MatchTimer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(160, 40),
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = Theme.panelTransparency,
		Font = Theme.fontNumbers,
		TextSize = 32,
		TextColor3 = Theme.text,
		Visible = false,
		Text = "15:00",
		Parent = root,
	})

	compass = Create("Frame", {
		Name = "Compass",
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.fromOffset(260, 40),
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = Theme.panelTransparency,
		ClipsDescendants = true,
		Visible = false,
		Parent = root,
	}, {
		Cardinal = Create("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -2),
			Size = UDim2.fromOffset(60, 14),
			BackgroundTransparency = 1,
			Font = Theme.fontNumbers,
			TextSize = 12,
			TextColor3 = Theme.textDim,
			Text = "000°",
		}),
		Center = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(2, 8),
			BackgroundColor3 = Theme.cyan,
			BorderSizePixel = 0,
		}),
	})

	feed = Create("Frame", {
		Name = "KillFeed",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 60),
		Size = UDim2.fromOffset(320, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = root,
	}, {
		Layout = Create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	banner = Create("TextLabel", {
		Name = "AxiomBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.18, 0),
		Size = UDim2.new(0.8, 0, 0, 40),
		BackgroundTransparency = 1,
		Font = Theme.fontTitle,
		TextSize = 24,
		TextColor3 = Theme.red,
		TextStrokeTransparency = 0.4,
		TextWrapped = true,
		Visible = false,
		Text = "",
		Parent = root,
	})

	extractionRing = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 10),
		Position = UDim2.fromOffset(0, 26),
		BackgroundColor3 = Theme.panel,
		BorderSizePixel = 0,
	}, {
		Fill = Create("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.green, BorderSizePixel = 0 }),
	})
	extractionLabel = Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Font = Theme.fontTitle,
		TextSize = 18,
		TextColor3 = Theme.green,
		TextStrokeTransparency = 0.5,
		Text = "",
	})
	extractionFrame = Create("Frame", {
		Name = "Extraction",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.62, 0),
		Size = UDim2.fromOffset(300, 40),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	}, { Label = extractionLabel, Bar = extractionRing })

	reviveLabel = Create("TextLabel", {
		Name = "Revive",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -110),
		Size = UDim2.fromOffset(420, 24),
		BackgroundTransparency = 1,
		Font = Theme.fontTitle,
		TextSize = 16,
		TextColor3 = Theme.cyan,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.5,
		Visible = false,
		Text = "",
		Parent = root,
	})

	resultPanel = Create("Frame", {
		Name = "MatchResult",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 20,
		Parent = root,
	}, {
		Stroke = Create("UIStroke", { Color = Theme.cyan, Transparency = 0.3 }),
		Padding = Create("UIPadding", {
			PaddingTop = UDim.new(0, 16),
			PaddingBottom = UDim.new(0, 16),
			PaddingLeft = UDim.new(0, 16),
			PaddingRight = UDim.new(0, 16),
		}),
		Layout = Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		SizeLimit = Create("UISizeConstraint", { MaxSize = Vector2.new(520, 900) }),
	})

	ClientNet.on("Announce", function(key: string)
		if type(key) == "string" then
			announce(key)
		end
	end)
	ClientNet.on("KillFeed", function(victim: string, killer: string?)
		if type(victim) == "string" then
			addFeed(victim, if type(killer) == "string" then killer else nil)
		end
	end)
	ClientNet.on("ExtractionState", function(zoneId: string?, progress: number, newStatus: string)
		extraction = { zoneId = zoneId, progress = tonumber(progress) or 0, status = tostring(newStatus) }
	end)
	ClientNet.on("ReviveState", function(payload: { [string]: any }?)
		revive = if type(payload) == "table" then payload else nil
		if revive == nil and acceleratorMarker then
			acceleratorMarker:Destroy()
			acceleratorMarker = nil
		end
	end)
	ClientNet.on("MatchStatus", function(newStatus: string)
		status = tostring(newStatus)
		MatchHUDController.StatusChanged:Fire(status)
	end)
	ClientNet.on("MatchResult", function(result: { [string]: any })
		if type(result) == "table" then
			showResult(result)
		end
	end)

	RunService.RenderStepped:Connect(function()
		updateTimer()
		if compass.Visible then
			updateCompass()
		end
		updateExtraction()
		updateRevive()
	end)
end

return MatchHUDController
