--!strict
--[[
	DeployController : Porte de déploiement, file d'attente et groupe duo
	(sections 16.2, 16.3, 16.5 et 17.3, écran 10).

	- Écran de la Porte de déploiement (station « deploy »).
	- Bandeau de file d'attente : « 11 / 16 joueurs », temps d'attente,
	  annulation, proposition de passer en crossplay après 60 s.
	- Invitations duo : invite « Inviter en duo » en approchant un joueur au
	  Terminus, invitation reçue (Accepter / Refuser, 30 s).
	- Plateforme déclarée au serveur (périphérique d'entrée principal).
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Types = require(Shared.Types)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
local Panel = require(script.Parent.Parent.UI.Panel)
local Theme = require(script.Parent.Parent.UI.Theme)
local DeployScreen = require(script.Parent.Parent.Screens.DeployScreen)
local HUDController = require(script.Parent.HUDController)
local InputController = require(script.Parent.InputController)
local MatchHUDController = require(script.Parent.MatchHUDController)
local ProfileController = require(script.Parent.ProfileController)
local TerminusController = require(script.Parent.TerminusController)

local DeployController = {}

local player = Players.LocalPlayer
local t = ProfileController.t

local screen: DeployScreen.Screen
local queueFrame: Frame
local queueTitle: TextLabel
local queueCount: TextLabel
local queueWait: TextLabel
local crossplayButton: TextButton
local cancelButton: TextButton
local inviteFrame: Frame
local queue: Types.QueueView = { status = "idle" }
local invitePrompts: { [Player]: ProximityPrompt } = {}
local pendingInvite: { userId: number, expires: number }? = nil

local function inMatch(): boolean
	local status = MatchHUDController.status()
	return status ~= "none"
end

-- Bandeau de file d'attente ---------------------------------------------------

local function buildQueueBanner(root: Instance)
	queueTitle = Panel.label("", 18, Theme.red)
	queueTitle.Font = Theme.fontTitle
	queueTitle.Size = UDim2.new(1, 0, 0, 24)
	queueTitle.TextXAlignment = Enum.TextXAlignment.Center
	queueCount = Panel.label("", 22, Theme.text)
	queueCount.Font = Theme.fontNumbers
	queueCount.Size = UDim2.new(1, 0, 0, 28)
	queueCount.TextXAlignment = Enum.TextXAlignment.Center
	queueWait = Panel.label("", 14, Theme.textDim)
	queueWait.Size = UDim2.new(1, 0, 0, 20)
	queueWait.TextXAlignment = Enum.TextXAlignment.Center
	crossplayButton = Panel.button("", Theme.cyan, 220)
	cancelButton = Panel.button("", Theme.textDim, 140)
	queueFrame = Create("Frame", {
		Name = "QueueBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(380, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = 0.1,
		Visible = false,
		ZIndex = 6,
		Parent = root,
	}, {
		Stroke = Create("UIStroke", { Color = Theme.red, Transparency = 0.3, Thickness = 2 }),
		Padding = Create("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
		}),
		Layout = Create("UIListLayout", {
			Padding = UDim.new(0, 4),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Title = queueTitle,
		Count = queueCount,
		Wait = queueWait,
		Crossplay = crossplayButton,
		Cancel = cancelButton,
	})
	queueTitle.LayoutOrder = 1
	queueCount.LayoutOrder = 2
	queueWait.LayoutOrder = 3
	crossplayButton.LayoutOrder = 4
	cancelButton.LayoutOrder = 5

	cancelButton.Activated:Connect(function()
		ClientNet.fire("QueueLeave")
	end)
	crossplayButton.Activated:Connect(function()
		if queue.status == "queued" and queue.modeId and queue.format then
			ClientNet.fire("QueueJoin", queue.modeId, queue.format, true)
		end
	end)
end

local function renderQueue()
	local status = queue.status
	queueFrame.Visible = status ~= "idle" and not inMatch()
	if status == "idle" then
		return
	end
	queueTitle.Text = if status == "teleporting"
		then t("queue.found")
		else t("queue.searching", {
			mode = t("mode." .. tostring(queue.modeId)),
			format = t("mode.format." .. tostring(queue.format)),
		})
	queueCount.Text = t("queue.players", { players = queue.players or 1, needed = queue.needed or 16 })
	local waited = math.max(0, os.time() - (queue.since or os.time()))
	queueWait.Text = t("queue.wait", { time = string.format("%d:%02d", math.floor(waited / 60), waited % 60) })
		.. if queue.group == "crossplay" then "  ·  " .. t("deploy.crossplay") else ""
	crossplayButton.Visible = status == "queued" and queue.suggestCrossplay == true
	crossplayButton.Text = t("queue.switchCrossplay")
	cancelButton.Visible = status == "queued"
	cancelButton.Text = t("queue.cancel")
end

-- Invitations duo ----------------------------------------------------------------

local function buildInviteToast(root: Instance)
	inviteFrame = Create("Frame", {
		Name = "PartyInvite",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 120),
		Size = UDim2.fromOffset(340, 120),
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 12,
		Parent = root,
	}, {
		Stroke = Create("UIStroke", { Color = Theme.magenta, Transparency = 0.3, Thickness = 2 }),
		Message = Create("TextLabel", {
			Position = UDim2.fromOffset(12, 8),
			Size = UDim2.new(1, -24, 0, 52),
			BackgroundTransparency = 1,
			Font = Theme.fontText,
			TextSize = 16,
			TextWrapped = true,
			TextColor3 = Theme.text,
			Text = "",
		}),
		Buttons = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -24, 0, Theme.minButtonSize),
			BackgroundTransparency = 1,
		}, {
			Layout = Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 10),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
			}),
		}),
	})
	local buttons = inviteFrame:FindFirstChild("Buttons") :: Frame
	local accept = Panel.button("", Theme.green, 150)
	accept.Name = "Accept"
	accept.Parent = buttons
	local decline = Panel.button("", Theme.textDim, 150)
	decline.Name = "Decline"
	decline.Parent = buttons
	local function answer(value: boolean)
		local invite = pendingInvite
		pendingInvite = nil
		inviteFrame.Visible = false
		if invite then
			ClientNet.fire("PartyRespond", invite.userId, value)
		end
	end
	accept.Activated:Connect(function()
		answer(true)
	end)
	decline.Activated:Connect(function()
		answer(false)
	end)
