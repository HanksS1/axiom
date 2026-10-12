--!strict
--[[
	Localisation FR / EN (section 19.6).

	Tous les textes visibles passent par une clé : `Localization.get(lang,
	key, params)`. Une clé manquante est signalée (warn) et sa clé affichée,
	pour être repérée immédiatement pendant les tests.
]]

local Strings = {
	fr = require(script.Strings.fr),
	en = require(script.Strings.en),
}

export type Language = "fr" | "en"

local Localization = {}

Localization.languages = table.freeze({ "fr", "en" } :: { Language })
Localization.default = "en" :: Language

local warned: { [string]: boolean } = {}

--[[
	Résout la langue effective à partir du paramètre du joueur
	("auto" | "fr" | "en") et de la locale du compte Roblox (ex. "fr-fr").
]]
function Localization.resolve(setting: string?, localeId: string?): Language
	if setting == "fr" or setting == "en" then
		return setting :: Language
	end
	if type(localeId) == "string" and string.sub(string.lower(localeId), 1, 2) == "fr" then
		return "fr" :: Language
	end
	return Localization.default :: Language
end

--[[
	Formate un nombre selon la langue : séparateur de milliers (espace fine
	insécable en français, virgule en anglais) et au plus 2 décimales
	(virgule décimale en français).
]]
function Localization.formatNumber(lang: Language, value: number): string
	if value ~= value or math.abs(value) == math.huge then
		return "?"
	end
	local negative = value < 0
	local cents = math.floor(math.abs(value) * 100 + 0.5)
	local integerPart = cents // 100
	local decimals = ""
	if cents % 100 ~= 0 then
		decimals = (string.gsub(string.format("%02d", cents % 100), "0$", ""))
	end

	local digits = string.format("%d", integerPart)
	-- Espace fine insécable (U+202F) encodée en UTF-8.
	local thousands = if lang == "fr" then "\226\128\175" else ","
	local groups = {}
	local length = #digits
	local first = length % 3
	if first > 0 then
		table.insert(groups, string.sub(digits, 1, first))
	end
	for index = first + 1, length, 3 do
		table.insert(groups, string.sub(digits, index, index + 2))
	end
	local result = table.concat(groups, thousands)
	if decimals ~= "" then
		result ..= (if lang == "fr" then "," else ".") .. decimals
	end
	return if negative and result ~= "0" then "-" .. result else result
end

function Localization.has(lang: Language, key: string): boolean
	local strings = Strings[lang] :: { [string]: string }?
	return strings ~= nil and strings[key] ~= nil
end

function Localization.get(lang: Language, key: string, params: { [string]: any }?): string
	local strings = (Strings[lang] or Strings[Localization.default]) :: { [string]: string }
	local template = strings[key]
	if template == nil then
		template = (Strings[Localization.default] :: { [string]: string })[key]
		if template == nil then
			if not warned[key] then
				warned[key] = true
				warn(`[Localization] clé manquante : {key}`)
			end
			return key
		end
	end
	if params == nil then
		return template
	end
	return (
		string.gsub(template, "{(%w+)}", function(name: string): string
			local value = params[name]
			if value == nil then
				return "{" .. name .. "}" -- laisse le motif intact
			end
			if type(value) == "number" then
				return Localization.formatNumber(lang :: Language, value)
			end
			return tostring(value)
		end)
	)
end

-- Accès brut aux tables (tests de parité FR / EN).
function Localization._tables(): { [string]: { [string]: string } }
	return Strings :: any
end

return Localization
