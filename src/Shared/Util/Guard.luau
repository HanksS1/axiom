--!strict
--[[
	Guard : validation stricte des types à l'exécution.

	Toute donnée venant d'un client (arguments de RemoteEvent / RemoteFunction)
	est considérée comme hostile. Chaque remote déclare un validateur construit
	avec ces fonctions ; le serveur rejette (et journalise) tout appel qui ne
	correspond pas exactement au format attendu.

	Un validateur est une fonction (value) -> (ok, raison?).
]]

export type Check = (value: any) -> (boolean, string?)

local Guard = {}

local function isFiniteNumber(value: any): boolean
	-- NaN ~= NaN, et ±inf ont une valeur absolue infinie.
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end
Guard.isFiniteNumber = isFiniteNumber

function Guard.any(): Check
	return function(_value)
		return true
	end
end

function Guard.boolean(): Check
	return function(value)
		if type(value) ~= "boolean" then
			return false, "boolean attendu"
		end
		return true
	end
end

function Guard.number(min: number?, max: number?): Check
	return function(value)
		if not isFiniteNumber(value) then
			return false, "nombre fini attendu"
		end
		if min ~= nil and value < min then
			return false, `nombre < {min}`
		end
		if max ~= nil and value > max then
			return false, `nombre > {max}`
		end
		return true
	end
end

function Guard.integer(min: number?, max: number?): Check
	local numberCheck = Guard.number(min, max)
	return function(value)
		local ok, reason = numberCheck(value)
		if not ok then
			return false, reason
		end
		if value % 1 ~= 0 then
			return false, "entier attendu"
		end
		return true
	end
end

function Guard.string(maxLength: number, pattern: string?): Check
	return function(value)
		if type(value) ~= "string" then
			return false, "chaîne attendue"
		end
		if #value > maxLength then
			return false, "chaîne trop longue"
		end
		if pattern ~= nil and string.match(value, pattern) == nil then
			return false, "format de chaîne invalide"
		end
		return true
	end
end

-- Identifiant unique d'objet (GUID Roblox sans accolades, ou identifiant interne).
function Guard.uid(): Check
	return Guard.string(64, "^[%w%-_]+$")
end

function Guard.enum(values: { string }): Check
	local allowed: { [string]: boolean } = {}
	for _, v in values do
		allowed[v] = true
	end
	return function(value)
		if type(value) ~= "string" or not allowed[value] then
			return false, "valeur hors énumération"
		end
		return true
	end
end

-- Énumération construite à partir des clés d'un dictionnaire de config.
function Guard.keyOf(dictionary: { [string]: any }): Check
	return function(value)
		if type(value) ~= "string" or dictionary[value] == nil then
			return false, "clé inconnue"
		end
		return true
	end
end

function Guard.vector3(maxMagnitude: number?): Check
	return function(value)
		if typeof(value) ~= "Vector3" then
			return false, "Vector3 attendu"
		end
		local v = value :: Vector3
		if not (isFiniteNumber(v.X) and isFiniteNumber(v.Y) and isFiniteNumber(v.Z)) then
			return false, "Vector3 non fini"
		end
		if maxMagnitude ~= nil and v.Magnitude > maxMagnitude then
			return false, "Vector3 trop grand"
		end
		return true
	end
end

-- Vecteur unitaire (direction de tir, de regard…).
function Guard.unitVector(tolerance: number?): Check
	local tol = tolerance or 0.01
	local base = Guard.vector3()
	return function(value)
		local ok, reason = base(value)
		if not ok then
			return false, reason
		end
		if math.abs((value :: Vector3).Magnitude - 1) > tol then
			return false, "vecteur non unitaire"
		end
		return true
	end
end

function Guard.instanceOf(className: string): Check
	return function(value)
		if typeof(value) ~= "Instance" or not (value :: Instance):IsA(className) then
			return false, `Instance {className} attendue`
		end
		return true
	end
end

function Guard.optional(check: Check): Check
	return function(value)
		if value == nil then
			return true
		end
		return check(value)
	end
end

function Guard.array(check: Check, maxLength: number): Check
	return function(value)
		if type(value) ~= "table" then
			return false, "tableau attendu"
		end
		local count = 0
		for key in value do
			count += 1
			if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
				return false, "tableau non séquentiel"
			end
		end
		if count > maxLength then
			return false, "tableau trop long"
		end
		if count ~= #value then
			return false, "tableau à trous"
		end
		for index = 1, count do
			local ok, reason = check(value[index])
			if not ok then
				return false, `[{index}] {reason or "?"}`
			end
		end
		return true
	end
end

-- Structure : clés exactes, aucune clé supplémentaire tolérée.
function Guard.struct(shape: { [string]: Check }): Check
	return function(value)
		if type(value) ~= "table" then
			return false, "table attendue"
		end
		for key in value do
			if type(key) ~= "string" or shape[key] == nil then
				return false, `clé inattendue {tostring(key)}`
			end
		end
		for key, check in shape do
			local ok, reason = check(value[key])
			if not ok then
				return false, `{key} : {reason or "?"}`
			end
		end
		return true
	end
end

-- Valide une liste d'arguments (ceux d'un appel de remote).
function Guard.tuple(...: Check): (...any) -> (boolean, string?)
	local checks = { ... }
	local expected = #checks
	return function(...)
		local count = select("#", ...)
		if count > expected then
			return false, "trop d'arguments"
		end
		local args = { ... }
		for index = 1, expected do
			local ok, reason = checks[index](args[index])
			if not ok then
				return false, `argument {index} : {reason or "?"}`
			end
		end
		return true
	end
end

return Guard
