--!strict
--[[
	TutorialController : le tutoriel côté client (section 15.2).

	- Radio de la mentor (Vesna, ancienne mercenaire) : message tapé lettre
	  par lettre à chaque étape, avec grésillement.
	- Objectif en haut de l'écran (cibles abattues, extraction en cours…),
	  temps restant, bouton « Quitter » pour un tutoriel rejoué.
	- Signaux visuels : décharge d'AXIOM (écran rouge), « PAREZ ! » quand le
	  robot d'entraînement arme son coup.
	- Fin : cinématique d'arrivée au Terminus (bandes noires, survol du hall).

	Tout l'état vient du serveur (TutorialState) : le client n'envoie que
	« refaire » ou « quitter ».
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
local Panel = require(script.Parent.Parent.UI.Panel)
local Theme = require(script.Parent.Parent.UI.Theme)
local CameraController = require(script.Parent.CameraController)
local HUDController = require(script.Parent.HUDController)
local InputController = require(script.Parent.InputController)
local NotificationController = require(script.Parent.NotificationController)
local ProfileController = require(script.Parent.ProfileController)

local TutorialController = {}

local t = ProfileController.t
local player = Players.LocalPlayer
local Tutorial = Config.Progression.tutorial

local root: Frame
local radio: Frame
local radioText: TextLabel
local goal: TextLabel
local timer: TextLabel
local cue: TextLabel
local flash: Frame
local skip: TextButton
local state: { [string]: any }? = nil
local lastStep: string? = nil
local typingToken = 0
local timeLeftAt = 0
local timeLeft = 0

-- Message radio tapé lettre par lettre.
local function say(text: string)
	typingToken += 1
	local token = typingToken
	radio.Visible = true
	radioText.Text = ""
	task.spawn(function()
		local shown = 0
		for _, codepoint in utf8.codes(text) do
			if token ~= typingToken then
				return
			end
			shown += 1
			radioText.Text = radioText.Text .. utf8.char(codepoint)
			if shown % 2 == 0 then
				task.wait(0.02)
			end
		end
	end)
end

local function showCue(text: string, color: Color3)
	cue.Text = text
	cue.TextColor3 = color
	cue.TextTransparency = 0
	cue.TextStrokeTransparency = 0.3
	TweenService:Create(cue, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
end

local function renderGoal()
	local current = state
	if current == nil then
		return
	end
	goal.Text = t("tutorial.goal." .. tostring(current.step), {
		count = current.count or 0,
		goal = current.goal or 0,
		progress = math.floor(current.progress or 0),
		key = InputController.hint("parry") or "",
	})
	local remaining = math.max(0, timeLeft - (os.clock() - timeLeftAt))
	timer.Text = t("tutorial.timer", {
		step = current.index or 1,
		total = current.total or 6,
		time = string.format("%d:%02d", math.floor(remaining / 60), math.floor(remaining % 60)),
	})
end

-- Textes localisés du décor de la simulation.
local function localizeArea()
	local area = Workspace:FindFirstChild(`Tutorial_{player.UserId}`)
	if area == nil then
		return
	end
	for _, descendant in area:GetDescendants() do
		if descendant:IsA("TextLabel") then
			local key = descendant:GetAttribute("TextKey")
			if type(key) == "string" then
				descendant.Text = t(key)
			end
		end
	end
end

-- Cinématique d'arrivée : survol du Terminus jusqu'au point d'apparition.
local function arrivalCinematic(level: number?)
	local terminus = Workspace:FindFirstChild("Terminus")
	local structure = if terminus then terminus:FindFirstChild("Structure") else nil
	local platform = if structure then structure:FindFirstChild("Platform") else nil
	local camera = Workspace.CurrentCamera
	if platform == nil or not platform:IsA("BasePart") then
		return
	end
	-- Attend le nouveau personnage, apparu au Terminus.
	local rootPart: BasePart? = nil
	for _ = 1, 100 do
		local character = player.Character
		local candidate = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if candidate and candidate:IsA("BasePart") and (candidate.Position - platform.Position).Magnitude < 260 then
			rootPart = candidate
			break
		end
		task.wait(0.1)
	end
	if rootPart == nil then
		return
	end
	local center = platform.Position
	local target = rootPart.Position
	CameraController.setEnabled(false)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(center + Vector3.new(80, 45, 70), center)

	local bars = Create("Frame", {
		Name = "Cinematic",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 50,
		Parent = root.Parent,
	}, {
		Top = Create("Frame", {
			Size = UDim2.fromScale(1, 0.12),
			BackgroundColor3 = Color3.new(),
			BorderSizePixel = 0,
			ZIndex = 50,
		}),
		Bottom = Create("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0.12),
			BackgroundColor3 = Color3.new(),
			BorderSizePixel = 0,
			ZIndex = 50,
		}),
		Title = Create("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.72),
			Size = UDim2.new(0.8, 0, 0, 60),
			BackgroundTransparency = 1,
			Font = Theme.fontTitle,
			TextSize = 46,
			TextColor3 = Theme.cyan,
			TextStrokeTransparency = 0.4,
			Text = t("tutorial.arrival.title"),
			ZIndex = 51,
		}),
		Subtitle = Create("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.8),
			Size = UDim2.new(0.8, 0, 0, 30),
			BackgroundTransparency = 1,
			Font = Theme.fontText,
			TextSize = 20,
			TextColor3 = Theme.text,
			Text = t("tutorial.arrival.subtitle"),
			ZIndex = 51,
		}),
	})
	local duration = Tutorial.cinematicDuration
	local midway = CFrame.lookAt(center + Vector3.new(-30, 22, 40), center + Vector3.new(0, 6, 0))
	local final = CFrame.lookAt(target + Vector3.new(0, 6, 16), target + Vector3.new(0, 2, 0))
	local first =
		TweenService:Create(camera, TweenInfo.new(duration * 0.55, Enum.EasingStyle.Sine), { CFrame = midway })
	first:Play()
	first.Completed:Wait()
	local second = TweenService:Create(
		camera,
		TweenInfo.new(duration * 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = final }
	)
	second:Play()
	second.Completed:Wait()
	bars:Destroy()
	CameraController.setEnabled(true)
	if level then
		NotificationController.show(t("tutorial.reward", { level = level }), Theme.green)
	end
