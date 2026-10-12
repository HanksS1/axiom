--!strict
--[[
	Kit : petits outils de construction du Terminus (décor et PNJ).

	Les éléments animés portent un TAG CollectionService (et des attributs) :
	c'est le client (HubAmbienceController) qui les anime, pour que le
	serveur ne fasse aucun travail par image.

	| Tag        | Animation côté client                              |
	|------------|----------------------------------------------------|
	| Flicker    | néon / lumière qui grésille                        |
	| Spin       | rotation continue (Speed, en tours par seconde)    |
	| Sway       | balancement d'une lampe suspendue                  |
	| Bob        | flottement vertical                                |
	| Hologram   | transparence instable                              |
	| Orbit      | orbite autour d'un point (Center, Radius, Speed)   |
	| Drone      | ronde en cercle (Center, Radius, Speed, Height)    |
	| Critter    | va-et-vient d'un rongeur mécanique (PointA, PointB)|
	| SparkBurst | gerbe d'étincelles périodique                      |
	| HubNpc     | PNJ : respiration, regard, salutations             |
	Attribut `TextKey` : texte localisé côté client (enseignes, affiches).
]]

local CollectionService = game:GetService("CollectionService")

local Kit = {}

export type PartOptions = {
	transparency: number?,
	collide: boolean?,
	query: boolean?,
	shape: EnumItem?,
	tag: string?,
	attributes: { [string]: any }?,
	castShadow: boolean?,
}

function Kit.part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: EnumItem,
	options: PartOptions?
): Part
	local opts: PartOptions = options or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material :: any
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Transparency = opts.transparency or 0
	p.CanCollide = opts.collide ~= false
	p.CanQuery = opts.query ~= false
	p.CanTouch = false
	if opts.shape then
		p.Shape = opts.shape :: any
	end
	if material == Enum.Material.Neon or opts.castShadow == false then
		p.CastShadow = false
	end
	if opts.attributes then
		for key, value in opts.attributes do
			p:SetAttribute(key, value)
		end
	end
	if opts.tag then
		CollectionService:AddTag(p, opts.tag)
	end
	p.Parent = parent
	return p
end

-- Décor non bloquant (ni collision, ni tirs).
function Kit.decor(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: EnumItem,
	options: PartOptions?
): Part
	local opts: PartOptions = table.clone(options or {})
	opts.collide = false
	opts.query = false
	return Kit.part(parent, name, size, cframe, color, material, opts)
end

-- Cylindre vertical (l'axe des cylindres Roblox est X).
function Kit.cylinder(
	parent: Instance,
	name: string,
	height: number,
	diameter: number,
	position: Vector3,
	color: Color3,
	material: EnumItem,
	options: PartOptions?
): Part
	local opts: PartOptions = table.clone(options or {})
	opts.shape = Enum.PartType.Cylinder
	return Kit.part(
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		material,
		opts
	)
end

function Kit.tag(instance: Instance, tag: string, attributes: { [string]: any }?)
	if attributes then
		for key, value in attributes do
			instance:SetAttribute(key, value)
		end
	end
	CollectionService:AddTag(instance, tag)
end

function Kit.light(parent: BasePart, color: Color3, range: number, brightness: number, flicker: boolean?): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = parent
	if flicker then
		Kit.tag(light, "Flicker")
	end
	return light
end

export type EmitterOptions = {
	color: ColorSequence,
	rate: number,
	lifetime: NumberRange,
	speed: NumberRange,
	size: NumberSequence,
	transparency: NumberSequence?,
	acceleration: Vector3?,
	spread: Vector2?,
	lightEmission: number?,
	texture: string?,
	direction: EnumItem?,
}

-- Émetteur de particules (feu, fumée, vapeur, gouttes, poussière).
function Kit.emitter(parent: Instance, name: string, options: EmitterOptions): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Color = options.color
	emitter.Rate = options.rate
	emitter.Lifetime = options.lifetime
	emitter.Speed = options.speed
	emitter.Size = options.size
	emitter.Transparency = options.transparency or NumberSequence.new(0, 1)
	emitter.Acceleration = options.acceleration or Vector3.zero
	emitter.SpreadAngle = options.spread or Vector2.new(15, 15)
	emitter.LightEmission = options.lightEmission or 0
	if options.texture then
		emitter.Texture = options.texture
	end
	if options.direction then
		emitter.EmissionDirection = options.direction :: any
	end
	emitter.Parent = parent
	return emitter
end

-- Texte sur une face (enseigne, affiche, tag), localisé côté client.
function Kit.text(
	part: BasePart,
	face: EnumItem,
	textKey: string,
	color: Color3,
	font: EnumItem?,
	background: Color3?,
	rotation: number?
): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face :: any
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.2
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = if background then 0 else 1
	label.BackgroundColor3 = background or Color3.new()
	label.TextScaled = true
	label.Font = (font or Enum.Font.GothamBlack) :: any
	label.TextColor3 = color
	label.Rotation = rotation or 0
	label.Text = ""
	label:SetAttribute("TextKey", textKey)
	label.Parent = gui
	return gui
end

-- Soude une pièce (non ancrée) à une autre.
function Kit.weld(base: BasePart, part: BasePart)
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = base
	weld.Part1 = part
	weld.Parent = part
end

return Kit