end

local function showInvite(userId: number, name: string)
	if inMatch() then
		ClientNet.fire("PartyRespond", userId, false)
		return
	end
	pendingInvite = { userId = userId, expires = os.clock() + Config.Matchmaking.party.inviteTimeout }
	local message = inviteFrame:FindFirstChild("Message") :: TextLabel
	message.Text = t("party.invited", { name = name })
	local buttons = inviteFrame:FindFirstChild("Buttons") :: Frame
	(buttons:FindFirstChild("Accept") :: TextButton).Text = t("party.accept");
	(buttons:FindFirstChild("Decline") :: TextButton).Text = t("party.decline")
	inviteFrame.Visible = true
end

-- Invite « Inviter en duo » sur les autres joueurs (locale à ce client).
local function attachInvitePrompt(other: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local existing = invitePrompts[other]
	if existing then
		existing:Destroy()
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PartyInvitePrompt"
	prompt.ActionText = t("party.invitePrompt")
	prompt.ObjectText = other.DisplayName
	prompt.KeyboardKeyCode = Enum.KeyCode.G
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = not inMatch()
	prompt:SetAttribute("ActionKey", "party.invitePrompt")
	prompt:SetAttribute("PartyInviteUserId", other.UserId)
	prompt.Parent = root
	invitePrompts[other] = prompt
end

local function watchPlayer(other: Player)
	if other == player then
		return
	end
	other.CharacterAdded:Connect(function(character)
		attachInvitePrompt(other, character)
	end)
	if other.Character then
		task.spawn(attachInvitePrompt, other, other.Character)
	end
end

local function refreshPrompts()
	local enabled = not inMatch()
	for _, prompt in invitePrompts do
		prompt.Enabled = enabled
	end
end

-- Plateforme : déclarée au serveur quand le périphérique principal change.
local lastPlatform: string? = nil
local platformDirty = false
local function reportPlatform()
	local device = InputController.device()
	screen.setPlatform(device)
	if device ~= lastPlatform then
		lastPlatform = device
		platformDirty = true
	end
end

function DeployController.init() end

function DeployController.start()
	local root = HUDController.root()
	screen = DeployScreen.create(root, t)
	TerminusController.register("deploy", screen)
	buildQueueBanner(root)
	buildInviteToast(root)

	ClientNet.on("QueueState", function(state: Types.QueueView?)
		queue = if type(state) == "table" then state else { status = "idle" }
		renderQueue()
	end)
	ClientNet.on("PartyState", function(party: Types.PartyView?)
		screen.setParty(if type(party) == "table" then party else nil)
	end)
	ClientNet.on("PartyInviteReceived", function(userId: number, name: string)
		if type(userId) == "number" and type(name) == "string" then
			showInvite(userId, name)
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local userId = prompt:GetAttribute("PartyInviteUserId")
		if type(userId) == "number" and not inMatch() then
			ClientNet.fire("PartyInvite", userId)
		end
	end)
	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(other)
		local prompt = invitePrompts[other]
		if prompt then
			prompt:Destroy()
		end
		invitePrompts[other] = nil
	end)

	MatchHUDController.StatusChanged:Connect(function()
		refreshPrompts()
		renderQueue()
		if inMatch() then
			screen.panel:close()
			inviteFrame.Visible = false
			pendingInvite = nil
		end
	end)

	InputController.DeviceChanged:Connect(reportPlatform)
	reportPlatform()
	-- Envoi regroupé (au plus une fois toutes les 2 s) : le périphérique peut
	-- changer à chaque mouvement de souris / manette.
	task.spawn(function()
		while true do
			if platformDirty and lastPlatform then
				platformDirty = false
				ClientNet.fire("SetPlatform", lastPlatform)
			end
			task.wait(2)
		end
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.5 then
			return
		end
		accumulator = 0
		if queue.status ~= "idle" then
			renderQueue()
		end
		local invite = pendingInvite
		if invite and os.clock() > invite.expires then
			pendingInvite = nil
			inviteFrame.Visible = false
		end
	end)
end

return DeployController
