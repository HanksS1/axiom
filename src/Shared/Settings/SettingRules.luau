--!strict
--[[
	SettingRules : validation d'un paramètre joueur (serveur : réception et
	assainissement des profils). Une seule source de vérité pour les bornes.
]]

local Config = require(script.Parent.Parent.Config)
local Bindings = require(script.Parent.Parent.Input.Bindings)
local TouchLayout = require(script.Parent.Parent.Input.TouchLayout)

local SettingRules = {}

function SettingRules.isValid(key: any, value: any): boolean
	if type(key) ~= "string" then
		return false
	end
	local def = Config.Settings[key]
	if def == nil then
		return false
	end
	if def.kind == "boolean" then
		return type(value) == "boolean"
	elseif def.kind == "number" then
		return type(value) == "number"
			and value == value
			and value >= (def.min :: number)
			and value <= (def.max :: number)
	elseif def.kind == "enum" then
		return type(value) == "string" and table.find(def.values :: { string }, value) ~= nil
	elseif def.kind == "keybinds" then
		return Bindings.validate(value)
	elseif def.kind == "touchLayout" then
		return TouchLayout.validate(value)
	end
	return false
end

-- Valeur par défaut (copie : les tables de la config sont gelées).
function SettingRules.default(key: string): any
	local value = Config.Settings[key].default
	return if type(value) == "table" then table.clone(value) else value
end

return SettingRules
