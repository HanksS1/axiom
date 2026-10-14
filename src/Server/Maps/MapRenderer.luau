--!strict
--[[
	MapRenderer : crée les Instances d'une carte décrite par LayoutBuilder.

	- Les pièces sont ancrées, groupées par `group` (modèles nommés, pour
	  les effondrements), décalées vers `origin`.
	- Lumières et particules décrites par la carte (`light`, `emitter`) :
	  · lumière qui grésille : tag « Flicker » (animée côté client) ;
	  · lumière sur secteur : tag « PowerLight » (éteinte pendant une coupure
	    de courant) ; une lumière de secours (`emergency`) reste allumée.
	- Les repères passent par MapService.placeMarker (tags CollectionService).
	- La création est étalée (quelques centaines de pièces par image) pour
	  ne pas figer le serveur.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local LayoutBuilder = require(script.Parent.LayoutBuilder)
local MapService = require(script.Parent.Parent.Services.MapService)

local MapRenderer = {}

local PER_FRAME = 400

-- Lumières de la carte en cours de rendu : × intensité, × portée (Config.Maps.*.lightScale).
type LightScale = { brightness: number, range: number }
local NO_SCALE: LightScale = { brightness = 1, range = 1 }
local lightScale: LightScale = NO_SCALE

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

export type Emitter = {
	color: ColorSequence,
	rate: number,
	lifetime: NumberRange,
	speed: NumberRange,
	size: NumberSequence,
	transparency: NumberSequence,
	acceleration: Vector3?,
	spread: number?,
	lightEmission: number?,
	texture: string?,
	face: EnumItem?,
}

local function fade(from: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, from), NumberSequenceKeypoint.new(1, 1) })
end

local function grow(from: number, to: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, from), NumberSequenceKeypoint.new(1, to) })
end

-- Préréglages de particules (débits faibles : budget mobile).
MapRenderer.EMITTERS = {
	smoke = {
		color = ColorSequence.new(Color3.fromRGB(58, 56, 58)),
		rate = 5,
		lifetime = NumberRange.new(4, 7),
		speed = NumberRange.new(3, 5),
		size = grow(2, 9),
		transparency = fade(0.55),
		acceleration = Vector3.new(1.5, 1, 0),
		spread = 12,
		texture = SMOKE,
	},
	steam = {
		color = ColorSequence.new(Color3.fromRGB(220, 226, 232)),
		rate = 6,
		lifetime = NumberRange.new(1.5, 2.6),
		speed = NumberRange.new(3, 6),
		size = grow(0.8, 4),
		transparency = fade(0.6),
		spread = 18,
		texture = SMOKE,
	},
	fire = {
		color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 70, 20)),
		rate = 18,
		lifetime = NumberRange.new(0.4, 0.9),
		speed = NumberRange.new(3, 5),
		size = grow(1.4, 0),
		transparency = fade(0.1),
		spread = 14,
		lightEmission = 1,
	},
	embers = {
		color = ColorSequence.new(Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 60, 20)),
		rate = 6,
		lifetime = NumberRange.new(2, 4),
		speed = NumberRange.new(2, 6),
		size = grow(0.35, 0),
		transparency = fade(0),
		acceleration = Vector3.new(0, 2, 0),
		spread = 40,
		lightEmission = 1,
	},
	motes = {
		color = ColorSequence.new(Color3.fromRGB(150, 255, 110)),
		rate = 5,
		lifetime = NumberRange.new(3, 6),
		speed = NumberRange.new(0.5, 2),
		size = grow(0.3, 0),
		transparency = fade(0.2),
		acceleration = Vector3.new(0, 0.6, 0),
		spread = 180,
		lightEmission = 1,
	},
	dust = {
		color = ColorSequence.new(Color3.fromRGB(196, 172, 128)),
		rate = 4,
		lifetime = NumberRange.new(4, 7),
		speed = NumberRange.new(4, 8),
		size = grow(3, 10),
		transparency = fade(0.8),
		acceleration = Vector3.new(3, 0, 1),
		spread = 60,
		texture = SMOKE,
		face = Enum.NormalId.Right,
	},
	coldfog = {
		color = ColorSequence.new(Color3.fromRGB(205, 228, 240)),
		rate = 4,
		lifetime = NumberRange.new(3, 5),
		speed = NumberRange.new(1, 2.5),
		size = grow(2, 7),
		transparency = fade(0.75),
		acceleration = Vector3.new(0, -0.6, 0),
		spread = 70,
		texture = SMOKE,
		face = Enum.NormalId.Bottom,
	},
	sparks = {
		color = ColorSequence.new(Color3.fromRGB(255, 230, 150), Color3.fromRGB(255, 120, 30)),
		rate = 0, -- par gerbes (tag SparkBurst, côté client)
		lifetime = NumberRange.new(0.3, 0.8),
		speed = NumberRange.new(8, 16),
		size = grow(0.25, 0),
		transparency = fade(0),
		acceleration = Vector3.new(0, -40, 0),
		spread = 60,
		lightEmission = 1,
	},
} :: { [string]: Emitter }

for _, name in LayoutBuilder.emitterNames do
	assert(MapRenderer.EMITTERS[name] ~= nil, `préréglage de particules manquant : {name}`)
end

local function enumOf(enum: any, name: string?, fallback: EnumItem): EnumItem
	if name == nil then
		return fallback
	end
	local ok, item = pcall(function()
		return enum[name]
	end)
	return if ok and item then item else fallback
