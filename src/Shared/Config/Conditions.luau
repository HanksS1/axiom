--!strict
--[[
	États des objets (section 7.1).

	L'état est FIXE (aucune usure) et fait office de rareté. Il est stocké dans
	les profils sous forme d'indice entier de 1 (Très abîmé) à 5 (Neuf).
	Seuls l'efficacité (dégâts, bouclier, stat principale d'un gadget…) et la
	valeur dépendent de l'état.
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

export type ConditionDef = {
	index: number,
	key: string, -- clé stable (sert aussi de suffixe de localisation)
	color: Color3,
	efficiency: number, -- multiplicateur de dégâts / efficacité
	valueMultiplier: number, -- multiplicateur de valeur (× valeur de base)
}

local MIN = 1
local MAX = 5

local list: { ConditionDef } = {
	{
		index = 1,
		key = "wrecked",
		color = Color3.fromRGB(154, 160, 166),
		efficiency = 0.70,
		valueMultiplier = 0.10,
	},
	{
		index = 2,
		key = "damaged",
		color = Color3.fromRGB(76, 217, 100),
		efficiency = 0.80,
		valueMultiplier = 0.25,
	},
	{
		index = 3,
		key = "worn",
		color = Color3.fromRGB(59, 167, 255),
		efficiency = 0.90,
		valueMultiplier = 0.50,
	},
	{
		index = 4,
		key = "good",
		color = Color3.fromRGB(176, 92, 255),
		efficiency = 1.00,
		valueMultiplier = 1.00,
	},
	{
		index = 5,
		key = "pristine",
		color = Color3.fromRGB(255, 176, 32),
		efficiency = 1.15,
		valueMultiplier = 2.50,
	},
}

return Freeze.deep({
	MIN = MIN,
	MAX = MAX,
	-- Indices nommés pour la lisibilité du code.
	WRECKED = 1,
	DAMAGED = 2,
	WORN = 3,
	GOOD = 4,
	PRISTINE = 5,
	list = list,
})
