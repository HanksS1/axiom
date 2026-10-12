--!strict
--[[
	Paramètres joueur (section 17.3, écran 17) : valeurs par défaut et bornes.
	Le serveur n'accepte que les paramètres listés ici, dans leurs bornes.
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

export type SettingDef = {
	kind: "number" | "boolean" | "enum" | "keybinds" | "touchLayout",
	default: any,
	min: number?,
	max: number?,
	values: { string }?,
}

local settings: { [string]: SettingDef } = {
	-- "auto" = langue du compte Roblox.
	language = { kind = "enum", default = "auto", values = { "auto", "fr", "en" } },
	mouseSensitivity = { kind = "number", default = 1, min = 0.1, max = 5 },
	touchSensitivity = { kind = "number", default = 1, min = 0.1, max = 5 },
	gamepadSensitivity = { kind = "number", default = 1, min = 0.1, max = 5 },
	aimAssist = { kind = "boolean", default = true },
	aimAssistStrength = { kind = "number", default = 0.5, min = 0, max = 1 },
	cameraShoulder = { kind = "enum", default = "right", values = { "right", "left" } },
	crossplay = { kind = "boolean", default = true },
	volumeMusic = { kind = "number", default = 0.7, min = 0, max = 1 },
	volumeEffects = { kind = "number", default = 1, min = 0, max = 1 },
	volumeAxiom = { kind = "number", default = 1, min = 0, max = 1 },
	volumeVoice = { kind = "number", default = 1, min = 0, max = 1 },
	graphicsQuality = { kind = "enum", default = "auto", values = { "auto", "low", "medium", "high" } },
	mobileButtonOpacity = { kind = "number", default = 0.8, min = 0.2, max = 1 },
	skipCrateAnimation = { kind = "boolean", default = false },
	-- Touches personnalisées (différences avec les touches par défaut, voir Input/Bindings).
	keybinds = { kind = "keybinds", default = {} },
	-- Disposition personnalisée des boutons tactiles (voir Input/TouchLayout).
	touchLayout = { kind = "touchLayout", default = {} },
}

return Freeze.deep(settings)
