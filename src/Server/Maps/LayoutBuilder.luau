--!strict
--[[
	LayoutBuilder : description PURE d'une carte greybox (pièces, repères,
	zones dangereuses, effondrements). Aucune Instance n'est créée ici :
	MapRenderer s'en charge. Les cartes peuvent ainsi être vérifiées par
	des tests (nombre de repères, caisses posées sur un sol…).

	Coordonnées LOCALES : x / z autour du centre de la carte, y = hauteur
	(le sol de la carte est à y = 0). Le décalage vers `Config.Maps.origin`
	est appliqué au rendu.
]]

local LayoutBuilder = {}

export type PartSpec = {
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: string, -- nom d'Enum.Material
	transparency: number?,
	collide: boolean?, -- true par défaut
	query: boolean?, -- true par défaut (les tirs s'arrêtent dessus)
	shape: string?, -- nom d'Enum.PartType (Cylinder, Ball…)
	group: string?, -- regroupement (édifice qui peut s'effondrer…)
	tags: { string }?,
	attributes: { [string]: any }?,
}

export type MarkerSpec = {
	tag: string,
	cframe: CFrame,
	attributes: { [string]: any }?,
}

export type Hazard = {
	kind: string, -- "molten" | "radiation"
	center: Vector3,
	size: Vector3?, -- boîte (métal en fusion)
	radius: number?, -- cylindre vertical (radiation)
	height: number,
}

export type Collapse = {
	id: string,
	kind: string, -- "building" (s'effondre dans la rue) | "barrier" (s'écroule et libère un passage)
	center: Vector3,
	size: Vector3, -- emprise touchée par l'effondrement
	rubble: { PartSpec }, -- décombres après l'effondrement
}

export type Layout = {
	parts: { PartSpec },
	markers: { MarkerSpec },
	hazards: { Hazard },
	collapses: { Collapse },
	data: { [string]: any },
}

export type Rng = {
	NextNumber: (self: any, min: number?, max: number?) -> number,
	NextInteger: (self: any, min: number, max: number) -> number,
}

export type BuildingSpec = {
	x: number,
	z: number,
	w: number,
	d: number,
	floors: number,
	base: number?,
	floorHeight: number?,
	doors: { string }?, -- côtés ouverts au rez-de-chaussée : "n", "s", "e", "w"
	windows: boolean?,
	roofAccess: boolean?, -- rampe jusqu'au toit
	color: Color3?,
	material: string?,
	group: string?,
	name: string?,
}

export type BuildingInfo = {
	levels: { number }, -- hauteur de chaque niveau (rez-de-chaussée, étages, toit)
	spots: { { Vector3 } }, -- emplacements libres par niveau (caisses…)
	roof: number,
}

-- Palette greybox commune.
LayoutBuilder.colors = {
	concrete = Color3.fromRGB(96, 98, 104),
	darkConcrete = Color3.fromRGB(62, 64, 70),
	metal = Color3.fromRGB(84, 88, 96),
	rust = Color3.fromRGB(120, 78, 52),
	sand = Color3.fromRGB(196, 170, 120),
	rock = Color3.fromRGB(140, 112, 84),
	floor = Color3.fromRGB(70, 72, 78),
	cyan = Color3.fromRGB(0, 229, 255),
	magenta = Color3.fromRGB(255, 46, 196),
	orange = Color3.fromRGB(255, 138, 0),
	red = Color3.fromRGB(255, 59, 59),
	green = Color3.fromRGB(57, 255, 20),
	toxic = Color3.fromRGB(120, 255, 90),
	white = Color3.fromRGB(230, 236, 240),
}

local Builder = {}
Builder.__index = Builder

export type Builder = typeof(setmetatable(
	{} :: {
		layout: Layout,
		defaultColor: Color3,
		defaultMaterial: string,
	},
	Builder
))

function LayoutBuilder.new(defaultColor: Color3?, defaultMaterial: string?): Builder
	return setmetatable({
		layout = { parts = {}, markers = {}, hazards = {}, collapses = {}, data = {} },
		defaultColor = defaultColor or LayoutBuilder.colors.concrete,
		defaultMaterial = defaultMaterial or "Concrete",
	}, Builder)
end

export type PartOptions = {
	transparency: number?,
	collide: boolean?,
	query: boolean?,
	shape: string?,
	group: string?,
	tags: { string }?,
	attributes: { [string]: any }?,
}

function Builder.part(
	self: Builder,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3?,
	material: string?,
	options: PartOptions?
): PartSpec
	local opts: PartOptions = options or {}
	local spec: PartSpec = {
		name = name,
		size = size,
		cframe = cframe,
		color = color or self.defaultColor,
		material = material or self.defaultMaterial,
		transparency = opts.transparency,
		collide = opts.collide,
		query = opts.query,
		shape = opts.shape,
		group = opts.group,
		tags = opts.tags,
		attributes = opts.attributes,
	}
	table.insert(self.layout.parts, spec)
	return spec
end

-- Boîte alignée sur les axes, posée sur `base` (sol par défaut).
function Builder.block(
	self: Builder,
	name: string,
	x: number,
	z: number,
	w: number,
	d: number,
	h: number,
	color: Color3?,
	material: string?,
	options: (PartOptions & { base: number? })?
): PartSpec
	local base = if options and options.base then options.base else 0
	return self:part(name, Vector3.new(w, h, d), CFrame.new(x, base + h / 2, z), color, material, options)
end

-- Rectangle horizontal (dalle) entre deux coins, dessus à la hauteur `top`.
function Builder.slab(
	self: Builder,
	name: string,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	top: number,
	color: Color3?,
	material: string?,
	options: PartOptions?
): PartSpec?
	local w, d = math.abs(x1 - x0), math.abs(z1 - z0)
	if w < 0.5 or d < 0.5 then
		return nil
	end
	return self:part(
		name,
		Vector3.new(w, 1, d),
		CFrame.new((x0 + x1) / 2, top - 0.5, (z0 + z1) / 2),
		color,
		material,
		options
	)
end

-- Planche inclinée de `from` à `to` (dessus de la planche aux deux extrémités).
function Builder.ramp(
	self: Builder,
	name: string,
	from: Vector3,
	to: Vector3,
	width: number,
	color: Color3?,
	material: string?,
	options: PartOptions?
): PartSpec
	local a, b = from - Vector3.new(0, 0.5, 0), to - Vector3.new(0, 0.5, 0)
	local length = (b - a).Magnitude
	return self:part(name, Vector3.new(width, 1, length), CFrame.lookAt((a + b) / 2, b), color, material, options)
end

--[[
	Mur (le long de l'axe x ou z) avec une ouverture éventuelle :
	`gap` = { offset (le long du mur), width, bottom, top }.
]]
function Builder.wall(
	self: Builder,
	name: string,
	center: Vector3, -- centre au sol du mur
	length: number,
	height: number,
	axis: string, -- "x" : mur parallèle à l'axe x ; "z" : parallèle à z
	gap: { offset: number, width: number, bottom: number, top: number }?,
	color: Color3?,
	material: string?,
	options: PartOptions?
)
	local thickness = 1
	local function piece(suffix: string, along0: number, along1: number, y0: number, y1: number)
		local len, h = along1 - along0, y1 - y0
		if len < 0.2 or h < 0.2 then
			return
		end
		local mid = (along0 + along1) / 2
		local size = if axis == "x" then Vector3.new(len, h, thickness) else Vector3.new(thickness, h, len)
		local position = if axis == "x"
			then Vector3.new(center.X + mid, center.Y + (y0 + y1) / 2, center.Z)
			else Vector3.new(center.X, center.Y + (y0 + y1) / 2, center.Z + mid)
		self:part(name .. suffix, size, CFrame.new(position), color, material, options)
	end
	local half = length / 2
	if gap == nil then
		piece("", -half, half, 0, height)
		return
	end
	local g0 = math.clamp(gap.offset - gap.width / 2, -half, half)
	local g1 = math.clamp(gap.offset + gap.width / 2, -half, half)
	piece("_L", -half, g0, 0, height)
	piece("_R", g1, half, 0, height)
	piece("_B", g0, g1, 0, gap.bottom)
	piece("_T", g0, g1, math.min(gap.top, height), height)
end

--[[
	Bâtiment greybox : murs (portes au rez-de-chaussée, fenêtres aux étages),
	dalles d'étage et rampes intérieures en zigzag (côtés sud / nord en
	alternance), toit accessible en option. Retourne les hauteurs de chaque
	niveau et des emplacements libres (hors trémies et rampes).
]]
function Builder.building(self: Builder, spec: BuildingSpec): BuildingInfo
	local x, z, w, d = spec.x, spec.z, spec.w, spec.d
	local base = spec.base or 0
	local fh = spec.floorHeight or 14
	local color = spec.color or self.defaultColor
	local material = spec.material or self.defaultMaterial
	local name = spec.name or "Building"
	local opts: PartOptions = { group = spec.group }
	local doors = spec.doors or { "s", "n" }
	local floors = math.max(1, spec.floors)
	local run = math.min(28, w - 8) -- longueur horizontale d'une rampe
	local strip = 7 -- bande des rampes le long des murs sud / nord

	local function hasDoor(side: string): boolean
		return table.find(doors, side) ~= nil
	end

	-- Murs, niveau par niveau.
	for level = 0, floors - 1 do
		local y = base + level * fh
		for _, side in { "s", "n", "e", "w" } do
			local gap = nil
			if level == 0 and hasDoor(side) then
				-- Portes sud / nord décalées vers l'est (les rampes partent de l'ouest).
				local offset = if side == "s" or side == "n" then w / 4 else 0
				gap = { offset = offset, width = 8, bottom = 0, top = 9 }
			elseif spec.windows ~= false and (side == "e" or side == "w" or level > 0) then
				gap = { offset = 0, width = 6, bottom = 4, top = 9 }
			end
			local center, length, axis
			if side == "s" then
				center, length, axis = Vector3.new(x, y, z - d / 2), w, "x"
			elseif side == "n" then
				center, length, axis = Vector3.new(x, y, z + d / 2), w, "x"
			elseif side == "e" then
				center, length, axis = Vector3.new(x + w / 2, y, z), d, "z"
			else
				center, length, axis = Vector3.new(x - w / 2, y, z), d, "z"
			end
			self:wall(`{name}_{side}{level}`, center, length, fh, axis, gap, color, material, opts)
		end
	end

	-- Dalles (étages et toit), avec la trémie de la rampe qui arrive du niveau inférieur.
	local levels = { base }
	for level = 1, floors do
		local top = base + level * fh
		table.insert(levels, top)
		local ramped = level < floors or spec.roofAccess == true
		local south = (level - 1) % 2 == 0
		local x0, x1 = x - w / 2, x + w / 2
		local z0, z1 = z - d / 2, z + d / 2
		if not ramped then
			self:slab(`{name}_floor{level}`, x0, z0, x1, z1, top, LayoutBuilder.colors.floor, material, opts)
			continue
		end
		local holeEnd = x0 + 3 + run
		if south then
			self:slab(`{name}_floor{level}a`, x0, z0 + strip, x1, z1, top, LayoutBuilder.colors.floor, material, opts)
			self:slab(
				`{name}_floor{level}b`,
				holeEnd,
				z0,
				x1,
				z0 + strip,
				top,
				LayoutBuilder.colors.floor,
				material,
				opts
			)
		else
			self:slab(`{name}_floor{level}a`, x0, z0, x1, z1 - strip, top, LayoutBuilder.colors.floor, material, opts)
			self:slab(
				`{name}_floor{level}b`,
				holeEnd,
				z1 - strip,
				x1,
				z1,
				top,
				LayoutBuilder.colors.floor,
				material,
				opts
			)
		end
		local zs = if south then z0 + 4 else z1 - 4
		self:ramp(
			`{name}_ramp{level}`,
			Vector3.new(x0 + 2 + run, top - fh, zs),
			Vector3.new(x0 + 2, top, zs),
			6,
			LayoutBuilder.colors.darkConcrete,
			material,
			opts
		)
	end

	-- Emplacements libres sur chaque niveau (hors bandes des rampes).
	local spots: { { Vector3 } } = {}
	local inner = math.max(1, d / 2 - 9)
	for _, y in levels do
		table.insert(spots, {
			Vector3.new(x + w / 2 - 4, y, z + inner),
			Vector3.new(x + w / 2 - 4, y, z - inner),
			Vector3.new(x, y, z),
			Vector3.new(x - w / 2 + 6, y, z),
		})
	end
	return { levels = levels, spots = spots, roof = base + floors * fh }
end

-- Repères ----------------------------------------------------------------------

function Builder.marker(self: Builder, tag: string, position: Vector3, attributes: { [string]: any }?)
	table.insert(self.layout.markers, { tag = tag, cframe = CFrame.new(position), attributes = attributes })
end

function Builder.crate(self: Builder, position: Vector3, crateType: string)
	self:marker("CrateSpawn", position, { CrateType = crateType })
end

function Builder.deploySpawn(self: Builder, position: Vector3)
	self:marker("DeploySpawn", position + Vector3.new(0, 3, 0))
end

function Builder.extraction(self: Builder, position: Vector3, nameKey: string)
	self:marker("ExtractionPoint", position + Vector3.new(0, 0.2, 0), { NameKey = nameKey })
end

function Builder.accelerator(self: Builder, position: Vector3)
	self:marker("AcceleratorSpot", position + Vector3.new(0, 0.2, 0))
end

function Builder.riskZone(self: Builder, position: Vector3, radius: number, main: boolean)
	self:marker("RiskZone", position + Vector3.new(0, 1, 0), { Main = main, Radius = radius })
end

function Builder.robotSpawn(self: Builder, position: Vector3, attributes: { [string]: any }?)
	local attrs = attributes or { Garrison = false }
	self:marker("RobotSpawn", position + Vector3.new(0, 1, 0), attrs)
end

function Builder.hazard(self: Builder, hazard: Hazard)
	table.insert(self.layout.hazards, hazard)
end

-- Sol de la carte et murs d'enceinte.
function Builder.ground(self: Builder, size: number, color: Color3, material: string)
	self:part("Ground", Vector3.new(size, 4, size), CFrame.new(0, -2, 0), color, material)
	self:boundary(size)
end

function Builder.boundary(self: Builder, size: number)
	local half = size / 2
	for index, offset in
		{ Vector3.new(half, 0, 0), Vector3.new(-half, 0, 0), Vector3.new(0, 0, half), Vector3.new(0, 0, -half) }
	do
		local alongX = offset.X == 0
		self:part(
			"Boundary" .. index,
			if alongX then Vector3.new(size + 4, 120, 2) else Vector3.new(2, 120, size + 4),
			CFrame.new(offset + Vector3.new(0, 60, 0)),
			LayoutBuilder.colors.darkConcrete,
			"Concrete",
			{ transparency = 0.2 }
		)
	end
end

-- 8 points de départ régulièrement répartis en bordure.
function Builder.borderSpawns(self: Builder, size: number, margin: number, angleOffset: number?)
	local radius = size / 2 - margin
	for index = 1, 8 do
		local angle = (index - 1) / 8 * math.pi * 2 + (angleOffset or math.pi / 8)
		-- Projection sur le carré : les points restent près des bords.
		local cx, cz = math.cos(angle), math.sin(angle)
		local scale = radius / math.max(math.abs(cx), math.abs(cz))
		self:deploySpawn(Vector3.new(cx * scale, 0, cz * scale))
	end
end

export type Reserved = { x: number, z: number, r: number }

local function isReserved(reserved: { Reserved }, x: number, z: number, margin: number): boolean
	for _, area in reserved do
		local dx, dz = x - area.x, z - area.z
		if dx * dx + dz * dz < (area.r + margin) ^ 2 then
			return true
		end
	end
	return false
end

export type CitySpec = {
	from: number,
	to: number,
	step: number, -- les centres de bâtiments sont sur la grille, les rues entre deux
	reserved: { Reserved },
	chance: number,
	size: { min: number, max: number },
	floors: { min: number, max: number },
	crateChance: number,
	crateType: string,
	color: Color3?,
	material: string?,
	prefix: string,
}

--[[
	Bâtiments de remplissage sur une grille (centres sur les multiples de
	`step`), hors zones réservées. Les rues passent à mi-chemin entre deux
	centres : la taille maximale doit rester inférieure à `step` - 12.
]]
function Builder.cityGrid(self: Builder, rng: Rng, spec: CitySpec): { BuildingInfo }
	local infos = {}
	local index = 0
	local x = spec.from
	while x <= spec.to do
		local z = spec.from
		while z <= spec.to do
			if not isReserved(spec.reserved, x, z, spec.size.max / 2) and rng:NextNumber() < spec.chance then
				index += 1
				local w = rng:NextInteger(math.floor(spec.size.min / 2), math.floor(spec.size.max / 2)) * 2
				local d = rng:NextInteger(math.floor(spec.size.min / 2), math.floor(spec.size.max / 2)) * 2
				local sides = { "n", "s", "e", "w" }
				local first = table.remove(sides, rng:NextInteger(1, #sides)) :: string
				local second = table.remove(sides, rng:NextInteger(1, #sides)) :: string
				local info = self:building({
					x = x,
					z = z,
					w = w,
					d = d,
					floors = rng:NextInteger(spec.floors.min, spec.floors.max),
					doors = { first, second },
					color = spec.color,
					material = spec.material,
					name = `{spec.prefix}{index}`,
				})
				if rng:NextNumber() < spec.crateChance then
					local level = rng:NextInteger(1, #info.levels - 1)
					local spots = info.spots[level]
					self:crate(spots[rng:NextInteger(1, #spots)], spec.crateType)
				end
				table.insert(infos, info)
			end
			z += spec.step
		end
		x += spec.step
	end
	return infos
end

-- Positions des carrefours (entre les centres de la grille), hors zones réservées.
function LayoutBuilder.intersections(from: number, to: number, step: number, reserved: { Reserved }): { Vector3 }
	local points = {}
	local x = from + step / 2
	while x < to do
		local z = from + step / 2
		while z < to do
			if not isReserved(reserved, x, z, 6) then
				table.insert(points, Vector3.new(x, 0, z))
			end
			z += step
		end
		x += step
	end
	return points
end

-- Points libres tirés au hasard dans un carré, hors zones réservées (et
-- espacés d'au moins `spacing` entre eux).
function LayoutBuilder.freePoints(
	rng: Rng,
	count: number,
	half: number,
	reserved: { Reserved },
	spacing: number
): { Vector3 }
	local points: { Vector3 } = {}
	local attempts = 0
	while #points < count and attempts < count * 60 do
		attempts += 1
		local x = math.floor(rng:NextNumber(-half, half))
		local z = math.floor(rng:NextNumber(-half, half))
		if not isReserved(reserved, x, z, 4) then
			local ok = true
			for _, other in points do
				if (other.X - x) ^ 2 + (other.Z - z) ^ 2 < spacing * spacing then
					ok = false
					break
				end
			end
			if ok then
				table.insert(points, Vector3.new(x, 0, z))
			end
		end
	end
	return points
end

-- Mélange en place (Fisher-Yates).
function LayoutBuilder.shuffle<T>(rng: Rng, list: { T }): { T }
	for index = #list, 2, -1 do
		local swap = rng:NextInteger(1, index)
		list[index], list[swap] = list[swap], list[index]
	end
	return list
end

function Builder.finish(self: Builder): Layout
	return self.layout
end

return LayoutBuilder
