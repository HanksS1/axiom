--!nocheck
--[[
	Plan vu de dessus de chaque carte (SVG, à ouvrir dans un navigateur) :
	`lune run tests/tools/map_preview.luau [dossier de sortie]`

	Pièces solides en couleur (plus claires en hauteur), décor sans collision
	en transparence, lumières en jaune, repères en pastilles :
	D = départ, X = extraction, A = Accélérateur, R = patrouille, caisses en vert.
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local Vector3 = require("@lune/roblox").Vector3
local Harness = require("../lib/Harness")
Harness.loadProject("./")
local Config = Harness.require("ReplicatedStorage/Shared/Config")
local Registry = Harness.require("ServerScriptService/Server/Maps/Registry")
local LayoutBuilder = Harness.require("ServerScriptService/Server/Maps/LayoutBuilder")

local out = process.args[1] or "map-preview"
if not fs.isDir(out) then
	fs.writeDir(out)
end

local HALF = Config.Maps.size / 2
local MARKERS = {
	DeploySpawn = { "#ffffff", "D", 7 },
	ExtractionPoint = { "#ff8a00", "X", 11 },
	AcceleratorSpot = { "#00e5ff", "A", 6 },
	RobotSpawn = { "#ff3b3b", "R", 5 },
	CrateSpawn = { "#39ff14", "", 3 },
}

for _, mapId in Config.Maps.list do
	local layout = Registry[mapId](LayoutBuilder.random(Config.Maps.byId[mapId].seed))
	local parts = table.clone(layout.parts)
	table.sort(parts, function(a, b)
		return a.cframe.Position.Y + a.size.Y / 2 < b.cframe.Position.Y + b.size.Y / 2
	end)
	local svg = {
		`<svg xmlns="http://www.w3.org/2000/svg" viewBox="{-HALF} {-HALF} {HALF * 2} {HALF * 2}" width="1600" height="1600">`,
		`<rect x="{-HALF}" y="{-HALF}" width="{HALF * 2}" height="{HALF * 2}" fill="#101014"/>`,
	}
	for _, part in parts do
		local cf, size = part.cframe, part.size
		local top = cf.Position.Y + size.Y / 2
		-- Les très grandes dalles hautes (toitures) masqueraient l'intérieur : contour seulement.
		local roof = top > 12 and size.X * size.Z > 4000
		local points = {}
		for _, corner in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
			local p = cf:PointToWorldSpace(Vector3.new(corner[1] * size.X / 2, 0, corner[2] * size.Z / 2))
			table.insert(points, string.format("%.1f,%.1f", p.X, p.Z))
		end
		local shade = math.clamp(0.55 + top / 60, 0.45, 1.5)
		local r = math.clamp(math.floor(part.color.R * 255 * shade), 0, 255)
		local g = math.clamp(math.floor(part.color.G * 255 * shade), 0, 255)
		local b = math.clamp(math.floor(part.color.B * 255 * shade), 0, 255)
		local opacity = if part.collide == false then 0.45 else 1
		if (part.transparency or 0) >= 0.8 then
			opacity = 0.12
		end
		if roof then
			table.insert(
				svg,
				`<polygon points="{table.concat(points, " ")}" fill="none" stroke="rgb({r},{g},{b})" stroke-width="0.8" stroke-dasharray="4 3"/>`
			)
		else
			table.insert(
				svg,
				`<polygon points="{table.concat(points, " ")}" fill="rgb({r},{g},{b})" fill-opacity="{opacity}"/>`
			)
		end
	end
	for _, part in layout.parts do
		if part.light then
			local p = part.cframe.Position
			table.insert(
				svg,
				string.format('<circle cx="%.1f" cy="%.1f" r="1.6" fill="#ffe680" fill-opacity="0.9"/>', p.X, p.Z)
			)
		end
	end
	for _, marker in layout.markers do
		local style = MARKERS[marker.tag]
		if style then
			local p = marker.cframe.Position
			table.insert(
				svg,
				string.format(
					'<circle cx="%.1f" cy="%.1f" r="%d" fill="%s" fill-opacity="0.85" stroke="#000" stroke-width="0.6"/>',
					p.X,
					p.Z,
					style[3],
					style[1]
				)
			)
			if style[2] ~= "" then
				table.insert(
					svg,
					string.format(
						'<text x="%.1f" y="%.1f" font-size="8" font-family="monospace" text-anchor="middle" fill="#000">%s</text>',
						p.X,
						p.Z + 3,
						style[2]
					)
				)
			end
		end
	end
	table.insert(svg, "</svg>")
	local path = `{out}/{mapId}.svg`
	fs.writeFile(path, table.concat(svg, "\n"))
	print(path, #layout.parts .. " pièces")
end
