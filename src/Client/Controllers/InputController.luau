--!strict
--[[
	InputController : couche d'actions indépendante du périphérique (5.3).

	Le reste du client ne lit jamais directement le clavier, la manette ou
	l'écran tactile : il écoute des ACTIONS (fire, aim, parry…). Les
	touches par défaut suivent la section 5.3 et sont personnalisables
	(paramètre `keybinds`, voir Shared/Input/Bindings), appliquées à chaud.

	Détecte aussi le périphérique principal (dernier utilisé) : "keyboard",
	"gamepad" ou "touch" — utilisé pour le crossplay, les icônes de touches
	et la visée assistée.
]]

local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Bindings = require(Shared.Input.Bindings)
local Signal = require(Shared.Util.Signal)

local ProfileController = require(script.Parent.ProfileController)

export type Action =
	"fire"
	| "aim"
	| "parry"
	| "sprint"
	| "crouch"
	| "switch"
	| "reload"
	| "weapon1"
	| "weapon2"
	| "inventory"
	| "heal"
	| "battery"
	| "boost"
	| "quickCycle"
	| "interact"
	| "ping"
	| "map"
	| "gadget1"
	| "gadget2"
export type Device = "keyboard" | "gamepad" | "touch"

local InputController = {}

InputController.ActionBegan = Signal.new() :: Signal.Signal<Action>
InputController.ActionEnded = Signal.new() :: Signal.Signal<Action>
InputController.DeviceChanged = Signal.new() :: Signal.Signal<Device>
-- Appui court (relâché avant le seuil d'appui long) / appui long (seuil atteint).
InputController.Tapped = Signal.new() :: Signal.Signal<Action>
InputController.HeldLong = Signal.new() :: Signal.Signal<Action>
-- Les touches ont changé (icônes de touches à rafraîchir).
InputController.BindingsChanged = Signal.new() :: Signal.Signal<>

local LONG_PRESS = 0.35
local pressedAt: { [Action]: number } = {}

local held: { [Action]: boolean } = {}
local device: Device = "keyboard"

-- Touches effectives (défauts + paramètre `keybinds`) et actions liées.
local resolved = Bindings.resolve(nil)
local boundNames: { string } = {}
local appliedKey = ""

-- Nom de touche → Enum (KeyCode, ou UserInputType pour la souris).
local function toEnum(name: string): EnumItem?
	if string.sub(name, 1, 11) == "MouseButton" then
		local ok, item = pcall(function()
			return (Enum.UserInputType :: any)[name]
		end)
		return if ok then item else nil
	end
	local ok, item = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	return if ok then item else nil
end

local function classify(inputType: EnumItem): Device?
	if inputType == Enum.UserInputType.Touch then
		return "touch" :: Device
	elseif string.find(inputType.Name, "Gamepad") then
		return "gamepad" :: Device
	elseif
		inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseMovement
		or inputType == Enum.UserInputType.MouseWheel
	then
		return "keyboard" :: Device
	end
	return nil
end

local function setDevice(newDevice: Device)
	if newDevice ~= device then
		device = newDevice
		InputController.DeviceChanged:Fire(device)
	end
end

-- Appui / relâchement d'une action (appelé aussi par les boutons tactiles).
function InputController.press(action: Action)
	if held[action] then
		return
	end
	held[action] = true
	local stamp = os.clock()
	pressedAt[action] = stamp
	InputController.ActionBegan:Fire(action)
	task.delay(LONG_PRESS, function()
		if held[action] and pressedAt[action] == stamp then
			pressedAt[action] = nil
			InputController.HeldLong:Fire(action)
		end
	end)
end

function InputController.release(action: Action)
	if not held[action] then
		return
	end
	held[action] = false
	if pressedAt[action] ~= nil then
		pressedAt[action] = nil
		InputController.Tapped:Fire(action)
	end
	InputController.ActionEnded:Fire(action)
end

function InputController.isHeld(action: Action): boolean
	return held[action] == true
end

function InputController.device(): Device
	return device
end

-- (Re)lie les actions aux touches du profil. Sans effet si rien n'a changé.
function InputController.applyBindings()
	local view = ProfileController.get()
	local overrides = if view and type(view.settings.keybinds) == "table" then view.settings.keybinds else {}
	local key = HttpService:JSONEncode(overrides)
	if key == appliedKey and #boundNames > 0 then
		return
	end
	appliedKey = key
	for _, name in boundNames do
		ContextActionService:UnbindAction(name)
	end
	table.clear(boundNames)
	InputController.releaseAll()
	resolved = Bindings.resolve(overrides)
	for actionName, entry in resolved do
		local action: Action = actionName :: any
		local inputs: { EnumItem } = {}
		local names: { string } = {}
		if entry.keyboard then
			table.insert(names, entry.keyboard)
		end
		if entry.gamepad then
			table.insert(names, entry.gamepad)
		end
		for _, name in names do
			local item = toEnum(name)
			if item then
				table.insert(inputs, item)
			end
		end
		local extras: { string } = Bindings.extras[actionName] or {}
		for _, name in extras do
			local item = toEnum(name)
			if item then
				table.insert(inputs, item)
			end
		end
		if #inputs == 0 then
			continue
		end
		local bindName = "Axiom_" .. actionName
		ContextActionService:BindActionAtPriority(bindName, function(_name, state, _input)
			if state == Enum.UserInputState.Begin then
				InputController.press(action)
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				InputController.release(action)
			end
			-- Les clics souris restent disponibles pour l'interface.
			return Enum.ContextActionResult.Pass
		end, false, Enum.ContextActionPriority.Default.Value, table.unpack(inputs))
		table.insert(boundNames, bindName)
	end
	InputController.BindingsChanged:Fire()
end

-- Libellé d'une touche (selon la disposition du clavier : A en AZERTY pour Q).
function InputController.keyLabel(name: string?): string
	if name == nil then
		return "—"
	end
	local key = "key." .. name
	if ProfileController.has(key) then
		return ProfileController.t(key)
	end
	local item = toEnum(name)
	if item then
		local ok, label = pcall(function()
			return UserInputService:GetStringForKeyCode(item :: any)
		end)
		if ok and type(label) == "string" and label ~= "" then
			return string.upper(label)
		end
	end
	return name
end

-- Touche d'une action pour le périphérique actuel (icônes de touches, 17.2).
function InputController.hint(action: Action): string?
	local entry = resolved[action]
	if entry == nil or device == "touch" then
		return nil
	end
	local name = if device == "gamepad" then entry.gamepad else entry.keyboard
	if name == nil then
		return nil
	end
	-- Une touche supplémentaire fixe porte la lettre du raccourci sur ce clavier
	-- (« M » en AZERTY pour la carte) : c'est elle qu'on annonce.
	if device == "keyboard" and #name == 1 then
		local extras: { string } = Bindings.extras[action] or {}
		for _, extra in extras do
			local item = toEnum(extra)
			local ok, label = pcall(function()
				return UserInputService:GetStringForKeyCode(item :: any)
			end)
			if item and ok and type(label) == "string" and string.upper(label) == name then
				return name
			end
		end
	end
	return InputController.keyLabel(name)
end

-- Libère toutes les actions (mort, ouverture d'un menu…).
function InputController.releaseAll()
	for action, isHeld in held do
		if isHeld then
			InputController.release(action :: Action)
		end
	end
end

function InputController.init()
	local initial = UserInputService:GetLastInputType()
	setDevice(
		classify(initial)
			or (
				if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "touch" else "keyboard"
			) :: Device
	)
end

function InputController.start()
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		local newDevice: Device? = classify(inputType)
		if newDevice then
			setDevice(newDevice)
		end
	end)

	InputController.applyBindings()
	ProfileController.Changed:Connect(function()
		InputController.applyBindings()
	end)

	-- Molette : changement d'arme.
	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.UserInputType == Enum.UserInputType.MouseWheel then
			InputController.ActionBegan:Fire("switch")
			InputController.ActionEnded:Fire("switch")
		end
	end)

	-- Perte du focus de la fenêtre : on relâche tout (évite le tir bloqué).
	UserInputService.WindowFocusReleased:Connect(InputController.releaseAll)
end

return InputController
