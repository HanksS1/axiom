--!nocheck
-- Plan vu de dessus des cartes : `lune run tests/tools/map_plan.luau [case] [dossier]`
-- Affiche le nombre de rectangles par carte et, avec un dossier, écrit un
-- fichier texte par carte (une ligne de 0/1 par rangée) pour en tirer une image.
local fs = require("@lune/fs")
local process = require("@lune/process")
local Harness = require("../lib/Harness")
Harness.loadProject("./")
local Config = Harness.require("ReplicatedStorage/Shared/Config")
local MapPlan = Harness.require("ReplicatedStorage/Shared/Match/MapPlan")
local Registry = Harness.require("ServerScriptService/Server/Maps/Registry")
local LayoutBuilder = Harness.require("ServerScriptService/Server/Maps/LayoutBuilder")

local P = Config.Maps.plan
local cell = tonumber(process.args[1]) or P.cell
local out = process.args[2]
for _, mapId in Config.Maps.list do
	local layout = Registry[mapId](LayoutBuilder.random(Config.Maps.byId[mapId].seed))
	local grid, cells = MapPlan.rasterize(layout.parts, Config.Maps.size, cell, P.band)
	local rects = MapPlan.rects(grid, cells)
	local full = 0
	for _, value in grid do
		if value then
			full += 1
		end
	end
	local encoded = MapPlan.encode({ cells = cells, rects = rects })
	print(string.format("%s : %d cases pleines, %d rectangles, %d octets", mapId, full, #rects, #encoded))
	if out then
		local lines = {}
		for z = 0, cells - 1 do
			local row = table.create(cells)
			for x = 0, cells - 1 do
				row[x + 1] = if grid[z * cells + x + 1] then "1" else "0"
			end
			lines[z + 1] = table.concat(row)
		end
		fs.writeFile(out .. "/" .. mapId .. ".txt", table.concat(lines, "\n"))
	end
end
