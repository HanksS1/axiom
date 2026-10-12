--!nocheck
--[[
	Mini-framework de tests (describe / it / expect).
]]

local Test = {}

local results = { passed = 0, failed = 0, failures = {} }
local prefix: { string } = {}

local function fullName(name: string): string
	local parts = table.clone(prefix)
	table.insert(parts, name)
	return table.concat(parts, " › ")
end

function Test.describe(name: string, body: () -> ())
	table.insert(prefix, name)
	body()
	table.remove(prefix)
end

function Test.it(name: string, body: () -> ())
	local ok, err = pcall(body)
	if ok then
		results.passed += 1
	else
		results.failed += 1
		table.insert(results.failures, { name = fullName(name), err = tostring(err) })
	end
end

local function fmt(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

function Test.expect(actual: any)
	local api = {}
	function api.toBe(expected: any)
		if actual ~= expected then
			error(string.format("attendu %s, obtenu %s", fmt(expected), fmt(actual)), 2)
		end
	end
	function api.toEqual(expected: any)
		if not deepEqual(actual, expected) then
			error("les tables diffèrent", 2)
		end
	end
	function api.toBeNear(expected: number, epsilon: number?)
		if math.abs(actual - expected) > (epsilon or 1e-6) then
			error(string.format("attendu ≈ %s, obtenu %s", fmt(expected), fmt(actual)), 2)
		end
	end
	function api.toBeTruthy()
		if not actual then
			error("attendu une valeur vraie, obtenu " .. fmt(actual), 2)
		end
	end
	function api.toBeFalsy()
		if actual then
			error("attendu une valeur fausse, obtenu " .. fmt(actual), 2)
		end
	end
	function api.toBeNil()
		if actual ~= nil then
			error("attendu nil, obtenu " .. fmt(actual), 2)
		end
	end
	function api.toThrow()
		local ok = pcall(actual)
		if ok then
			error("attendu une erreur", 2)
		end
	end
	return api
end

function Test.results()
	return results
end

return Test
