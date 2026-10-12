--!strict
--[[
	Panel : panneau plein écran / centré, réutilisable (Terminus, menus).

	- Titre (police techno), bouton fermer (44 px), contour néon de la couleur
	  d'accent, léger « glitch » d'ouverture (section 17.1).
	- Enregistré dans PanelState : souris libérée, combat bloqué.
	- Sélection automatique du premier bouton à la manette.
]]

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local Create = require(script.Parent.Create)
local PanelState = require(script.Parent.PanelState)
local Flicker = require(script.Parent.Flicker)
local Sounds = require(script.Parent.Sounds)
local Theme = require(script.Parent.Theme)

local RUST = Color3.fromRGB(150, 84, 40)
local RIVET = Color3.fromRGB(110, 116, 126)
local TAPE = Color3.fromRGB(214, 196, 150)

-- Décor « sali » (17.1) : lignes de balayage CRT, rivets, ruban adhésif,
-- coin fissuré. Purement décoratif : ne capte aucune entrée, toujours
-- sous le contenu, et très discret (la lisibilité passe avant tout).
local function decorate(frame: Frame)
	local scanlines = Create("Frame", {
		Name = "Scanlines",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 0,
		Parent = frame,
	})
	for index = 1, 28 do
		Create("Frame", {
			Position = UDim2.fromScale(0, (index - 0.5) / 28),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.965,
			BorderSizePixel = 0,
			ZIndex = 0,
			Parent = scanlines,
		})
	end
	for index, corner in { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) } do
		Create("Frame", {
			Name = "Rivet" .. index,
			AnchorPoint = corner,
			Position = UDim2.new(corner.X, if corner.X == 0 then 6 else -6, corner.Y, if corner.Y == 0 then 6 else -6),
			Size = UDim2.fromOffset(6, 6),
			BackgroundColor3 = RIVET,
			BorderSizePixel = 0,
			ZIndex = 0,
			Parent = frame,
		}, { Corner = Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	end
	Create("Frame", {
		Name = "Tape",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(6, 4),
		Size = UDim2.fromOffset(46, 12),
		Rotation = -32,
		BackgroundColor3 = TAPE,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = frame,
	})
	for index, crack in { { 0, 22, 40 }, { 14, 12, -25 }, { -6, 34, 70 } } do
		Create("Frame", {
			Name = "Crack" .. index,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -8 + crack[1], 1, -8),
			Size = UDim2.fromOffset(1, crack[2]),
			Rotation = crack[3],
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.8,
			BorderSizePixel = 0,
			ZIndex = 0,
			Parent = frame,
		})
	end
end

export type Panel = {
	name: string,
	frame: Frame,
	title: TextLabel,
	body: Frame,
	footer: Frame,
	isOpen: (self: Panel) -> boolean,
	open: (self: Panel) -> (),
	close: (self: Panel) -> (),
	onClosed: (() -> ())?,
}

local Panel = {}

function Panel.create(name: string, parent: Instance, accent: Color3?): Panel
	local color = accent or Theme.cyan
	local title = Create("TextLabel", {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -80, 0, 30),
		BackgroundTransparency = 1,
		Font = Theme.fontTitle,
		TextSize = 24,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
	local close = Create("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 6),
		Size = UDim2.fromOffset(Theme.minButtonSize, Theme.minButtonSize),
		BackgroundTransparency = 1,
		Font = Theme.fontTitle,
		TextSize = 24,
		TextColor3 = Theme.textDim,
		Text = "✕",
	})
	local body = Create("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(16, 50),
		Size = UDim2.new(1, -32, 1, -110),
		BackgroundTransparency = 1,
	})
	local footer = Create("Frame", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -10),
		Size = UDim2.new(1, -32, 0, 48),
		BackgroundTransparency = 1,
	}, {
		Layout = Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local frame = Create("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.92, 0.86),
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = 0.04,
		Visible = false,
		ZIndex = 8,
		Parent = parent,
	}, {
		Stroke = Create("UIStroke", { Color = color, Transparency = 0.35, Thickness = 2 }, {
			-- Bordure usée : la couleur d'accent tire sur la rouille par endroits.
			Rust = Create("UIGradient", {
				Rotation = 35,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, color),
					ColorSequenceKeypoint.new(0.45, color),
					ColorSequenceKeypoint.new(0.6, RUST),
					ColorSequenceKeypoint.new(0.75, color),
					ColorSequenceKeypoint.new(1, RUST),
				}),
			}),
		}),
		SizeLimit = Create("UISizeConstraint", { MaxSize = Vector2.new(1100, 760) }),
		Title = title,
		Close = close,
		Body = body,
		Footer = footer,
	})

	decorate(frame)
	Flicker.attach(title)

	local panel = {} :: any
	panel.name = name
	panel.frame = frame
	panel.title = title
	panel.body = body
	panel.footer = footer
	panel.onClosed = nil

	function panel:isOpen(): boolean
		return frame.Visible
	end

	function panel:open()
		frame.Visible = true
		PanelState.set(name, true)
		-- Ouverture courte (0,2 s) avec un léger glitch de transparence.
		frame.BackgroundTransparency = 0.6
		TweenService:Create(frame, TweenInfo.new(0.2), { BackgroundTransparency = 0.04 }):Play()
		task.defer(function()
			if GuiService.SelectedObject == nil then
				local first = body:FindFirstChildWhichIsA("GuiButton", true)
				if first and game:GetService("UserInputService").GamepadEnabled then
					GuiService.SelectedObject = first
				end
			end
		end)
	end

	function panel:close()
		if not frame.Visible then
			return
		end
		frame.Visible = false
		PanelState.set(name, false)
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(frame) then
			GuiService.SelectedObject = nil
		end
		local callback = panel.onClosed
		if callback then
			callback()
		end
	end

	close.Activated:Connect(function()
		panel:close()
	end)
	return panel :: Panel
end

-- Bouton standard (≥ 44 px), avec couleur d'accent.
function Panel.button(text: string, color: Color3?, width: number?): TextButton
	local accent = color or Theme.cyan
	local button = Create("TextButton", {
		Size = UDim2.fromOffset(width or 160, Theme.minButtonSize),
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = 0.05,
		AutoButtonColor = true,
		Font = Theme.fontTitle,
		TextSize = 15,
		TextColor3 = accent,
		Text = text,
	}, {
		Stroke = Create("UIStroke", { Color = accent, Transparency = 0.4 }),
	})
	button.Activated:Connect(Sounds.click)
	return button
end

-- Liste défilante verticale.
function Panel.list(name: string): ScrollingFrame
	return Create("ScrollingFrame", {
		Name = name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, {
		Layout = Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
end

-- Vide un conteneur (sauf les éléments de mise en page).
function Panel.clear(container: Instance)
	for _, child in container:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIGridLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

-- Texte simple.
function Panel.label(text: string, size: number?, color: Color3?): TextLabel
	return Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, (size or 15) + 8),
		BackgroundTransparency = 1,
		Font = Theme.fontText,
		TextSize = size or 15,
		TextColor3 = color or Theme.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Text = text,
	})
end

return Panel
