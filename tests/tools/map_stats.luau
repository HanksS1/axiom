--!nocheck
-- Statistiques des cartes : `lune run tests/tools/map_stats.luau`
local Harness = require("../lib/Harness")
Harness.loadProject("./")
local Config = Harness.require("ReplicatedStorage/Shared/Config")
local Registry = Harness.require("ServerScriptService/Server/Maps/Registry")
for _, mapId in Config.Maps.list do
	local build = Registry[mapId]
	if build then
		local LayoutBuilder = Harness.require("ServerScriptService/Server/Maps/LayoutBuilder")
		local started = os.clock()
		local layout = build(LayoutBuilder.random(Config.Maps.byId[mapId].seed))
		local elapsed = os.clock() - started
		local lights, emitters, solid, cover = 0, 0, 0, 0
		for _, part in layout.parts do
			if part.light then
				lights += 1
			end
			if part.emitter then
				emitters += 1
			end
			if part.collide ~= false then
				solid += 1
			end
			if part.tags and table.find(part.tags, "LightCover") then
				cover += 1
			end
		end
		print(
			string.format(
				"%s : %d pièces (%d solides), %d lumières, %d émetteurs, %d couverts légers, %.0f ms",
				mapId,
				#layout.parts,
				solid,
				lights,
				emitters,
				cover,
				elapsed * 1000
			)
		)
		local counts = {}
		for _, marker in layout.markers do
			counts[marker.tag] = (counts[marker.tag] or 0) + 1
		end
		local crateTypes = {}
		for _, marker in layout.markers do
			if marker.tag == "CrateSpawn" then
				local t = marker.attributes.CrateType
				crateTypes[t] = (crateTypes[t] or 0) + 1
			end
		end
		local parts = {}
		for tag, n in counts do
			table.insert(parts, tag .. "=" .. n)
		end
		local ct = {}
		for t, n in crateTypes do
			table.insert(ct, t .. "=" .. n)
		end
		print(mapId, #layout.parts .. " pièces", table.concat(parts, " "), "|", table.concat(ct, " "))
	end
end
