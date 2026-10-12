--!strict
--[[
	MapRenderer : crée les Instances d'une carte décrite par LayoutBuilder.

	- Les pièces sont ancrées, groupées par `group` (modèles nommés, pour
	  les effondrements), décalées vers `origin`.
	- Les repères passent par MapService.placeMarker (tags CollectionService).
	- La création est étalée (quelques centaines de pièces par image) pour
	  ne pas figer le serveur.
]]

local CollectionService = game:GetService("CollectionService")

local LayoutBuilder = require(script.Parent.LayoutBuilder)
local MapService = require(script.Parent.Parent.Services.MapService)

local MapRenderer = {}

local PER_FRAME = 400

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
	for _, marker in layout.markers do
		MapService.placeMarker(markers, marker.tag, CFrame.new(origin) * marker.cframe, marker.attributes)
	end
	root.Parent = container
	return root
end

return MapRenderer
