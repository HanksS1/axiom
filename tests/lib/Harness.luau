--!nocheck
--[[
	Harness : exécute les modules Roblox du projet hors de Studio, avec Lune.

	Reconstitue l'arborescence décrite par default.project.json sous forme
	d'« instances » virtuelles, pour que les `require(script.Parent.X)` et
	`game:GetService("ReplicatedStorage").Shared…` fonctionnent tels quels.

	Les services Roblox non disponibles (Players, DataStoreService…) sont
	fournis par les tests via `Harness.setService(name, stub)`.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local task = require("@lune/task")

local Harness = {}

local root = "./"
local services: { [string]: any } = {}
local moduleCache: { [any]: any } = {}
local nodeMeta = {}

-- Nœud virtuel ---------------------------------------------------------------

local function newNode(name: string, className: string, path: string?, source: string?, parent: any?)
	local node = setmetatable({
		_name = name,
		_className = className,
		_path = path, -- dossier (pour les enfants)
		_source = source, -- fichier source (ModuleScript / Script)
		_parent = parent,
		_children = {},
	}, nodeMeta)
	return node
end

local function stripExtension(fileName: string): (string?, string?)
	for _, suffix in { ".server.luau", ".client.luau", ".luau", ".server.lua", ".client.lua", ".lua" } do
		if string.sub(fileName, -#suffix) == suffix then
			local className = if string.find(suffix, "server")
				then "Script"
				elseif string.find(suffix, "client") then "LocalScript"
				else "ModuleScript"
			return string.sub(fileName, 1, -#suffix - 1), className
		end
	end
	return nil, nil
end

-- Construit l'arbre complet d'avance : les accès au disque de Lune cèdent la
-- main et ne peuvent pas être faits dans une métaméthode (__index).
local nodeFromPath

local function scanChildren(node, path: string)
	local children = rawget(node, "_children")
	for _, entry in fs.readDir(path) do
		local full = path .. "/" .. entry
		if fs.isDir(full) then
			children[entry] = nodeFromPath(entry, full, node)
		else
			local base = stripExtension(entry)
			if base and base ~= "init" then
				children[base] = nodeFromPath(base, full, node)
			end
		end
	end
end

function nodeFromPath(name: string, path: string, parent: any?)
	if fs.isDir(path) then
		local node
		for _, init in { "init.luau", "init.lua" } do
			if fs.isFile(path .. "/" .. init) then
				node = newNode(name, "ModuleScript", path, path .. "/" .. init, parent)
				break
			end
		end
		node = node or newNode(name, "Folder", path, nil, parent)
		scanChildren(node, path)
		return node
	end
	local base, className = stripExtension(path)
	assert(base, "fichier non pris en charge : " .. path)
	return newNode(name, className, nil, path, parent)
end

local function loadChildren(node)
	return rawget(node, "_children")
end

nodeMeta.__index = function(node, key)
	if key == "Name" then
		return rawget(node, "_name")
	elseif key == "Parent" then
		return rawget(node, "_parent")
	elseif key == "ClassName" then
		return rawget(node, "_className")
	elseif key == "FindFirstChild" then
		return function(self, name)
			return loadChildren(self)[name]
		end
	elseif key == "WaitForChild" then
		return function(self, name)
			local child = loadChildren(self)[name]
			assert(child, "WaitForChild : enfant introuvable " .. tostring(name))
			return child
		end
	elseif key == "GetChildren" then
		return function(self)
			local list = {}
			for _, child in loadChildren(self) do
				table.insert(list, child)
			end
			return list
		end
	elseif key == "IsA" then
		return function(self, className)
			return rawget(self, "_className") == className
				or (className == "LuaSourceContainer" and rawget(self, "_source") ~= nil)
		end
	end
	local child = loadChildren(node)[key]
	if child == nil then
		error(string.format("%s n'est pas un enfant valide de %s", tostring(key), rawget(node, "_name")), 2)
	end
	return child
end
nodeMeta.__tostring = function(node)
	return rawget(node, "_name")
end

-- Projet Rojo --------------------------------------------------------------

local projectRoots: { [string]: any } = {}

local function mapTree(tree, node)
	for key, value in tree do
		if string.sub(key, 1, 1) ~= "$" and type(value) == "table" then
			local child
			if value["$path"] then
				child = nodeFromPath(key, root .. value["$path"], node)
			else
				child = newNode(key, value["$className"] or "Folder", nil, nil, node)
			end
			rawget(node, "_children")[key] = child
			mapTree(value, child)
		end
	end
end

function Harness.loadProject(projectRoot: string?)
	root = projectRoot or "./"
	local project = serde.decode("json", fs.readFile(root .. "default.project.json"))
	for serviceName, serviceTree in project.tree do
		if string.sub(serviceName, 1, 1) ~= "$" then
			local serviceNode = newNode(serviceName, serviceName, nil, nil, nil)
			mapTree(serviceTree, serviceNode)
			projectRoots[serviceName] = serviceNode
		end
	end
end

-- Faux `game` ----------------------------------------------------------------

local fakeGame = setmetatable({
	JobId = "test-job",
	PlaceId = 0,
}, {
	__index = function(_, key)
		if key == "GetService" then
			return function(_self, name)
				local service = services[name] or projectRoots[name]
				assert(service ~= nil, "service non simulé dans les tests : " .. tostring(name))
				return service
			end
		elseif key == "BindToClose" then
			return function() end
		end
		return projectRoots[key]
	end,
})

function Harness.setService(name: string, stub: any)
	services[name] = stub
end

-- Random minimal compatible (Roblox `Random.new(seed)`).
local FakeRandom = {}
FakeRandom.__index = FakeRandom
function FakeRandom.new(seed: number?)
	local state = seed or os.clock() * 1e6
	return setmetatable({ _state = math.floor(state) % 2147483647 + 1 }, FakeRandom)
end
function FakeRandom:_next(): number
	-- Générateur congruentiel (Park-Miller) : suffisant et déterministe pour les tests.
	self._state = (self._state * 48271) % 2147483647
	return self._state / 2147483647
end
function FakeRandom:NextNumber(min: number?, max: number?): number
	local a, b = min or 0, max or 1
	return a + (b - a) * self:_next()
end
function FakeRandom:NextInteger(min: number, max: number): number
	return min + math.floor(self:_next() * (max - min + 1))
end

-- Chargement des modules -----------------------------------------------------

-- Avertissements émis par les modules (comptés, affichés si HARNESS_VERBOSE).
Harness.warnings = {} :: { string }
local verbose = require("@lune/process").env.HARNESS_VERBOSE ~= nil

local baseEnvironment = {
	warn = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			table.insert(parts, tostring((select(i, ...))))
		end
		local message = table.concat(parts, " ")
		table.insert(Harness.warnings, message)
		if verbose then
			print("[warn] " .. message)
		end
	end,
	game = fakeGame,
	task = task,
	Color3 = roblox.Color3,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Random = FakeRandom,
	Enum = roblox.Enum,
}

local function requireNode(node)
	if type(node) ~= "table" or getmetatable(node) ~= nodeMeta then
		error("require : argument non pris en charge (" .. tostring(node) .. ")", 2)
	end
	if moduleCache[node] ~= nil then
		return moduleCache[node]
	end
	local sourcePath = rawget(node, "_source")
	assert(sourcePath, "require d'un nœud sans source : " .. rawget(node, "_name"))
	-- Lune copie les champs propres de l'environnement (pas sa métatable).
	local environment = table.clone(baseEnvironment)
	environment.script = node
	environment.require = requireNode
	local chunk = luau.load(fs.readFile(sourcePath), {
		debugName = sourcePath,
		environment = environment,
	})
	local result = chunk()
	moduleCache[node] = result
	return result
end

Harness.FakeRandom = FakeRandom

--[[
	Rend disponibles les vraies Instances de Lune (Part, SurfaceGui…) et leurs
	types (NumberSequence, ColorSequence…) aux modules chargés ensuite : pour
	construire un décor hors de Studio et l'inspecter (tests du Terminus).
]]
local instanceGlobals: { string } = {}
function Harness.useInstances()
	instanceGlobals = {
		"Instance",
		"NumberSequence",
		"NumberSequenceKeypoint",
		"ColorSequence",
		"ColorSequenceKeypoint",
		"NumberRange",
		"BrickColor",
		"Rect",
		"Font",
	}
	baseEnvironment.Instance = roblox.Instance
	baseEnvironment.NumberSequence = roblox.NumberSequence
	baseEnvironment.NumberSequenceKeypoint = roblox.NumberSequenceKeypoint
	baseEnvironment.ColorSequence = roblox.ColorSequence
	baseEnvironment.ColorSequenceKeypoint = roblox.ColorSequenceKeypoint
	baseEnvironment.NumberRange = roblox.NumberRange
	baseEnvironment.BrickColor = roblox.BrickColor
	baseEnvironment.Rect = roblox.Rect
	baseEnvironment.Font = roblox.Font
end

-- Résout un chemin « Service/Enfant/… » et charge le module.
function Harness.require(path: string)
	local node
	for segment in string.gmatch(path, "[^/]+") do
		if node == nil then
			node = fakeGame:GetService(segment)
		else
			node = node[segment]
		end
	end
	return requireNode(node)
end

-- Vide le cache (chaque fichier de test repart de modules neufs).
function Harness.reset()
	-- Instances réservées au fichier de test qui les a demandées.
	for _, name in instanceGlobals do
		baseEnvironment[name] = nil
	end
	instanceGlobals = {}
	table.clear(moduleCache)
	table.clear(services)
	table.clear(Harness.warnings)
end

return Harness
