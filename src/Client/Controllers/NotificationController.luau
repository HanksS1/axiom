--!strict
--[[
	NotificationController : messages courts du serveur (clé + paramètres,
	traduits dans la langue du joueur) et textes des invites d'interaction.
]]

local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
local Theme = require(script.Parent.Parent.UI.Theme)
local HUDController = require(script.Parent.HUDController)
local ProfileController = require(script.Parent.ProfileController)

local NotificationController = {}

local stack: Frame

function NotificationController.show(text: string, color: Color3?)
	local label = Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = 0.2,
		Font = Theme.fontText,
		TextSize = 16,
		TextColor3 = color or Theme.text,
		Text = text,
		Parent = stack,
	}, {
		Stroke = Create("UIStroke", { Color = color or Theme.cyan, Transparency = 0.5 }),
	})
	task.delay(2.2, function()
		local tween =
			TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1, BackgroundTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		label:Destroy()
	end)
	-- Au plus 4 messages à l'écran.
	local labels = {}
	for _, child in stack:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(labels, child)
		end
	end
	if #labels > 4 then
		labels[1]:Destroy()
	end
end

-- Traduit une invite (Ouvrir / Fouiller / Ramasser…) dans la langue du joueur.
local function localizePrompt(prompt: ProximityPrompt)
	local actionKey = prompt:GetAttribute("ActionKey")
	local objectKey = prompt:GetAttribute("ObjectKey")
	if type(actionKey) == "string" then
		prompt.ActionText = ProfileController.t(actionKey)
	end
	if type(objectKey) == "string" then
		prompt.ObjectText = ProfileController.t(objectKey)
	end
end

function NotificationController.init() end

function NotificationController.start()
	stack = Create("Frame", {
		Name = "Notifications",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(420, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = HUDController.root(),
	}, {
		Layout = Create(
			"UIListLayout",
			{ Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center }
		),
	})

	ClientNet.on("Notify", function(key: string, params: { [string]: any }?)
		if type(key) == "string" then
			NotificationController.show(ProfileController.t(key, if type(params) == "table" then params else nil))
		end
	end)

	local watched: { [ProximityPrompt]: boolean } = {}
	ProximityPromptService.PromptShown:Connect(function(prompt)
		localizePrompt(prompt)
		if watched[prompt] then
			return
		end
		watched[prompt] = true
		-- La clé peut changer (caisse ouverte → « Fouiller ») : le serveur
		-- réécrit alors le texte brut, on le retraduit.
		prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
			if prompt.ActionText == prompt:GetAttribute("ActionKey") then
				localizePrompt(prompt)
			end
		end)
		prompt.Destroying:Connect(function()
			watched[prompt] = nil
		end)
	end)
end

return NotificationController
