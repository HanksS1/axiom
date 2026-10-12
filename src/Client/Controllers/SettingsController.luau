--!strict
--[[
	SettingsController : écran des paramètres (section 17.3, écran 17).

	- Bouton ⚙ toujours accessible (Terminus et partie), et entrée
	  « Paramètres » du menu rapide.
	- Applique les volumes aux groupes de sons.
	- Lance l'éditeur de disposition des boutons mobiles.
]]

local ProfileController = require(script.Parent.ProfileController)
local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
local Sounds = require(script.Parent.Parent.UI.Sounds)
local Theme = require(script.Parent.Parent.UI.Theme)
local SettingsScreen = require(script.Parent.Parent.Screens.SettingsScreen)
local HUDController = require(script.Parent.HUDController)
local InputController = require(script.Parent.InputController)
local NotificationController = require(script.Parent.NotificationController)
local TerminusController = require(script.Parent.TerminusController)
local TouchControlsController = require(script.Parent.TouchControlsController)

local SettingsController = {}

local t = ProfileController.t
local screen: SettingsScreen.Screen

local VOLUMES: { [string]: string } = {
	Music = "volumeMusic",
	Effects = "volumeEffects",
	Axiom = "volumeAxiom",
	Voice = "volumeVoice",
}

local function applyVolumes()
	local view = ProfileController.get()
	if view == nil then
		return
	end
	for group, key in VOLUMES do
		local value = view.settings[key]
		if type(value) == "number" then
			Sounds.setVolume(group, value)
		end
	end
end

function SettingsController.open()
	local view = ProfileController.get()
	if view == nil then
		return
	end
	screen.render(view)
	screen.panel:open()
end

function SettingsController.init()
	Sounds.init()
end

function SettingsController.start()
	local root = HUDController.root()
	screen = SettingsScreen.create(root, t, {
		setSetting = ProfileController.setSetting,
		keyLabel = InputController.keyLabel,
		notify = function(text: string)
			NotificationController.show(text, Theme.cyan)
		end,
		editTouchLayout = function()
			screen.panel:close()
			TouchControlsController.edit(t, SettingsController.open)
		end,
		restartTutorial = function()
			screen.panel:close()
			ClientNet.fire("TutorialAction", "restart")
		end,
	})
	TerminusController.register("settings", screen)

	local gear = Create("TextButton", {
		Name = "SettingsButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 52),
		Size = UDim2.fromOffset(Theme.minButtonSize, Theme.minButtonSize),
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = 0.3,
		Font = Theme.fontTitle,
		TextSize = 22,
		TextColor3 = Theme.textDim,
		Text = "⚙",
		ZIndex = 5,
		Parent = root,
	}, {
		Corner = Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
		Stroke = Create("UIStroke", { Color = Theme.textDim, Transparency = 0.5 }),
	})
	gear.Activated:Connect(function()
		Sounds.click()
		if screen.panel:isOpen() then
			screen.panel:close()
		else
			SettingsController.open()
		end
	end)

	ProfileController.Changed:Connect(function(view)
		applyVolumes()
		if screen.panel:isOpen() then
			screen.render(view)
		end
	end)
	applyVolumes()
end

return SettingsController
