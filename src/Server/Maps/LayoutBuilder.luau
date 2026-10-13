--!strict
--[[
	LayoutBuilder : description PURE d'une carte (pièces, lumières, particules,
	repères, zones dangereuses, effondrements). Aucune Instance n'est créée
	ici : MapRenderer s'en charge. Les cartes peuvent ainsi être vérifiées par
	des tests (nombre de repères, caisses posées sur un sol, décor qui ne
	recouvre aucun repère…).

	Le constructeur tient un index spatial des pièces solides : l'habillage
	(Props, Dress) demande `isFree` avant de poser un décor, pour ne jamais
	recouvrir une caisse, une extraction, une porte ou un autre décor.

	Coordonnées LOCALES : x / z autour du centre de la carte, y = hauteur
	(le sol de la carte est à y = 0). Le décalage vers `Config.Maps.origin`
	est appliqué au rendu.
]]

local LayoutBuilder = {}

export type LightSpec = {
	kind: string?, -- "point" (défaut) | "spot" | "surface"
	color: Color3,
	range: number,
	brightness: number,
	face: string?, -- nom d'Enum.NormalId (spot / surface)
	angle: number?,
	flicker: boolean?, -- grésille (animé côté client)
	emergency: boolean?, -- reste allumée pendant une coupure de courant
}

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
	light: LightSpec?,
	emitter: string?, -- préréglage de particules (voir MapRenderer.EMITTERS)
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

--[[
	Générateur aléatoire des cartes (Park-Miller). Les cartes ne passent PAS
	par `Random.new` : le même code doit donner la même carte dans Studio et
	dans les tests (Lune), sinon les tests vérifieraient une autre carte que
	celle qui est jouée.
]]
function LayoutBuilder.random(seed: number): Rng
	local state = math.floor(seed) % 2147483647 + 1
	local function nextValue(): number
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
	local rng = {}
	function rng.NextNumber(_self: any, min: number?, max: number?): number
		local a, b = min or 0, max or 1
		return a + (b - a) * nextValue()
	end
	function rng.NextInteger(_self: any, min: number, max: number): number
		return min + math.floor(nextValue() * (max - min + 1))
	end
	return rng
end

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
	-- Emprise (pour l'habillage intérieur et les toits).
	x: number,
	z: number,
	w: number,
	d: number,
	doors: { string },
	roofAccess: boolean,
	group: string?,
}

-- Zone à garder libre (porte, passage, emprise d'un effondrement) : cylindre vertical.
export type KeepOut = { x: number, z: number, r: number, y0: number, y1: number }

type Box = { x0: number, x1: number, y0: number, y1: number, z0: number, z1: number }

-- Préréglages de particules connus de MapRenderer (champ `emitter` d'une pièce).
LayoutBuilder.emitterNames = { "smoke", "steam", "fire", "embers", "motes", "dust", "coldfog", "sparks" }

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
		keepOuts: { KeepOut },
		big: { Box },
		grid: { [number]: { Box } },
	},
	Builder
))

function LayoutBuilder.new(defaultColor: Color3?, defaultMaterial: string?): Builder
	return setmetatable({
		layout = { parts = {}, markers = {}, hazards = {}, collapses = {}, data = {} },
		defaultColor = defaultColor or LayoutBuilder.colors.concrete,
		defaultMaterial = defaultMaterial or "Concrete",
		keepOuts = {},
		big = {},
		grid = {},
	}, Builder)
end

-- Index spatial des pièces solides ---------------------------------------------

local CELL = 32
local BIG = 160 -- au-delà : pièce testée à chaque requête (sol, enceinte, grands halls)

local function cellKey(cx: number, cz: number): number
	return (cx + 512) * 1024 + (cz + 512)
end

-- Boîte englobante (alignée sur les axes) d'une pièce, rotation comprise.
local function boundsOf(size: Vector3, cframe: CFrame): Box
	local r, u, l = cframe.RightVector, cframe.UpVector, cframe.LookVector
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	local ex = math.abs(r.X) * hx + math.abs(u.X) * hy + math.abs(l.X) * hz
	local ey = math.abs(r.Y) * hx + math.abs(u.Y) * hy + math.abs(l.Y) * hz
	local ez = math.abs(r.Z) * hx + math.abs(u.Z) * hy + math.abs(l.Z) * hz
	local p = cframe.Position
	return { x0 = p.X - ex, x1 = p.X + ex, y0 = p.Y - ey, y1 = p.Y + ey, z0 = p.Z - ez, z1 = p.Z + ez }
