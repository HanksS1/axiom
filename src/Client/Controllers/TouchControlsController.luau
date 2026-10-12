--!strict
--[[
	TouchControlsController : commandes tactiles (sections 5.3 et 17.3, écran 12).

	- Joystick de déplacement flottant à gauche : celui de Roblox (dynamique).
	- À droite : grand bouton de tir (on peut glisser dessus pour viser en
	  tirant), visée, parade, accroupi/couché (appui court / long),
	  changement d'arme, recharge, sprint. Le saut reste le bouton Roblox.
	- Opacité réglable (paramètre `mobileButtonOpacity`). La disposition
	  personnalisable arrive avec l'écran des paramètres (P8).

	Les boutons ne s'affichent que lorsque le dernier périphérique utilisé
	est l'écran tactile.
]]

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Create = require(script.Parent.Parent.UI.Create)
local Theme = require(script.Parent.Parent.UI.Theme)
local CameraController = require(script.Parent.CameraController)
local HUDController = require(script.Parent.HUDController)
local InputController = require(script.Parent.InputController)
local ProfileController = require(script.Parent.ProfileController)

local TouchControlsController = {}

type ButtonSpec = {
	action: InputController.Action,
	label: string,
	size: number,
	position: UDim2, -- depuis le coin inférieur droit
	color: Color3,
	toggle: boolean?, -- l'action est une bascule gérée par le contrôleur concerné
	dragToLook: boolean?,
}

local BUTTONS: { ButtonSpec } = {
	{
		action = "fire",
		label = "touch.fire",
		size = 104,
		position = UDim2.new(1, -150, 1, -210),
		color = Theme.red,
		dragToLook = true,
	},
	{ action = "aim", label = "touch.aim", size = 64, position = UDim2.new(1, -270, 1, -190), color = Theme.cyan },
	{ action = "parry", label = "touch.parry", size = 64, position = UDim2.new(1, -250, 1, -275), color = Theme.cyan },
	{ action = "reload", label = "touch.reload", size = 56, position = UDim2.new(1, -60, 1, -290), color = Theme.text },
	{
		action = "switch",
		label = "touch.switch",
		size = 56,
		position = UDim2.new(1, -130, 1, -320),
		color = Theme.text,
	},
	{ action = "crouch", label = "touch.crouch", size = 56, position = UDim2.new(1, -60, 1, -220), color = Theme.text },
	{
		action = "sprint",
		label = "touch.sprint",
		size = 56,
		position = UDim2.new(1, -330, 1, -110),
		color = Theme.orange,
	},
	-- Rangée compacte : soins, batterie, Surcharge, sac.
	{ action = "heal", label = "touch.heal", size = 48, position = UDim2.new(1, -250, 1, -380), color = Theme.green },
	{
		action = "battery",
		label = "touch.battery",
		size = 48,
		position = UDim2.new(1, -190, 1, -380),
		color = Theme.cyan,
	},
	{
		action = "boost",
		label = "touch.boost",
		size = 48,
		position = UDim2.new(1, -130, 1, -380),
		color = Theme.orange,
	},
	{
		action = "inventory",
		label = "touch.inventory",
		size = 48,
		position = UDim2.new(1, -60, 1, -380),
		color = Theme.text,
	},
	-- Gadgets et ping.
	{
		action = "gadget1",
		label = "touch.gadget1",
		size = 48,
		position = UDim2.new(1, -250, 1, -440),
		color = Theme.magenta,
	},
	{
		action = "gadget2",
		label = "touch.gadget2",
		size = 48,
		position = UDim2.new(1, -190, 1, -440),
		color = Theme.magenta,
	},
	{ action = "ping", label = "touch.ping", size = 48, position = UDim2.new(1, -130, 1, -440), color = Theme.cyan },
}

local container: Frame
local labels: { [TextLabel]: string } = {}
local buttons: { { button: TextButton, stroke: UIStroke, label: TextLabel, spec: ButtonSpec } } = {}

-- Hauteur d'écran de référence pour laquelle la disposition a été conçue.
local REFERENCE_HEIGHT = 480
local opacity = 0.8

local function createButton(spec: ButtonSpec): TextButton
	local label = Create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Theme.fontTitle,
		TextSize = math.floor(spec.size / 5),
		TextColor3 = spec.color,
		Text = ProfileController.t(spec.label),
	})
	labels[label] = spec.label
	local button = Create("TextButton", {
		Name = spec.action,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = spec.position,
		Size = UDim2.fromOffset(spec.size, spec.size),
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = 0.35,
		AutoButtonColor = false,
		Text = "",
		Parent = container,
	}, {
		Corner = Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Stroke = Create("UIStroke", { Color = spec.color, Thickness = 2, Transparency = 0.2 }),
		Label = label,
	})
	table.insert(
		buttons,
		{ button = button, stroke = button:FindFirstChild("Stroke") :: UIStroke, label = label, spec = spec }
	)

	-- Suivi du doigt posé sur le bouton (multi-touch).
	local activeTouch: InputObject? = nil
	button.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch or activeTouch ~= nil then
			return
		end
		activeTouch = input
		button.BackgroundTransparency = 1 - opacity
		InputController.press(spec.action)
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input == activeTouch and spec.dragToLook then
			CameraController.addTouchDelta(input.Delta)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input == activeTouch then
			activeTouch = nil
			button.BackgroundTransparency = 1 - opacity * 0.65
			InputController.release(spec.action)
		end
	end)
	return button
end

-- Mise à l'échelle selon la hauteur d'écran (petits téléphones en paysage),
-- sans jamais descendre sous la taille tactile minimale.
local function layout()
	local height = Workspace.CurrentCamera.ViewportSize.Y
	local scale = math.clamp(height / REFERENCE_HEIGHT, 0.6, 1.3)
	for _, entry in buttons do
		local spec = entry.spec
		local size = math.max(Theme.minButtonSize, spec.size * scale)
		entry.button.Size = UDim2.fromOffset(size, size)
		entry.button.Position = UDim2.new(
			spec.position.X.Scale,
			spec.position.X.Offset * scale,
			spec.position.Y.Scale,
			spec.position.Y.Offset * scale
		)
		entry.label.TextSize = math.floor(size / 5)
	end
end

local function refresh()
	local visible = InputController.device() == "touch"
	container.Visible = visible
	local view = ProfileController.get()
	opacity = if view and type(view.settings.mobileButtonOpacity) == "number"
		then view.settings.mobileButtonOpacity
		else 0.8
	-- Opacité appliquée bouton par bouton (un CanvasGroup plein écran coûterait
	-- une texture de la taille de l'écran sur mobile).
	for _, entry in buttons do
		entry.button.BackgroundTransparency = 1 - opacity * 0.65
		entry.stroke.Transparency = 1 - opacity
		entry.label.TextTransparency = 1 - opacity
	end
	for label, key in labels do
		label.Text = ProfileController.t(key)
	end
end

function TouchControlsController.init() end

function TouchControlsController.start()
	container = Create("Frame", {
		Name = "TouchControls",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = HUDController.root(),
	})
	for _, spec in BUTTONS do
		createButton(spec)
	end
	refresh()
	layout()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	InputController.DeviceChanged:Connect(refresh)
	ProfileController.Changed:Connect(refresh)
end

return TouchControlsController
