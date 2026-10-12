--!strict
--[[
	Cellules d'énergie (section 6.4). Une pile de 30 cellules occupe 1 UP.
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

export type CellDef = {
	id: string,
	color: Color3,
	stackSize: number,
	up: number, -- UP par pile (même partielle)
	stackValue: number, -- valeur d'une pile pleine (revente / SE)
	merchantStackPrice: number, -- prix d'achat d'une pile pleine chez le Marchand
}

-- QUESTION OUVERTE : le document fixe le prix d'achat (20 crédits la pile)
-- mais pas la valeur de revente. Valeur provisoire : 10 par pile pleine
-- (moitié du prix d'achat, cohérent avec le « ×2 » des équipements).
local STACK_VALUE = 10

local function cell(id: string, color: Color3): CellDef
	return {
		id = id,
		color = color,
		stackSize = 30,
		up = 1,
		stackValue = STACK_VALUE,
		merchantStackPrice = 20,
	}
end

return Freeze.deep({
	cell_light = cell("cell_light", Color3.fromRGB(255, 221, 51)),
	cell_standard = cell("cell_standard", Color3.fromRGB(0, 229, 255)),
	cell_precision = cell("cell_precision", Color3.fromRGB(240, 240, 240)),
	cell_heavy = cell("cell_heavy", Color3.fromRGB(255, 59, 59)),
} :: { [string]: CellDef })