end

local function addLight(part: BasePart, spec: LayoutBuilder.LightSpec)
	local light: Light
	if spec.kind == "spot" then
		local spot = Instance.new("SpotLight")
		spot.Face = enumOf(Enum.NormalId, spec.face, Enum.NormalId.Bottom) :: any
		spot.Angle = spec.angle or 70
		spot.Range = spec.range
		light = spot
	elseif spec.kind == "surface" then
		local surface = Instance.new("SurfaceLight")
		surface.Face = enumOf(Enum.NormalId, spec.face, Enum.NormalId.Front) :: any
		surface.Angle = spec.angle or 120
		surface.Range = spec.range
		light = surface
	else
		local point = Instance.new("PointLight")
		point.Range = spec.range
		light = point
	end
	light.Color = spec.color
	light.Brightness = spec.brightness * lightScale.brightness
	if light:IsA("PointLight") or light:IsA("SpotLight") or light:IsA("SurfaceLight") then
		light.Range = math.min(60, spec.range * lightScale.range)
	end
	light.Shadows = false
	light.Parent = part
	if spec.flicker then
		CollectionService:AddTag(light, "Flicker")
	end
	if not spec.emergency then
		CollectionService:AddTag(light, "PowerLight")
	end
end

local function addEmitter(part: BasePart, preset: string)
	local def = MapRenderer.EMITTERS[preset]
	if def == nil then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = preset
	emitter.Color = def.color
	emitter.Rate = def.rate
	emitter.Lifetime = def.lifetime
	emitter.Speed = def.speed
	emitter.Size = def.size
	emitter.Transparency = def.transparency
	emitter.Acceleration = def.acceleration or Vector3.zero
	emitter.SpreadAngle = Vector2.new(def.spread or 15, def.spread or 15)
	emitter.LightEmission = def.lightEmission or 0
	emitter.EmissionDirection = (def.face or Enum.NormalId.Top) :: any
	if def.texture then
		emitter.Texture = def.texture
	end
	emitter.Parent = part
	if preset == "sparks" then
		CollectionService:AddTag(part, "SparkBurst")
	end
end

local function materialOf(name: string): EnumItem
	local ok, material = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and material then material else Enum.Material.Concrete
end

-- Crée une pièce (sans parent).
function MapRenderer.createPart(spec: LayoutBuilder.PartSpec, origin: Vector3): BasePart
	local part = Instance.new("Part")
	part.Name = spec.name
	if spec.shape then
		local ok, shape = pcall(function()
			return (Enum.PartType :: any)[spec.shape]
		end)
		if ok and shape then
			part.Shape = shape
		end
	end
	part.Size = spec.size
	part.CFrame = CFrame.new(origin) * spec.cframe
	part.Color = spec.color
	part.Material = materialOf(spec.material)
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Transparency = spec.transparency or 0
	part.CanCollide = spec.collide ~= false
	part.CanQuery = spec.query ~= false
	part.CanTouch = false
	if spec.material == "Neon" then
		part.CastShadow = false
	end
	if spec.attributes then
		for key, value in spec.attributes do
			part:SetAttribute(key, value)
		end
	end
	if spec.tags then
		for _, tag in spec.tags do
			CollectionService:AddTag(part, tag)
		end
	end
	if spec.light then
		addLight(part, spec.light)
	end
	if spec.emitter then
		addEmitter(part, spec.emitter)
	end
	return part
end

-- Crée des pièces sous `parent` (groupes : sous-modèles du dossier Groups).
function MapRenderer.renderParts(parts: { LayoutBuilder.PartSpec }, parent: Instance, origin: Vector3, groups: Folder?)
	local models: { [string]: Model } = {}
	for index, spec in parts do
		local part = MapRenderer.createPart(spec, origin)
		local group = spec.group
		if group and groups then
			local model = models[group] or groups:FindFirstChild(group) :: Model?
			if model == nil then
				local created = Instance.new("Model")
				created.Name = group
				created.Parent = groups
				model = created
			end
			models[group] = model :: Model
			part.Parent = model
		else
			part.Parent = parent
		end
		if index % PER_FRAME == 0 then
			task.wait()
		end
	end
end

--[[
	Construit la carte dans un dossier « Map » sous `container` et retourne ce
	dossier. Peut céder la main (étalement sur plusieurs images).
]]
function MapRenderer.render(layout: LayoutBuilder.Layout, container: Instance, origin: Vector3, mapId: string): Folder
	local def = (Config.Maps.byId :: any)[mapId]
	lightScale = if def and def.lightScale then def.lightScale else NO_SCALE
	local root = Instance.new("Folder")
	root.Name = "Map"
	root:SetAttribute("MapId", mapId)
	local geometry = Instance.new("Folder")
	geometry.Name = "Geometry"
	geometry.Parent = root
	local groups = Instance.new("Folder")
	groups.Name = "Groups"
	groups.Parent = root
	local markers = Instance.new("Folder")
	markers.Name = "Markers"
	markers.Parent = root
	MapRenderer.renderParts(layout.parts, geometry, origin, groups)
	-- Les rendus suivants (décombres, décor du Terminus) retrouvent l'échelle neutre.
	lightScale = NO_SCALE
	for _, marker in layout.markers do
		MapService.placeMarker(markers, marker.tag, CFrame.new(origin) * marker.cframe, marker.attributes)
	end
	root.Parent = container
	return root
end

return MapRenderer
