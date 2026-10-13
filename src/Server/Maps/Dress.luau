--!strict
--[[
	Dress : habillage des cartes (répartition des décors de Props).

	Toutes les poses passent par `Props.place`, qui refuse un emplacement
	occupé : un décor ne recouvre jamais une caisse, une extraction, un
	Accélérateur, un point de départ, une porte ou un autre décor. L'habillage
	se fait donc APRÈS la pose des repères de la carte.
]]

local LayoutBuilder = require(script.Parent.LayoutBuilder)
local Props = require(script.Parent.Props)

type Builder = LayoutBuilder.Builder
type Rng = LayoutBuilder.Rng
type BuildingInfo = LayoutBuilder.BuildingInfo

local C = LayoutBuilder.colors

local Dress = {}

export type Area = { x0: number, x1: number, z0: number, z1: number }

local DECOR: LayoutBuilder.PartOptions = { collide = false, query = false }

-- Orientation : "grid" = alignée sur les axes (légèrement de travers), sinon quelconque.
local function yawOf(rng: Rng, mode: string?): number
	if mode == "grid" then
		return rng:NextInteger(0, 3) * math.pi / 2 + rng:NextNumber(-0.14, 0.14)
	end
	return rng:NextNumber(0, math.pi * 2)
end

-- Dégage les abords des repères : zone d'extraction, Accélérateurs, départs, patrouilles.
function Dress.reserve(b: Builder)
	local radius = { ExtractionPoint = 11, AcceleratorSpot = 7, DeploySpawn = 6, RobotSpawn = 6 }
	for _, marker in b.layout.markers do
		local r = radius[marker.tag]
		if r then
			local p = marker.cframe.Position
			b:keepOut(p.X, p.Z, r, p.Y - 6, p.Y + 14)
		end
	end
end

