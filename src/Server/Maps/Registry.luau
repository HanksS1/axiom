--!strict
--[[
	Registry : constructeur de chaque carte (identifiant → fonction pure qui
	retourne la description greybox de la carte).
]]

local LayoutBuilder = require(script.Parent.LayoutBuilder)

export type Build = (rng: LayoutBuilder.Rng) -> LayoutBuilder.Layout

local Registry: { [string]: Build } = {
	neo_lumen = require(script.Parent.NeoLumen) :: Build,
	forge_7 = require(script.Parent.Forge7) :: Build,
	terres_brulees = require(script.Parent.TerresBrulees) :: Build,
	noyau_zero = require(script.Parent.NoyauZero) :: Build,
}

return Registry
