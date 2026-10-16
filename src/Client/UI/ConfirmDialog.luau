--!strict
--[[
	ConfirmDialog : confirmation obligatoire (achats / ventes au-delà de
	1 000 crédits, objet jeté définitivement…).
]]

local ClickShield = require(script.Parent.ClickShield)
local Create = require(script.Parent.Create)
local Panel = require(script.Parent.Panel)
local PanelState = require(script.Parent.PanelState)
local Theme = require(script.Parent.Theme)

local ConfirmDialog = {}

local dialog: Frame? = nil
local closeCurrent: (() -> ())? = nil

function ConfirmDialog.ask(
	parent: Instance,
	message: string,
	confirmText: string,
	cancelText: string,
	onConfirm: () -> ()
)
	if closeCurrent then
		closeCurrent()
	end
	local confirm = Panel.button(confirmText, Theme.green, 160)
	local cancel = Panel.button(cancelText, Theme.textDim, 160)
	local frame = Create("Frame", {
		Name = "ConfirmDialog",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 170),
		BackgroundColor3 = Theme.panel,
		ZIndex = 30,
		Parent = parent,
	}, {
		Stroke = Create("UIStroke", { Color = Theme.orange, Thickness = 2 }),
		Message = Create("TextLabel", {
			Position = UDim2.fromOffset(16, 14),
			Size = UDim2.new(1, -32, 0, 80),
			BackgroundTransparency = 1,
			Font = Theme.fontText,
			TextSize = 17,
			TextColor3 = Theme.text,
			TextWrapped = true,
			Text = message,
			ZIndex = 31,
		}),
		Buttons = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -14),
			Size = UDim2.fromOffset(340, 44),
			BackgroundTransparency = 1,
			ZIndex = 31,
		}, {
			Layout = Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 16),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
			}),
			Confirm = confirm,
			Cancel = cancel,
		}),
	})
	dialog = frame
	-- Rien n'est cliquable à travers la question (le bouclier disparaît avec elle).
	ClickShield.attach(frame)
	PanelState.set("confirm", true)
	local function close()
		frame:Destroy()
		if dialog == frame then
			dialog = nil
			closeCurrent = nil
		end
		PanelState.set("confirm", false)
	end
	closeCurrent = close
	confirm.Activated:Connect(function()
		close()
		onConfirm()
	end)
	cancel.Activated:Connect(close)
end

-- Ferme la confirmation affichée, sans confirmer (départ en partie).
function ConfirmDialog.dismiss()
	if closeCurrent then
		closeCurrent()
	end
end

return ConfirmDialog
