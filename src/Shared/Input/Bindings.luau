--!strict
--[[
	Bindings : touches des actions (section 5.3), entièrement personnalisables.

	Chaque action a une touche clavier/souris et une touche manette. Le
	profil ne stocke que les DIFFÉRENCES avec les touches par défaut
	(paramètre `keybinds`), validées par le serveur. Une touche déjà prise
	par une autre action est échangée (jamais deux actions sur la même touche).

	Module pur : les touches sont des noms d'Enum.KeyCode / UserInputType,
	convertis côté client.
]]

local Bindings = {}

export type Slot = "keyboard" | "gamepad"
export type Binding = { keyboard: string?, gamepad: string? }
export type Overrides = { [string]: Binding }

-- Actions personnalisables, dans l'ordre d'affichage.
Bindings.actions = {
	"fire",
	"aim",
	"parry",
	"sprint",
	"crouch",
	"reload",
	"switch",
	"weapon1",
	"weapon2",
	"gadget1",
	"gadget2",
	"heal",
	"battery",
	"boost",
	"quickCycle",
	"ping",
	"inventory",
}

-- Touches par défaut (section 5.3). E / Q = positions physiques (A en AZERTY).
Bindings.defaults = {
	fire = { keyboard = "MouseButton1", gamepad = "ButtonR2" },
	aim = { keyboard = "MouseButton2", gamepad = "ButtonL2" },
	parry = { keyboard = "F", gamepad = "ButtonR1" },
	sprint = { keyboard = "LeftShift", gamepad = "ButtonL3" },
	crouch = { keyboard = "C", gamepad = "ButtonB" },
	reload = { keyboard = "R", gamepad = "ButtonX" },
	switch = { keyboard = nil, gamepad = "ButtonY" },
	weapon1 = { keyboard = "One", gamepad = nil },
	weapon2 = { keyboard = "Two", gamepad = nil },
	gadget1 = { keyboard = "E", gamepad = "DPadLeft" },
	gadget2 = { keyboard = "Q", gamepad = "DPadRight" },
	heal = { keyboard = "Three", gamepad = nil },
	battery = { keyboard = "Four", gamepad = nil },
	boost = { keyboard = "Five", gamepad = nil },
	quickCycle = { keyboard = nil, gamepad = "DPadDown" },
	ping = { keyboard = "T", gamepad = "DPadUp" },
	inventory = { keyboard = "Tab", gamepad = "ButtonSelect" },
} :: { [string]: Binding }

-- Touches supplémentaires fixes (non personnalisables).
Bindings.extras = {
	ping = { "MouseButton3" },
} :: { [string]: { string } }

-- « none » : action sans touche sur ce périphérique.
Bindings.NONE = "none"

local allowed: { keyboard: { [string]: boolean }, gamepad: { [string]: boolean } } = { keyboard = {}, gamepad = {} }
do
	-- Clavier : lettres (sauf déplacement W A S D), chiffres, modificateurs, souris.
	for code = string.byte("A"), string.byte("Z") do
		local letter = string.char(code)
		if letter ~= "W" and letter ~= "A" and letter ~= "S" and letter ~= "D" then
			allowed.keyboard[letter] = true
		end
	end
	for _, name in
		{
			"Zero",
			"One",
			"Two",
			"Three",
			"Four",
			"Five",
			"Six",
			"Seven",
			"Eight",
			"Nine",
			"LeftShift",
			"RightShift",
			"LeftControl",
			"RightControl",
			"LeftAlt",
			"RightAlt",
			"Tab",
			"CapsLock",
			"Backquote",
			"MouseButton1",
			"MouseButton2",
			"MouseButton3",
		}
	do
		allowed.keyboard[name] = true
	end
	-- Manette (sauf A = saut et Start = menu Roblox).
	for _, name in
		{
			"ButtonB",
			"ButtonX",
			"ButtonY",
			"ButtonR1",
			"ButtonR2",
			"ButtonR3",
			"ButtonL1",
			"ButtonL2",
			"ButtonL3",
			"DPadUp",
			"DPadDown",
			"DPadLeft",
			"DPadRight",
			"ButtonSelect",
		}
	do
		allowed.gamepad[name] = true
	end
end

function Bindings.isAllowed(slot: Slot, name: string): boolean
	local names = if slot == "keyboard" then allowed.keyboard else allowed.gamepad
	return name == Bindings.NONE or names[name] == true
end

function Bindings.isAction(name: any): boolean
	return type(name) == "string" and Bindings.defaults[name] ~= nil
end

-- Touches effectives (défauts + différences du profil).
function Bindings.resolve(overrides: Overrides?): { [string]: Binding }
	local result = {}
	for action, default in Bindings.defaults do
		local override = if overrides then overrides[action] else nil
		local entry: Binding = { keyboard = default.keyboard, gamepad = default.gamepad }
		if override then
			for _, slot in { "keyboard", "gamepad" } :: { Slot } do
				local value = (override :: any)[slot]
				if value ~= nil then
					(entry :: any)[slot] = if value == Bindings.NONE then nil else value
				end
			end
		end
		result[action] = entry
	end
	return result
end

-- Valeur du paramètre `keybinds` acceptable (envoyée par le client) ?
function Bindings.validate(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	local count = 0
	for action, entry in value do
		count += 1
		if count > #Bindings.actions or not Bindings.isAction(action) or type(entry) ~= "table" then
			return false
		end
		for slot, name in entry do
			if (slot ~= "keyboard" and slot ~= "gamepad") or type(name) ~= "string" then
				return false
			end
			if not Bindings.isAllowed(slot :: Slot, name) then
				return false
			end
		end
	end
	return true
end

-- Différences avec les défauts (ce qui est sauvegardé).
local function diff(resolved: { [string]: Binding }): Overrides
	local overrides: Overrides = {}
	for action, entry in resolved do
		local default = Bindings.defaults[action]
		local delta: Binding = {}
		local changed = false
		for _, slot in { "keyboard", "gamepad" } :: { Slot } do
			local current = (entry :: any)[slot]
			if current ~= (default :: any)[slot] then
				(delta :: any)[slot] = current or Bindings.NONE
				changed = true
			end
		end
		if changed then
			overrides[action] = delta
		end
	end
	return overrides
end

--[[
	Assigne `name` à `action` sur `slot`. Si une autre action utilisait déjà
	cette touche, elle reçoit l'ancienne touche de `action` (échange).
	Retourne les nouvelles différences à sauvegarder.
]]
function Bindings.assign(overrides: Overrides?, action: string, slot: Slot, name: string): Overrides
	assert(Bindings.isAction(action), `action inconnue : {action}`)
	assert(Bindings.isAllowed(slot, name), `touche refusée : {name}`)
	local resolved = Bindings.resolve(overrides)
	local previous = (resolved[action] :: any)[slot]
	local newValue = if name == Bindings.NONE then nil else name
	if newValue then
		for other, entry in resolved do
			if other ~= action and (entry :: any)[slot] == newValue then
				(entry :: any)[slot] = previous
			end
		end
	end
	(resolved[action] :: any)[slot] = newValue
	return diff(resolved)
end

return Bindings
