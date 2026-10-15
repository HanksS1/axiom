--!strict
--[[
	TouchControlsController : commandes tactiles (sections 5.3 et 17.3, écran 12).

	- Joystick de déplacement flottant à gauche : celui de Roblox (dynamique).
	- À droite : grand bouton de tir (on peut glisser dessus pour viser en
	  tirant), visée, parade, accroupi/couché (appui court / long),
	  changement d'arme, recharge, sprint. Le saut reste le bouton Roblox.
	- Opacité réglable (paramètre `mobileButtonOpacity`) et disposition
	  personnalisable (paramètre `touchLayout`) : mode édition depuis les
	  paramètres (glisser les boutons, taille, réinitialiser).

	Les boutons ne s'affichent que lorsque le dernier périphérique utilisé
	est l'écran tactile.
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local TouchLayout = require(ReplicatedStorage:WaitForChild("Shared").Input.TouchLayout)

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
	-- Rangée compacte : exo-harnais, soins, batterie, Surcharge, sac.
	{ action = "exo", label = "touch.exo", size = 48, position = UDim2.new(1, -310, 1, -380), color = Theme.magenta },
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

-- Mode édition de la disposition.
local editing = false
local draft: { [string]: TouchLayout.Placement } = {}
local selected: string? = nil
local editorFrame: Frame? = nil
local layout: () -> ()

local function savedLayout(): { [string]: TouchLayout.Placement }
	local view = ProfileController.get()
	local value = if view then view.settings.touchLayout else nil
	return if type(value) == "table" then value else {}
end

local function currentLayout(): { [string]: TouchLayout.Placement }
	return if editing then draft else savedLayout()
end

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
	local dragging: InputObject? = nil
	button.InputBegan:Connect(function(input: InputObject)
		-- Mode édition : on déplace le bouton au lieu de déclencher l'action.
		if editing then
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				dragging = input
				selected = spec.action
				layout()
			end
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Touch or activeTouch ~= nil then
			return
		end
		activeTouch = input
		button.BackgroundTransparency = 1 - opacity
		InputController.press(spec.action)
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if editing and dragging then
			local moving = input == dragging
				or (
					dragging.UserInputType == Enum.UserInputType.MouseButton1
					and input.UserInputType == Enum.UserInputType.MouseMovement
				)
			if moving then
				local viewport = Workspace.CurrentCamera.ViewportSize
				local current = draft[spec.action]
				draft[spec.action] = {
					x = math.clamp(input.Position.X / viewport.X, 0.02, 0.98),
					y = math.clamp((input.Position.Y + GuiService:GetGuiInset().Y) / viewport.Y, 0.05, 0.98),
					s = if current then current.s else 1,
				}
				layout()
			end
			return
		end
		if input == activeTouch and spec.dragToLook then
			CameraController.addTouchDelta(input.Delta)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input == dragging then
			dragging = nil
			return
		end
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
function layout()
	local height = Workspace.CurrentCamera.ViewportSize.Y
	local scale = math.clamp(height / REFERENCE_HEIGHT, 0.6, 1.3)
	local placements = currentLayout()
	for _, entry in buttons do
		local spec = entry.spec
		local placement = placements[spec.action]
		local size = math.max(Theme.minButtonSize, spec.size * scale * (if placement then placement.s else 1))
		entry.button.Size = UDim2.fromOffset(size, size)
		entry.button.Position = if placement
			then UDim2.fromScale(placement.x, placement.y)
			else UDim2.new(
				spec.position.X.Scale,
				spec.position.X.Offset * scale,
				spec.position.Y.Scale,
				spec.position.Y.Offset * scale
			)
		entry.label.TextSize = math.floor(size / 5)
		entry.stroke.Thickness = if editing and selected == spec.action then 4 else 2
	end
end

local function refresh()
	local visible = editing or InputController.device() == "touch"
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
	ProfileController.Changed:Connect(function()
		refresh()
		layout()
	end)
end

-- Taille du bouton sélectionné (mode édition).
local function resizeSelected(delta: number)
	local action = selected
	if action == nil then
		return
	end
	local current = draft[action]
	if current == nil then
		-- Position par défaut convertie en fractions d'écran.
		local entry
		for _, candidate in buttons do
			if candidate.spec.action == action then
				entry = candidate
			end
		end
		if entry == nil then
			return
		end
		local viewport = Workspace.CurrentCamera.ViewportSize
		local center = entry.button.AbsolutePosition + entry.button.AbsoluteSize / 2
		current = { x = center.X / viewport.X, y = (center.Y + GuiService:GetGuiInset().Y) / viewport.Y, s = 1 }
	end
	local placement = current :: TouchLayout.Placement
	draft[action] = {
		x = math.clamp(placement.x, 0, 1),
		y = math.clamp(placement.y, 0, 1),
		s = math.clamp(placement.s + delta, TouchLayout.minScale, TouchLayout.maxScale),
	}
	layout()
end

local function closeEditor(save: boolean, onClosed: (() -> ())?)
	if save then
		ProfileController.setSetting("touchLayout", draft)
	end
	editing = false
	selected = nil
	if editorFrame then
		editorFrame:Destroy()
		editorFrame = nil
	end
	refresh()
	layout()
	if onClosed then
		onClosed()
	end
end

-- Mode édition de la disposition (écran des paramètres).
function TouchControlsController.edit(t: (key: string) -> string, onClosed: (() -> ())?)
	if editing then
		return
	end
	editing = true
	draft = table.clone(savedLayout())
	selected = nil
	local function button(text: string, color: Color3, order: number, callback: () -> ())
		local b = Create("TextButton", {
			LayoutOrder = order,
			Size = UDim2.fromOffset(120, Theme.minButtonSize),
			BackgroundColor3 = Theme.panel,
			Font = Theme.fontTitle,
			TextSize = 16,
			TextColor3 = color,
			Text = text,
		}, { Stroke = Create("UIStroke", { Color = color, Transparency = 0.3 }) })
		b.Activated:Connect(callback)
		return b
	end
	editorFrame = Create("Frame", {
		Name = "TouchLayoutEditor",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(640, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = 0.1,
		ZIndex = 20,
		Parent = container.Parent,
	}, {
		Stroke = Create("UIStroke", { Color = Theme.cyan, Transparency = 0.3 }),
		SizeLimit = Create("UISizeConstraint", { MaxSize = Vector2.new(640, 400) }),
		Layout = Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Wraps = true,
			Padding = UDim.new(0, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Hint = Create("TextLabel", {
			LayoutOrder = 0,
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			Font = Theme.fontText,
			TextSize = 15,
			TextColor3 = Theme.text,
			Text = t("settings.layout.hint"),
		}),
		Smaller = button("−", Theme.text, 1, function()
			resizeSelected(-0.1)
		end),
		Bigger = button("+", Theme.text, 2, function()
			resizeSelected(0.1)
		end),
		Reset = button(t("settings.layout.reset"), Theme.orange, 3, function()
			draft = {}
			layout()
		end),
		Cancel = button(t("common.cancel"), Theme.textDim, 4, function()
			closeEditor(false, onClosed)
		end),
		Save = button(t("settings.save"), Theme.green, 5, function()
			closeEditor(true, onClosed)
		end),
	})
	refresh()
	layout()
end

return TouchControlsController