end

local function indexBox(self: Builder, box: Box)
	if box.x1 - box.x0 > BIG or box.z1 - box.z0 > BIG then
		table.insert(self.big, box)
		return
	end
	for cx = math.floor(box.x0 / CELL), math.floor(box.x1 / CELL) do
		for cz = math.floor(box.z0 / CELL), math.floor(box.z1 / CELL) do
			local key = cellKey(cx, cz)
			local cell = self.grid[key]
			if cell == nil then
				cell = {}
				self.grid[key] = cell
			end
			table.insert(cell, box)
		end
	end
end

local function overlaps(box: Box, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number): boolean
	return box.x0 < x1 and box.x1 > x0 and box.y0 < y1 and box.y1 > y0 and box.z0 < z1 and box.z1 > z0
end

-- Une pièce solide occupe-t-elle ce volume ?
function Builder.occupied(
	self: Builder,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number
): boolean
	for _, box in self.big do
		if overlaps(box, x0, x1, y0, y1, z0, z1) then
			return true
		end
	end
	for cx = math.floor(x0 / CELL), math.floor(x1 / CELL) do
		for cz = math.floor(z0 / CELL), math.floor(z1 / CELL) do
			local cell = self.grid[cellKey(cx, cz)]
			if cell then
				for _, box in cell do
					if overlaps(box, x0, x1, y0, y1, z0, z1) then
						return true
					end
				end
			end
		end
	end
	return false
end

-- Zone à garder libre de tout décor (porte, passage…).
function Builder.keepOut(self: Builder, x: number, z: number, r: number, y0: number?, y1: number?)
	table.insert(self.keepOuts, { x = x, z = z, r = r, y0 = y0 or -1000, y1 = y1 or 1000 })
end

local MARKER_CLEARANCE = 4

--[[
	Peut-on poser un décor d'emprise circulaire `radius` et de hauteur
	`height`, base à (x, y, z) ? Faux s'il toucherait une pièce solide, un
	repère (caisse, extraction, Accélérateur, départ, patrouille) ou une zone
	à garder libre.
]]
function Builder.isFree(self: Builder, x: number, y: number, z: number, radius: number, height: number): boolean
	for _, zone in self.keepOuts do
		if y + height > zone.y0 and y < zone.y1 then
			local dx, dz = x - zone.x, z - zone.z
			local reach = zone.r + radius
			if dx * dx + dz * dz < reach * reach then
				return false
			end
		end
	end
	for _, marker in self.layout.markers do
		if marker.tag ~= "RiskZone" then
			local p = marker.cframe.Position
			if p.Y > y - 6 and p.Y < y + height + 6 then
				local dx, dz = x - p.X, z - p.Z
				local reach = radius + MARKER_CLEARANCE
				if dx * dx + dz * dz < reach * reach then
					return false
				end
			end
		end
	end
	return not self:occupied(x - radius, x + radius, y + 0.3, y + height, z - radius, z + radius)
end

export type PartOptions = {
	transparency: number?,
	collide: boolean?,
	query: boolean?,
	shape: string?,
	group: string?,
	tags: { string }?,
	attributes: { [string]: any }?,
	light: LightSpec?,
	emitter: string?,
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
		light = opts.light,
		emitter = opts.emitter,
	}
	table.insert(self.layout.parts, spec)
	if spec.collide ~= false then
		indexBox(self, boundsOf(size, cframe))
	end
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
			if level == 0 and hasDoor(side) then
				-- Seuil de la porte (dedans et dehors) : jamais de décor.
				local alongX = side == "s" or side == "n"
				self:keepOut(center.X + (if alongX then w / 4 else 0), center.Z, 7, base - 1, base + 10)
			end
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
		-- Pied de la rampe et palier : passages à garder libres de tout décor.
		self:keepOut(x0 + 2 + run + 4, zs, 5, top - fh - 1, top - fh + 9)
		self:keepOut(x0 + 5, if south then z0 + strip + 3 else z1 - strip - 3, 5, top - 1, top + 9)
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
	return {
		levels = levels,
		spots = spots,
		roof = base + floors * fh,
		x = x,
		z = z,
		w = w,
		d = d,
		doors = doors,
		roofAccess = spec.roofAccess == true,
		group = spec.group,
	}
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
