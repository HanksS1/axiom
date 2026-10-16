--!strict
--[[
	Theme : charte graphique de l'interface (section 17.1).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local Theme = {
	panel = Color3.fromRGB(18, 22, 30), -- anthracite / bleu nuit
	panelTransparency = 0.25,
	background = Color3.fromRGB(8, 10, 16), -- fonds de jauges et de barres
	text = Color3.fromRGB(235, 240, 245),
	textDim = Color3.fromRGB(150, 158, 170),

	cyan = Color3.fromRGB(0, 229, 255), -- action principale
	magenta = Color3.fromRGB(255, 46, 196), -- boutique
	orange = Color3.fromRGB(255, 138, 0), -- alertes, extraction
	green = Color3.fromRGB(57, 255, 20), -- validation
	red = Color3.fromRGB(255, 59, 59), -- danger, dégâts

	health = Color3.fromRGB(235, 240, 245),
	healthLow = Color3.fromRGB(255, 59, 59),
	shield = Color3.fromRGB(0, 229, 255),

	-- Polices : techno / monospace pour les chiffres, sans-serif propre pour les textes.
	fontNumbers = Enum.Font.Code,
	fontTitle = Enum.Font.GothamBlack,
	fontText = Enum.Font.GothamMedium,

	minButtonSize = 44, -- px (mobile)
	-- Voile sous un menu ouvert (UI/ClickShield) : bloque les clics, assombrit à peine.
	shieldTransparency = 0.7,
}

function Theme.conditionColor(condition: number?): Color3
	if condition == nil then
		return Theme.textDim
	end
	local def = Config.Conditions.list[condition]
	return if def then def.color else Theme.textDim
end

return table.freeze(Theme)
