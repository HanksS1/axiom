--!strict
--[[
	CrateScene : ouverture d'une caisse du Holo-Bazar, en 3D (section 14.10).

	1. Des lasers (projecteurs magenta) assemblent la caisse en gros pixels,
	   puis en pixels de plus en plus fins, jusqu'à la caisse complète.
	2. Un scanner rouge la balaie de haut en bas et retour ; le bandeau de la
	   caisse prend la couleur de la rareté.
	3. La caisse tremble, le couvercle s'ouvre, une colonne de lumière à la
	   couleur de la rareté jaillit.
	4. L'objet obtenu sort de la caisse et reste à flotter au-dessus, en
	   tournant ; la caisse ouverte reste visible.

	Tout l'état est une fonction du temps écoulé (Shared/Visuals/CrateSequence) :
	« Passer » place simplement la scène à la fin.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local CrateSequence = require(Shared.Visuals.CrateSequence)
local ItemModels = require(Shared.Visuals.ItemModels)

local Create = require(script.Parent.Create)
local Theme = require(script.Parent.Theme)

local CrateScene = {}

local C = Config.Monetization.crateOpening
local TIMELINE = CrateSequence.timeline(C.phases)

local CRATE = Color3.fromRGB(46, 50, 60)
local DARK = Color3.fromRGB(22, 24, 30)
local STEEL = Color3.fromRGB(118, 124, 134)
local LASER = Theme.magenta
local SCAN = Theme.red
local FRESH = 0.25 -- secondes pendant lesquelles un pixel tout juste posé brille
local LID = 0.45 -- épaisseur du couvercle
-- Opacité maximale de la colonne de lumière : légère, pour ne jamais masquer l'objet qui en sort.
local COLUMN_OPACITY = 0.14

export type Callbacks = {
	onOpen: (() -> ())?, -- le couvercle commence à s'ouvrir (éclair à l'écran)
	onReveal: (() -> ())?, -- l'objet est sorti (nom et rareté)
}

export type Scene = {
	frame: ViewportFrame,
	skip: () -> (),
	destroy: () -> (),
}

type Pixel = { part: Part, at: number, size: Vector3 }

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function lerp(a: number, b: number, x: number): number
	return a + (b - a) * x
end

local function easeOutBack(x: number): number
	local c1, c3 = 1.4, 2.4
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

local function easeOutCubic(x: number): number
	return 1 - (1 - x) ^ 3
end

-- Pixels d'une phase de construction : chacun apparaît à son tour pendant la phase.
local function pixels(parent: Instance, center: Vector3, cell: number, phase: string): { Pixel }
	local step = CrateSequence.step(TIMELINE, phase) :: CrateSequence.Step
	local voxels = CrateSequence.voxels(C.crateSize, cell)
	local list: { Pixel } = {}
	for index, voxel in voxels do
		local p =
			part(parent, "Pixel", voxel.size * 0.94, CFrame.new(center + voxel.position), LASER, Enum.Material.Neon)
		p.Transparency = 1
		local at = step.start + (index / #voxels) * (step.finish - step.start)
		table.insert(list, { part = p, at = at, size = voxel.size * 0.94 })
	end
	return list
end

--[[
	Crée la scène dans `parent` pour le cosmétique `cosmeticId` (objet et skin)
	et la joue. `instant` : directement l'état final (ouverture rapide).
]]
function CrateScene.play(
	parent: GuiObject,
	itemId: string,
	skin: ItemModels.Skin?,
	rarityColor: Color3,
	callbacks: Callbacks,
	instant: boolean
): Scene
	local size = C.crateSize
	local height = size.Y
	local center = Vector3.new(0, height / 2, 0)

	local viewport = Create("ViewportFrame", {
		Name = "CrateScene",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(120, 124, 140),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-0.45, -1, -0.55),
		Parent = parent,
	})
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local target = Vector3.new(0, 2.9, 0)
	camera.CFrame = CFrame.lookAt(target + Vector3.new(0.42, 0.33, 0.85).Unit * 11.5, target)
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	-- Socle holographique.
	local pad = part(
		viewport,
		"Pad",
		Vector3.new(0.2, 6.4, 6.4),
		CFrame.new(0, -0.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		DARK,
		Enum.Material.Metal
	)
	pad.Shape = Enum.PartType.Cylinder
	local rim = part(
		viewport,
		"Rim",
		Vector3.new(0.12, 6.9, 6.9),
		CFrame.new(0, -0.16, 0) * CFrame.Angles(0, 0, math.rad(90)),
		LASER,
		Enum.Material.Neon
	)
	rim.Shape = Enum.PartType.Cylinder
	rim.Transparency = 0.45

	-- Projecteurs et lasers.
	local emitters: { Part } = {}
	local lasers: { Part } = {}
	for index, corner in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1) } do
		local position = Vector3.new(corner.X * (size.X / 2 + 0.7), height + 2.2, corner.Z * (size.Z / 2 + 0.7))
		local emitter =
			part(viewport, "Emitter" .. index, Vector3.one * 0.35, CFrame.new(position), LASER, Enum.Material.Neon)
		emitter.Shape = Enum.PartType.Ball
		table.insert(emitters, emitter)
		local laser = part(
			viewport,
			"Laser" .. index,
			Vector3.new(0.06, 0.06, 1),
			CFrame.new(position),
			LASER,
			Enum.Material.Neon
		)
		laser.Transparency = 1
		table.insert(lasers, laser)
	end

	local coarse = pixels(viewport, center, C.coarseCell, "coarse")
	local fine = pixels(viewport, center, C.fineCell, "fine")

	-- Caisse complète : corps (modèle pivotant à la base) et couvercle (pivotant à la charnière).
	local crate = Instance.new("Model")
	crate.Name = "Crate"
	local body = height - LID
	local solids: { Part } = {}
	local function solid(
		name: string,
		partSize: Vector3,
		position: Vector3,
		color: Color3,
		material: Enum.Material,
		into: Model
	): Part
		local p = part(into, name, partSize, CFrame.new(position), color, material)
		p.Transparency = 1
		table.insert(solids, p)
		return p
	end
	solid(
		"Body",
		Vector3.new(size.X * 0.98, body, size.Z * 0.98),
		Vector3.new(0, body / 2, 0),
		CRATE,
		Enum.Material.Metal,
		crate
	)
	for _, x in { -size.X * 0.3, size.X * 0.3 } do
		solid(
			"Band",
			Vector3.new(0.25, body + 0.02, size.Z + 0.04),
			Vector3.new(x, body / 2, 0),
			STEEL,
			Enum.Material.DiamondPlate,
			crate
		)
	end
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			solid(
				"Foot",
				Vector3.new(0.4, 0.25, 0.4),
				Vector3.new(x * (size.X / 2 - 0.25), 0.12, z * (size.Z / 2 - 0.25)),
				DARK,
				Enum.Material.Metal,
				crate
			)
		end
	end
	local strip = solid(
		"Strip",
		Vector3.new(size.X * 0.55, 0.18, 0.06),
		Vector3.new(0, body * 0.55, size.Z / 2 + 0.03),
		LASER,
		Enum.Material.Neon,
		crate
	)
	crate.WorldPivot = CFrame.new()
	crate.Parent = viewport

	local lid = Instance.new("Model")
	lid.Name = "Lid"
	local hinge = CFrame.new(0, body, -size.Z / 2)
	solid(
		"Plate",
		Vector3.new(size.X, LID, size.Z),
		hinge.Position + Vector3.new(0, LID / 2, size.Z / 2),
		CRATE,
		Enum.Material.Metal,
		lid
	)
	local lidStrip = solid(
		"LidStrip",
		Vector3.new(size.X * 0.7, 0.08, 0.06),
		hinge.Position + Vector3.new(0, LID / 2, size.Z + 0.03),
		LASER,
		Enum.Material.Neon,
		lid
	)
	lid.WorldPivot = hinge
	lid.Parent = viewport

	-- Scanner : lame rouge et halo.
	local scanBlade = part(
		viewport,
		"Scan",
		Vector3.new(size.X + 0.6, 0.06, size.Z + 0.6),
		CFrame.new(0, height, 0),
		SCAN,
		Enum.Material.Neon
	)
	scanBlade.Transparency = 1
	local scanGlow = part(
		viewport,
		"ScanGlow",
		Vector3.new(size.X + 0.9, 0.5, size.Z + 0.9),
		CFrame.new(0, height, 0),
		SCAN,
		Enum.Material.Neon
	)
	scanGlow.Transparency = 1

	-- Colonne de lumière à la couleur de la rareté.
	local column = part(
		viewport,
		"Column",
		Vector3.new(6.5, 2.4, 2.4),
		CFrame.new(0, body + 3.25, 0) * CFrame.Angles(0, 0, math.rad(90)),
		rarityColor,
		Enum.Material.Neon
	)
	column.Shape = Enum.PartType.Cylinder
	column.Transparency = 1

	-- L'objet obtenu, centré sur son origine, à l'échelle de la scène.
	local prize = Instance.new("Model")
	prize.Name = "Prize"
	local blueprint = ItemModels.blueprint(itemId)
	if blueprint then
		local middle, extent = ItemModels.bounds(blueprint)
		local scale = C.itemSize / math.max(extent.X, extent.Y, extent.Z, 0.1)
		ItemModels.place(itemId, prize, CFrame.new(), { skin = skin, scale = scale, shift = -middle })
	end
	prize.WorldPivot = CFrame.new()

	local stepOpen = CrateSequence.step(TIMELINE, "open") :: CrateSequence.Step
	local stepRise = CrateSequence.step(TIMELINE, "rise") :: CrateSequence.Step
	local fineEnd = (CrateSequence.step(TIMELINE, "fine") :: CrateSequence.Step).finish
	local solidEnd = (CrateSequence.step(TIMELINE, "solidify") :: CrateSequence.Step).finish
	local openAt = stepOpen.start + (stepOpen.finish - stepOpen.start) * 0.35
	local revealAt = stepRise.start + (stepRise.finish - stepRise.start) * 0.4

	local elapsed = 0
	local opened, revealed, cleared, solidDone = false, false, false, false

	local function showPixels(list: { Pixel }, t: number, fade: number)
		for _, pixel in list do
			local age = t - pixel.at
			local p = pixel.part
			if age < 0 then
				p.Transparency = 1
			else
				local fresh = age < FRESH
				p.Size = pixel.size * math.clamp(age / 0.12, 0.25, 1)
				p.Color = if fresh then LASER else CRATE
				p.Material = if fresh then Enum.Material.Neon else Enum.Material.Metal
				p.Transparency = fade
			end
		end
	end

	-- Le laser k vise le k-ième pixel le plus récent.
	local function aimLasers(list: { Pixel }, t: number)
		local count = 0
		for _, pixel in list do
			if pixel.at <= t then
				count += 1
			end
		end
		for k, laser in lasers do
			local pixel = list[count - (k - 1)]
			if pixel then
				local from = emitters[k].Position
				local to = pixel.part.Position
				local distance = (to - from).Magnitude
				laser.Size = Vector3.new(0.06, 0.06, distance)
				laser.CFrame = CFrame.lookAt((from + to) / 2, to)
				laser.Transparency = 0.1
			else
				laser.Transparency = 1
			end
		end
	end

	local function render(t: number)
		-- Construction (lasers, pixels de plus en plus fins).
		if not cleared then
			local fineP = CrateSequence.progress(TIMELINE, "fine", t)
			local solidP = CrateSequence.progress(TIMELINE, "solidify", t)
			showPixels(coarse, t, fineP)
			showPixels(fine, t, solidP)
			if t < fineEnd then
				aimLasers(
					if t < (CrateSequence.step(TIMELINE, "coarse") :: CrateSequence.Step).finish then coarse else fine,
					t
				)
			else
				for _, laser in lasers do
					laser.Transparency = 1
				end
			end
			for _, emitter in emitters do
				emitter.Transparency = solidP
			end
			for _, p in solids do
				p.Transparency = 1 - solidP
			end
			if t >= solidEnd then
				cleared = true
				for _, list in { coarse, fine } do
					for _, pixel in list do
						pixel.part:Destroy()
					end
				end
				for _, p in emitters do
					p:Destroy()
				end
				for _, p in lasers do
					p:Destroy()
				end
			end
		elseif not solidDone then
			solidDone = true
			for _, p in solids do
				p.Transparency = 0
			end
		end

		-- Scanner : du haut vers le bas, puis retour ; le bandeau prend la couleur de la rareté.
		local scanP = CrateSequence.progress(TIMELINE, "scan", t)
		local scanning = scanP > 0 and scanP < 1
		local sweep = 1 - math.abs(2 * scanP - 1)
		local y = lerp(height + 0.3, -0.1, sweep)
		scanBlade.CFrame = CFrame.new(0, y, 0)
		scanGlow.CFrame = CFrame.new(0, y, 0)
		scanBlade.Transparency = if scanning then 0.15 else 1
		scanGlow.Transparency = if scanning then 0.82 else 1
		local tint = math.clamp((scanP - 0.6) / 0.4, 0, 1)
		strip.Color = LASER:Lerp(rarityColor, tint)
		lidStrip.Color = strip.Color

		-- Ouverture : secousse, couvercle, colonne de lumière.
		local openP = CrateSequence.progress(TIMELINE, "open", t)
		local shake = if openP > 0 and openP < 0.35 then math.sin(t * 70) * 0.05 * (openP / 0.35) else 0
		local base = CFrame.Angles(0, 0, shake)
		crate:PivotTo(base)
		local lidOpen = easeOutBack(math.clamp((openP - 0.35) / 0.65, 0, 1))
		lid:PivotTo(base * hinge * CFrame.Angles(-math.rad(112) * lidOpen, 0, 0))
		local glow = math.clamp((openP - 0.35) / 0.4, 0, 1)
		local pulse = if t > TIMELINE.total then 0.03 * math.sin((t - TIMELINE.total) * 2.5) else 0
		column.Transparency = if glow > 0 then 1 - COLUMN_OPACITY * glow + pulse else 1
		if not opened and t >= openAt then
			opened = true
			if callbacks.onOpen then
				callbacks.onOpen()
			end
		end

		-- L'objet sort de la caisse et flotte au-dessus en tournant.
		local riseP = CrateSequence.progress(TIMELINE, "rise", t)
		if riseP > 0 then
			if prize.Parent == nil then
				prize.Parent = viewport
			end
			local rise = easeOutCubic(riseP)
			local bob = if t > TIMELINE.total then math.sin((t - TIMELINE.total) * 2) * 0.12 else 0
			local itemY = lerp(body * 0.5, C.floatHeight, rise) + bob
			local spin = math.pi / 2 + math.max(0, t - stepRise.start) * 0.8
			prize:PivotTo(CFrame.new(0, itemY, 0) * CFrame.Angles(0, spin, 0) * CFrame.Angles(math.rad(-8), 0, 0))
		end
		if not revealed and t >= revealAt then
			revealed = true
			if callbacks.onReveal then
				callbacks.onReveal()
			end
		end
	end

	local connection = RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt
		render(elapsed)
	end)
	if instant then
		elapsed = TIMELINE.total
	end
	render(elapsed)

	local scene: Scene = {
		frame = viewport,
		skip = function()
			if elapsed < TIMELINE.total then
				elapsed = TIMELINE.total
				render(elapsed)
			end
		end,
		destroy = function()
			connection:Disconnect()
			prize:Destroy()
			viewport:Destroy()
		end,
	}
	return scene
end

return CrateScene
