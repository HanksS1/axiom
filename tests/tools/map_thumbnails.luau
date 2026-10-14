--!nocheck
-- Génère src/Shared/Match/MapThumbnails.luau : `lune run tests/tools/map_thumbnails.luau`
-- (à relancer quand une carte change ; un test vérifie que le fichier est à jour).
local fs = require("@lune/fs")
local Harness = require("../lib/Harness")
Harness.loadProject("./")
local Config = Harness.require("ReplicatedStorage/Shared/Config")
local MapPlan = Harness.require("ReplicatedStorage/Shared/Match/MapPlan")
local Registry = Harness.require("ServerScriptService/Server/Maps/Registry")
local LayoutBuilder = Harness.require("ServerScriptService/Server/Maps/LayoutBuilder")

local P = Config.Maps.plan
local lines = {
	"--!strict",
	"--[[",
	"\tMapThumbnails : plans vus de dessus des cartes, en basse résolution, pour les",
	"\tvignettes de la Porte de déploiement (GÉNÉRÉ par tests/tools/map_thumbnails.luau,",
	"\tne pas modifier à la main ; un test vérifie qu'il correspond aux cartes).",
	"\tFormat : MapPlan.encode (cases|x,z,l,p;…).",
	"]]",
	"",
	"return table.freeze({",
}
for _, mapId in Config.Maps.list do
	local layout = Registry[mapId](LayoutBuilder.random(Config.Maps.byId[mapId].seed))
	local plan = MapPlan.build(layout.parts, Config.Maps.size, P.thumbnailCell, P.band)
	table.insert(lines, `\t{mapId} = "{MapPlan.encode(plan)}",`)
end
table.insert(lines, "})")
table.insert(lines, "")
fs.writeFile("src/Shared/Match/MapThumbnails.luau", table.concat(lines, "\n"))
print("MapThumbnails.luau généré")