end

local function onState(next: { [string]: any })
	if next.done then
		state = nil
		lastStep = nil
		typingToken += 1
		root.Visible = false
		if next.reason ~= "aborted" then
			task.spawn(arrivalCinematic, if next.replay then nil else next.level)
		end
		return
	end
	state = next
	root.Visible = true
	timeLeft = next.timeLeft or 0
	timeLeftAt = os.clock()
	skip.Visible = next.replay == true
	if next.step ~= lastStep then
		lastStep = next.step
		say(t("tutorial.radio." .. tostring(next.step)))
		task.defer(localizeArea)
	end
	local signal = next.cue
	if signal == "zap" then
		flash.BackgroundTransparency = 0.35
		TweenService:Create(flash, TweenInfo.new(0.9), { BackgroundTransparency = 1 }):Play()
		showCue(t("tutorial.cue.zap"), Theme.red)
	elseif signal == "windup" then
		showCue(t("tutorial.cue.windup", { key = InputController.hint("parry") or "" }), Theme.orange)
	elseif signal == "perfect" or signal == "parried" then
		showCue(t("tutorial.cue." .. signal), Theme.green)
	end
	renderGoal()
end

function TutorialController.init() end

function TutorialController.start()
	local gui = HUDController.root()
	root = Create("Frame", {
		Name = "Tutorial",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	flash = Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.red,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = root,
	})
	goal = Create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.new(0.6, 0, 0, 34),
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = Theme.panelTransparency,
		Font = Theme.fontTitle,
		TextSize = 20,
		TextColor3 = Theme.cyan,
		Parent = root,
	}, {
		Stroke = Create("UIStroke", { Color = Theme.cyan, Transparency = 0.4 }),
	})
	timer = Create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 100),
		Size = UDim2.new(0.6, 0, 0, 20),
		BackgroundTransparency = 1,
		Font = Theme.fontNumbers,
		TextSize = 15,
		TextColor3 = Theme.textDim,
		Parent = root,
	})
	cue = Create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.35),
		Size = UDim2.new(0.8, 0, 0, 60),
		BackgroundTransparency = 1,
		Font = Theme.fontTitle,
		TextSize = 44,
		TextColor3 = Theme.orange,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		Parent = root,
	})
	radio = Create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -190),
		Size = UDim2.fromOffset(380, 110),
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = Theme.panelTransparency,
		Parent = root,
	}, {
		Stroke = Create("UIStroke", { Color = Theme.orange, Thickness = 2 }),
		Mentor = Create("TextLabel", {
			Position = UDim2.fromOffset(10, 4),
			Size = UDim2.new(1, -20, 0, 22),
			BackgroundTransparency = 1,
			Font = Theme.fontTitle,
			TextSize = 15,
			TextColor3 = Theme.orange,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
		}),
	})
	radioText = Create("TextLabel", {
		Position = UDim2.fromOffset(10, 28),
		Size = UDim2.new(1, -20, 1, -34),
		BackgroundTransparency = 1,
		Font = Theme.fontText,
		TextSize = 15,
		TextColor3 = Theme.text,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = radio,
	})
	skip = Panel.button("", Theme.textDim, 160)
	skip.AnchorPoint = Vector2.new(1, 0)
	skip.Position = UDim2.new(1, -16, 0, 110)
	skip.Visible = false
	skip.Parent = root
	skip.Activated:Connect(function()
		ClientNet.fire("TutorialAction", "skip")
	end)

	local function relabel()
		(radio:FindFirstChild("Mentor") :: TextLabel).Text = t("tutorial.mentor")
		skip.Text = t("tutorial.skip")
		renderGoal()
	end
	relabel()
	ProfileController.Changed:Connect(relabel)
	ClientNet.on("TutorialState", onState)
	task.spawn(function()
		while true do
			if state then
				renderGoal()
			end
			task.wait(0.5)
		end
	end)
end

return TutorialController
