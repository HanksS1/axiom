--!nocheck
--[[
	Lance tous les tests : `lune run tests/run.luau` (depuis la racine du projet).
	Option : un filtre sur le nom de fichier, ex. `lune run tests/run.luau session`.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Harness = require("./lib/Harness")
local Test = require("./lib/Test")

local filter = process.args[1]

local files = {}
for _, entry in fs.readDir("tests/specs") do
	if string.match(entry, "%.spec%.luau$") and (filter == nil or string.find(entry, filter, 1, true)) then
		table.insert(files, entry)
	end
end
table.sort(files)

Harness.loadProject("./")

for _, file in files do
	Harness.reset()
	local spec = require("./specs/" .. string.gsub(file, "%.luau$", ""))
	local ok, err = pcall(spec, Test, Harness)
	if not ok then
		Test.it(file .. " (chargement)", function()
			error(err)
		end)
	end
end

local results = Test.results()
for _, failure in results.failures do
	print("✗ " .. failure.name .. "\n    " .. failure.err)
end
print(string.format("\n%d réussi(s), %d échoué(s) · %d fichier(s)", results.passed, results.failed, #files))
process.exit(if results.failed > 0 then 1 else 0)
