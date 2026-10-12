--!strict
--[[
	TouchLayout : disposition personnalisée des boutons tactiles (17.3, écran 12).

	Paramètre `touchLayout` : par bouton, position du centre en fraction de
	l'écran (x, y entre 0 et 1) et taille relative (s). Les boutons absents
	gardent la disposition par défaut.
]]

local TouchLayout = {}

export type Placement = { x: number, y: number, s: number }

TouchLayout.buttons = {
	"fire",
	"aim",
	"parry",
	"reload",
	"switch",
	"crouch",
	"sprint",
	"heal",
	"battery",
	"boost",
	"inventory",
	"gadget1",
	"gadget2",
	"ping",
}

TouchLayout.minScale = 0.6
TouchLayout.maxScale = 1.6

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function TouchLayout.validate(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	local count = 0
	for button, placement in value do
		count += 1
		if count > #TouchLayout.buttons or type(button) ~= "string" then
			return false
		end
		if table.find(TouchLayout.buttons, button) == nil or type(placement) ~= "table" then
			return false
		end
		local fields = 0
		for _ in placement do
			fields += 1
		end
		if fields ~= 3 or not finite(placement.x) or not finite(placement.y) or not finite(placement.s) then
			return false
		end
		if placement.x < 0 or placement.x > 1 or placement.y < 0 or placement.y > 1 then
			return false
		end
		if placement.s < TouchLayout.minScale or placement.s > TouchLayout.maxScale then
			return false
		end
	end
	return true
end

return TouchLayout
