--!strict
--[[
	SettingsScreen : paramètres (section 17.3, écran 17).

	Onglets :
	- Commandes : sensibilités (souris, manette, tactile), visée assistée
	  (manette et mobile) et sa force, épaule de la caméra, opacité et
	  disposition des boutons mobiles ;
	- Touches : clavier/souris et manette, entièrement personnalisables
	  (une touche déjà prise est échangée) ;
	- Audio : musique, effets, voix d'AXIOM, voix ;
	- Affichage : langue, qualité graphique, crossplay par défaut, animation
	  de la caisse gratuite, refaire le tutoriel.

	Les valeurs sont envoyées au serveur (validées) après un court délai,
	pour ne pas saturer la limite de fréquence en manipulant un curseur.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Bindings = require(Shared.Input.Bindings)
local Config = require(Shared.Config)
local Types = require(Shared.Types)

local Create = require(script.Parent.Parent.UI.Create)
local Panel = require(script.Parent.Parent.UI.Panel)
local Theme = require(script.Parent.Parent.UI.Theme)

type Translate = (key: string, params: { [string]: any }?) -> string

local SettingsScreen = {}

export type Hooks = {
	setSetting: (key: string, value: any) -> (),
	keyLabel: (name: string?) -> string,
	notify: (text: string) -> (),
	editTouchLayout: () -> (),
}

export type Screen = {
	panel: Panel.Panel,
	render: (view: Types.ProfileView) -> (),
}

local TABS = { "controls", "keys", "audio", "display" }
local SEND_DELAY = 0.35

-- Pas des curseurs, par paramètre.
local STEPS: { [string]: number } = {
	mouseSensitivity = 0.1,
	gamepadSensitivity = 0.1,
	touchSensitivity = 0.1,
	aimAssistStrength = 0.1,
	mobileButtonOpacity = 0.1,
	volumeMusic = 0.1,
	volumeEffects = 0.1,
	volumeAxiom = 0.1,
	volumeVoice = 0.1,
}

local ROWS: { [string]: { string } } = {
	controls = {
		"mouseSensitivity",
		"gamepadSensitivity",
		"touchSensitivity",
		"aimAssist",
		"aimAssistStrength",
		"cameraShoulder",
		"mobileButtonOpacity",
	},
	audio = { "volumeMusic", "volumeEffects", "volumeAxiom", "volumeVoice" },
	display = { "language", "graphicsQuality", "crossplay", "skipCrateAnimation" },
}

function SettingsScreen.create(parent: Instance, t: Translate, hooks: Hooks): Screen
	local panel = Panel.create("SettingsScreen", parent, Theme.cyan)
	local tab = "controls"
	local current: Types.ProfileView? = nil
	local pending: { [string]: any } = {}
	local sendTokens: { [string]: number } = {}
	local capture: { action: string, slot: Bindings.Slot }? = nil

	local tabs = Panel.list("Tabs")
	tabs.Size = UDim2.new(1, 0, 0, 48)
	tabs.ScrollingEnabled = false
	(tabs:FindFirstChildOfClass("UIListLayout") :: UIListLayout).FillDirection = Enum.FillDirection.Horizontal
	tabs.Parent = panel.body
	local list = Panel.list("Rows")
	list.Position = UDim2.fromOffset(0, 54)
	list.Size = UDim2.new(1, 0, 1, -54)
	list.Parent = panel.body

	local render: (view: Types.ProfileView) -> ()

	local function rerender()
		local view = current
		if view then
			render(view)
		end
	end

	local function valueOf(key: string): any
		if pending[key] ~= nil then
			return pending[key]
		end
		local view = current
		local value = if view then view.settings[key] else nil
		if value == nil then
			value = Config.Settings[key].default
		end
		return value
	end

	-- Envoi différé (le dernier changement gagne).
	local function change(key: string, value: any)
		pending[key] = value
		local token = (sendTokens[key] or 0) + 1
		sendTokens[key] = token
		task.delay(SEND_DELAY, function()
			if sendTokens[key] == token then
				hooks.setSetting(key, value)
				pending[key] = nil
			end
		end)
		rerender()
	end

	local function rowFrame(order: number, labelText: string): Frame
		return Create("Frame", {
			LayoutOrder = order,
			Size = UDim2.new(1, -8, 0, Theme.minButtonSize + 4),
			BackgroundTransparency = 1,
			Parent = list,
		}, {
			Label = Create("TextLabel", {
				Size = UDim2.new(0.38, 0, 1, 0),
				BackgroundTransparency = 1,
				Font = Theme.fontText,
				TextSize = 16,
				TextColor3 = Theme.text,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				Text = labelText,
			}),
			Controls = Create("Frame", {
				Position = UDim2.fromScale(0.4, 0),
				Size = UDim2.new(0.6, 0, 1, 0),
				BackgroundTransparency = 1,
			}, {
				Layout = Create("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 6),
					VerticalAlignment = Enum.VerticalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			}),
		})
	end

	local function controlsOf(row: Frame): Frame
		return row:FindFirstChild("Controls") :: Frame
	end

	-- Curseur : [−] barre [+] valeur.
	local function slider(order: number, key: string)
		local def = Config.Settings[key]
		local minimum, maximum = def.min :: number, def.max :: number
		local step = STEPS[key] or 0.1
		local value = valueOf(key) :: number
		local row = rowFrame(order, t("settings." .. key))
		local controls = controlsOf(row)
		local function set(newValue: number)
			local snapped = math.floor(newValue / step + 0.5) * step
			change(key, math.clamp(snapped, minimum, maximum))
		end
		local minus = Panel.button("−", Theme.text, Theme.minButtonSize)
		minus.LayoutOrder = 1
		minus.Parent = controls
		minus.Activated:Connect(function()
			set((valueOf(key) :: number) - step)
		end)
		local bar = Create("TextButton", {
			LayoutOrder = 2,
			Size = UDim2.new(0.5, 0, 0, 12),
			BackgroundColor3 = Theme.background,
			AutoButtonColor = false,
			Text = "",
			Parent = controls,
		}, {
			Fill = Create("Frame", {
				Size = UDim2.fromScale((value - minimum) / (maximum - minimum), 1),
				BackgroundColor3 = Theme.cyan,
				BorderSizePixel = 0,
			}),
		})
		bar.InputBegan:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				local ratio = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
				set(minimum + ratio * (maximum - minimum))
			end
		end)
		local plus = Panel.button("+", Theme.text, Theme.minButtonSize)
		plus.LayoutOrder = 3
		plus.Parent = controls
		plus.Activated:Connect(function()
			set((valueOf(key) :: number) + step)
		end)
		Create("TextLabel", {
			LayoutOrder = 4,
			Size = UDim2.fromOffset(56, 30),
			BackgroundTransparency = 1,
			Font = Theme.fontNumbers,
			TextSize = 16,
			TextColor3 = Theme.text,
			Text = string.format("%.1f", value),
			Parent = controls,
		})
	end

	local function toggle(order: number, key: string)
		local value = valueOf(key) == true
		local row = rowFrame(order, t("settings." .. key))
		local button = Panel.button(
			if value then t("settings.on") else t("settings.off"),
			if value then Theme.green else Theme.textDim,
			140
		)
		button.Parent = controlsOf(row)
		button.Activated:Connect(function()
			change(key, not (valueOf(key) == true))
		end)
	end

	local function choice(order: number, key: string)
		local def = Config.Settings[key]
		local value = valueOf(key)
		local row = rowFrame(order, t("settings." .. key))
		for index, option in def.values :: { string } do
			local active = option == value
			local button =
				Panel.button(t(`settings.choice.{key}.{option}`), if active then Theme.cyan else Theme.textDim, 110)
			button.LayoutOrder = index
			button.Parent = controlsOf(row)
			button.Activated:Connect(function()
				change(key, option)
			end)
		end
	end

	local function renderSettings(keys: { string })
		for index, key in keys do
			local def = Config.Settings[key]
			if def.kind == "number" then
				slider(index, key)
			elseif def.kind == "boolean" then
				toggle(index, key)
			elseif def.kind == "enum" then
				choice(index, key)
			end
		end
	end

	local function renderKeys(view: Types.ProfileView)
		local overrides = if type(view.settings.keybinds) == "table" then view.settings.keybinds else {}
		local resolved = Bindings.resolve(overrides)
		local header = rowFrame(0, "")
		for index, key in { "settings.keys.keyboard", "settings.keys.gamepad" } do
			local label = Panel.label(t(key), 14, Theme.textDim)
			label.LayoutOrder = index
			label.Size = UDim2.fromOffset(150, 30)
			label.Parent = controlsOf(header)
		end
		for index, action in Bindings.actions do
			local row = rowFrame(index, t("action." .. action))
			for slotIndex, slot in { "keyboard", "gamepad" } :: { Bindings.Slot } do
				local waiting = capture ~= nil and capture.action == action and capture.slot == slot
				local name = (resolved[action] :: any)[slot]
				local button = Panel.button(
					if waiting then "…" else hooks.keyLabel(name),
					if waiting then Theme.orange else Theme.cyan,
					150
				)
				button.LayoutOrder = slotIndex
				button.Parent = controlsOf(row)
				button.Activated:Connect(function()
					capture = { action = action, slot = slot :: Bindings.Slot }
					hooks.notify(t("settings.keys.press"))
					rerender()
				end)
			end
		end
		local reset = Panel.button(t("settings.keys.reset"), Theme.orange, 240)
		reset.LayoutOrder = #Bindings.actions + 1
		reset.Parent = list
		reset.Activated:Connect(function()
			capture = nil
			hooks.setSetting("keybinds", {})
		end)
	end

	function render(view: Types.ProfileView)
		current = view
		panel.title.Text = t("settings.title")
		Panel.clear(tabs)
		Panel.clear(list)
		for index, key in TABS do
			local button =
				Panel.button(t("settings.tab." .. key), if tab == key then Theme.cyan else Theme.textDim, 150)
			button.LayoutOrder = index
			button.Parent = tabs
			button.Activated:Connect(function()
				tab = key
				capture = nil
				render(view)
			end)
		end
		if tab == "keys" then
			renderKeys(view)
			return
		end
		renderSettings(ROWS[tab])
		if tab == "controls" then
			local layoutButton = Panel.button(t("settings.layout.button"), Theme.magenta, 300)
			layoutButton.LayoutOrder = 100
			layoutButton.Parent = list
			layoutButton.Activated:Connect(hooks.editTouchLayout)
		elseif tab == "audio" then
			local note = Panel.label(t("settings.voiceNote"), 14, Theme.textDim)
			note.LayoutOrder = 100
			note.Parent = list
		elseif tab == "display" then
			local tutorial = Panel.button(t("settings.tutorial"), Theme.textDim, 300)
			tutorial.LayoutOrder = 100
			tutorial.AutoButtonColor = false
			tutorial.Parent = list
			tutorial.Activated:Connect(function()
				hooks.notify(t("settings.tutorial.soon"))
			end)
		end
	end

	-- Capture de la prochaine touche (onglet Touches).
	UserInputService.InputBegan:Connect(function(input: InputObject)
		local waiting = capture
		local view = current
		if waiting == nil or view == nil or not panel:isOpen() then
			return
		end
		local name: string? = nil
		local inputType = input.UserInputType
		if waiting.slot == "keyboard" then
			if inputType == Enum.UserInputType.Keyboard then
				if input.KeyCode == Enum.KeyCode.Escape then
					capture = nil
					rerender()
					return
				end
				name = if input.KeyCode == Enum.KeyCode.Backspace then Bindings.NONE else input.KeyCode.Name
			elseif
				inputType == Enum.UserInputType.MouseButton1
				or inputType == Enum.UserInputType.MouseButton2
				or inputType == Enum.UserInputType.MouseButton3
			then
				name = inputType.Name
			end
		elseif string.find(inputType.Name, "Gamepad") then
			if input.KeyCode == Enum.KeyCode.ButtonStart then
				capture = nil
				rerender()
				return
			end
			if string.find(input.KeyCode.Name, "Thumbstick") == nil then
				name = input.KeyCode.Name
			end
		end
		if name == nil then
			return
		end
		if not Bindings.isAllowed(waiting.slot, name) then
			hooks.notify(t("settings.keys.refused"))
			return
		end
		capture = nil
		local overrides = if type(view.settings.keybinds) == "table" then view.settings.keybinds else {}
		hooks.setSetting("keybinds", Bindings.assign(overrides, waiting.action, waiting.slot, name))
		rerender()
	end)

	panel.onClosed = function()
		capture = nil
	end

	return { panel = panel, render = render }
end

return SettingsScreen
