--!strict
--[[
	InputController : couche d'actions indépendante du périphérique (5.3).

	Le reste du client ne lit jamais directement le clavier, la manette ou
	l'écran tactile : il écoute des ACTIONS (fire, aim, parry…). Les
	touches par défaut suivent la section 5.3 ; elles seront
	personnalisables (paramètres, phase P8).

	Détecte aussi le périphérique principal (dernier utilisé) : "keyboard",
	"gamepad" ou "touch" — utilisé pour le crossplay, les icônes de touches
	et la visée assistée.
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)

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

local LONG_PRESS = 0.35
local pressedAt: { [Action]: number } = {}

local held: { [Action]: boolean } = {}
local device: Device = "keyboard"

-- Touches par défaut (section 5.3).
local BINDINGS: { [Action]: { EnumItem } } = {
	fire = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2 },
	aim = { Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2 },
	parry = { Enum.KeyCode.F, Enum.KeyCode.ButtonR1 },
	sprint = { Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3 },
	crouch = { Enum.KeyCode.C, Enum.KeyCode.ButtonB },
	switch = { Enum.KeyCode.ButtonY },
	reload = { Enum.KeyCode.R, Enum.KeyCode.ButtonX },
	weapon1 = { Enum.KeyCode.One },
	weapon2 = { Enum.KeyCode.Two },
	inventory = { Enum.KeyCode.Tab, Enum.KeyCode.ButtonSelect },
	heal = { Enum.KeyCode.Three },
	battery = { Enum.KeyCode.Four },
	boost = { Enum.KeyCode.Five },
	quickCycle = { Enum.KeyCode.DPadDown },
	ping = { Enum.KeyCode.T, Enum.UserInputType.MouseButton3, Enum.KeyCode.DPadUp },
	gadget1 = { Enum.KeyCode.DPadLeft },
	gadget2 = { Enum.KeyCode.DPadRight },
}

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

	for key, inputs in BINDINGS do
		local action: Action = key :: any
		ContextActionService:BindActionAtPriority("Axiom_" .. action, function(_name, state, _input)
			if state == Enum.UserInputState.Begin then
				InputController.press(action)
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				InputController.release(action)
			end
			-- Les clics souris restent disponibles pour l'interface.
			return Enum.ContextActionResult.Pass
		end, false, Enum.ContextActionPriority.Default.Value, table.unpack(inputs))
	end

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