-- Pose jusqu'à `count` décors tirés dans `list`, au hasard dans `area`. Retourne le nombre posé.
function Dress.scatter(
	b: Builder,
	rng: Rng,
	list: { string },
	count: number,
	area: Area,
	y: number?,
	yawMode: string?
): number
	if area.x1 <= area.x0 or area.z1 <= area.z0 then
		return 0
	end
	local placed, attempts = 0, 0
	while placed < count and attempts < count * 12 do
		attempts += 1
		local name = list[rng:NextInteger(1, #list)]
		local x, z = rng:NextNumber(area.x0, area.x1), rng:NextNumber(area.z0, area.z1)
		if Props.place(b, name, x, y or 0, z, yawOf(rng, yawMode), rng) then
			placed += 1
		end
	end
	return placed
end

-- Comme `scatter`, dans la couronne carrée entre `inner` et `outer` (abords de la carte, terrasses).
function Dress.ring(
	b: Builder,
	rng: Rng,
	list: { string },
	count: number,
	inner: number,
	outer: number,
	y: number?
): number
	local placed, attempts = 0, 0
	while placed < count and attempts < count * 14 do
		attempts += 1
		local x, z = rng:NextNumber(-outer, outer), rng:NextNumber(-outer, outer)
		if math.max(math.abs(x), math.abs(z)) >= inner then
			local name = list[rng:NextInteger(1, #list)]
			if Props.place(b, name, x, y or 0, z, yawOf(rng, nil), rng) then
				placed += 1
			end
		end
	end
	return placed
end

-- Décors en file de (x0, z0) à (x1, z1) : épaves le long d'une rue, pylônes…
function Dress.along(
	b: Builder,
	rng: Rng,
	list: { string },
	count: number,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	lateral: number,
	wobble: number
): number
	local dx, dz = x1 - x0, z1 - z0
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 1 then
		return 0
	end
	local ux, uz = dx / length, dz / length
	-- Lacet d'un décor dont la longueur (axe Z local) suit la file.
	local heading = math.atan2(-ux, -uz)
	local placed = 0
	for index = 1, count do
		local along = (index - 0.5 + rng:NextNumber(-0.35, 0.35)) / count * length
		local side = rng:NextNumber(-lateral, lateral)
		local x, z = x0 + ux * along - uz * side, z0 + uz * along + ux * side
		local yaw = heading + (if rng:NextNumber() < 0.5 then math.pi else 0) + rng:NextNumber(-wobble, wobble)
		if Props.place(b, list[rng:NextInteger(1, #list)], x, 0, z, yaw, rng) then
			placed += 1
		end
	end
	return placed
end

-- Mobilier de chaque étage des bâtiments (hors édifices qui s'effondrent).
function Dress.interiors(b: Builder, rng: Rng, infos: { BuildingInfo }, list: { string }, perLevel: number)
	for _, info in infos do
		if info.group == nil then
			local area = {
				x0 = info.x - info.w / 2 + 2,
				x1 = info.x + info.w / 2 - 2,
				z0 = info.z - info.d / 2 + 2,
				z1 = info.z + info.d / 2 - 2,
			}
			for level = 1, #info.levels - 1 do
				Dress.scatter(b, rng, list, perLevel, area, info.levels[level], "grid")
			end
		end
	end
end

-- Décors adossés aux façades (bennes, caisses, palissades…) : le pied des murs n'est plus nu.
function Dress.around(b: Builder, rng: Rng, infos: { BuildingInfo }, list: { string }, perBuilding: number)
	for _, info in infos do
		if info.group == nil then
			local placed, attempts = 0, 0
			while placed < perBuilding and attempts < perBuilding * 8 do
				attempts += 1
				local name = list[rng:NextInteger(1, #list)]
				local gap = Props.catalog[name].radius + 1.5
				local side = rng:NextInteger(1, 4)
				local x, z, yaw
				if side <= 2 then
					-- Façades sud / nord : le décor s'allonge le long de l'axe x.
					x = info.x + rng:NextNumber(-info.w / 2, info.w / 2)
					z = info.z + (if side == 1 then -1 else 1) * (info.d / 2 + gap)
					yaw = math.pi / 2
				else
					x = info.x + (if side == 3 then -1 else 1) * (info.w / 2 + gap)
					z = info.z + rng:NextNumber(-info.d / 2, info.d / 2)
					yaw = 0
				end
				if Props.place(b, name, x, info.levels[1], z, yaw + rng:NextNumber(-0.1, 0.1), rng) then
					placed += 1
				end
			end
		end
	end
end

-- Toits : acrotères (couvert bas) et équipements techniques.
function Dress.roofs(b: Builder, rng: Rng, infos: { BuildingInfo }, list: { string }, perRoof: number)
	for index, info in infos do
		if info.group == nil then
			local y = info.roof
			local hw, hd = info.w / 2, info.d / 2
			local color, material = C.darkConcrete, "Concrete"
			b:block(`Parapet{index}S`, info.x, info.z - hd + 0.5, info.w, 1, 2.6, color, material, { base = y })
			b:block(`Parapet{index}N`, info.x, info.z + hd - 0.5, info.w, 1, 2.6, color, material, { base = y })
			b:block(`Parapet{index}E`, info.x + hw - 0.5, info.z, 1, info.d - 2, 2.6, color, material, { base = y })
			b:block(`Parapet{index}W`, info.x - hw + 0.5, info.z, 1, info.d - 2, 2.6, color, material, { base = y })
			Dress.scatter(b, rng, list, perRoof, {
				x0 = info.x - hw + 2,
				x1 = info.x + hw - 2,
				z0 = info.z - hd + 2,
				z1 = info.z + hd - 2,
			}, y, "grid")
		end
	end
end

-- Couverts près de chaque point de départ (personne n'apparaît à découvert).
function Dress.spawnCover(b: Builder, rng: Rng, list: { string })
	for _, marker in b.layout.markers do
		if marker.tag == "DeploySpawn" then
			local p = marker.cframe.Position
			local length = math.sqrt(p.X * p.X + p.Z * p.Z)
			if length > 1 then
				-- Vers le centre de la carte, de part et d'autre de la ligne de vue.
				local ux, uz = -p.X / length, -p.Z / length
				for _, side in { -1, 1 } do
					for _ = 1, 4 do
						local forward = rng:NextNumber(14, 22)
						local lateral = side * rng:NextNumber(5, 12)
						local x, z = p.X + ux * forward - uz * lateral, p.Z + uz * forward + ux * lateral
						local name = list[rng:NextInteger(1, #list)]
						if Props.place(b, name, x, 0, z, math.atan2(-uz, ux) + rng:NextNumber(-0.3, 0.3), rng) then
							break
						end
					end
				end
			end
		end
	end
end

export type Skyline = {
	colors: { Color3 },
	material: string,
	height: { min: number, max: number },
	width: { min: number, max: number },
	glow: { Color3 }?, -- bandeaux lumineux (fenêtres, enseignes) sur une partie des blocs
	glowChance: number?,
}

--[[
	Silhouettes au pied de l'enceinte (immeubles en ruine, falaises, murs
	d'usine) : la carte ne s'arrête plus sur un mur nu.
]]
function Dress.skyline(b: Builder, rng: Rng, size: number, spec: Skyline)
	local half = size / 2
	local sides = {
		{ axis = "x", sign = 1 },
		{ axis = "x", sign = -1 },
		{ axis = "z", sign = 1 },
		{ axis = "z", sign = -1 },
	}
	local index = 0
	for _, side in sides do
		local cursor = -half + 2
		while cursor < half - 2 do
			index += 1
			local width = math.min(rng:NextNumber(spec.width.min, spec.width.max), half - 2 - cursor)
			local depth = rng:NextNumber(7, 11)
			local height = rng:NextNumber(spec.height.min, spec.height.max)
			local centre = cursor + width / 2
			local inset = side.sign * (half - 1 - depth / 2)
			local color = spec.colors[rng:NextInteger(1, #spec.colors)]
			local alongX = side.axis == "z" -- bloc le long de l'axe x sur les bords nord / sud
			if width >= 6 then
				b:block(
					"Skyline" .. index,
					if alongX then centre else inset,
					if alongX then inset else centre,
					if alongX then width else depth,
					if alongX then depth else width,
					height,
					color,
					spec.material
				)
				if spec.glow and rng:NextNumber() < (spec.glowChance or 0.3) then
					local glow = spec.glow[rng:NextInteger(1, #spec.glow)]
					local face = side.sign * (half - 1 - depth - 0.2)
					local glowY = rng:NextNumber(8, math.max(9, height * 0.7))
					local glowWidth = math.max(3, width * rng:NextNumber(0.3, 0.7))
					b:part(
						"SkylineGlow" .. index,
						if alongX then Vector3.new(glowWidth, 1.2, 0.3) else Vector3.new(0.3, 1.2, glowWidth),
						CFrame.new(if alongX then centre else face, glowY, if alongX then face else centre),
						glow,
						"Neon",
						{ collide = false, query = false, tags = { "Flicker" } }
					)
				end
			end
			cursor += width + rng:NextNumber(0, 3)
		end
	end
end

-- Bande au sol sans collision (marquage, chaussée, trottoir).
function Dress.groundStrip(
	b: Builder,
	name: string,
	x: number,
	z: number,
	w: number,
	d: number,
	color: Color3,
	material: string,
	lift: number?
)
	b:part(name, Vector3.new(w, 0.1, d), CFrame.new(x, (lift or 0.05), z), color, material, DECOR)
end

-- Source lumineuse seule (plafonnier, lueur) : petite pièce néon sans collision.
function Dress.glow(
	b: Builder,
	name: string,
	position: Vector3,
	size: Vector3,
	color: Color3,
	range: number,
	brightness: number,
	flicker: boolean?,
	emergency: boolean?
)
	b:part(name, size, CFrame.new(position), color, "Neon", {
		collide = false,
		query = false,
		light = { color = color, range = range, brightness = brightness, flicker = flicker, emergency = emergency },
	})
end

-- Émetteur de particules invisible (poussière, braises au-dessus d'une coulée…).
function Dress.particles(b: Builder, name: string, position: Vector3, preset: string, size: Vector3?)
	b:part(name, size or Vector3.new(4, 0.4, 4), CFrame.new(position), C.white, "SmoothPlastic", {
		collide = false,
		query = false,
		transparency = 1,
		emitter = preset,
	})
end

return Dress
