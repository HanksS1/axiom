--!strict
--[[
	RobotFactory : modèles provisoires (« greybox ») des robots d'AXIOM.

	- Robots au sol : HumanoidRootPart + Humanoid (déplacement par MoveTo,
	  physique gérée par le serveur).
	- Mouches : en vol, maintenues par AlignPosition / AlignOrientation.
	- Yeux néon rouges (visibles même pendant les coupures de courant).
	- Bastion : plaque « WeakSpot » orange dans le dos (dégâts ×2,5).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local RobotFactory = {}

local METAL = Color3.fromRGB(52, 56, 64)
local DARK = Color3.fromRGB(30, 32, 38)
local EYE = Color3.fromRGB(255, 40, 40)
local WEAK = Color3.fromRGB(255, 138, 0)

local function part(
	model: Model,
	name: string,
	size: Vector3,
	offset: CFrame,
	root: BasePart,
	color: Color3,
	material: EnumItem
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = root.CFrame * offset
	p.Color = color
	p.Material = material
	p.CanCollide = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	p.Parent = model
	return p
end

export type Built = {
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	eye: BasePart,
}

function RobotFactory.build(robotId: string, cframe: CFrame): Built
	local def = Config.Robots.byId[robotId]
	assert(def ~= nil, `robot inconnu : {robotId}`)
	local size = def.size
	local model = Instance.new("Model")
	model.Name = "Robot_" .. robotId

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Transparency = 1
	root.CanCollide = not def.flying
	root.CanQuery = false
	root.Size = if def.flying then size else Vector3.new(size.X, 2, size.Z)
	root.CFrame = cframe
	root.Parent = model
	model.PrimaryPart = root

	-- Corps (touchable par les tirs).
	local body = part(model, "Body", size, CFrame.new(), root, METAL, Enum.Material.Metal)
	body.CanQuery = true
	-- Tête et yeux.
	local headSize = Vector3.new(size.X * 0.6, math.min(1.2, size.Y * 0.25), size.Z * 0.7)
	local head = part(
		model,
		"Head",
		headSize,
		CFrame.new(0, size.Y / 2 + headSize.Y / 2 - 0.1, -size.Z * 0.1),
		root,
		DARK,
		Enum.Material.Metal
	)
	head.CanQuery = true
	local eye = part(
		model,
		"Eye",
		Vector3.new(headSize.X * 0.8, 0.18, 0.1),
		CFrame.new(0, size.Y / 2 + headSize.Y / 2 - 0.1, -size.Z * 0.1 - headSize.Z / 2 - 0.02),
		root,
		EYE,
		Enum.Material.Neon
	)
	eye.CanQuery = false

	if def.weakSpotMultiplier then
		local weak = part(
			model,
			"WeakSpot",
			Vector3.new(size.X * 0.5, size.Y * 0.35, 0.3),
			CFrame.new(0, size.Y * 0.1, size.Z / 2 + 0.1),
			root,
			WEAK,
			Enum.Material.Neon
		)
		weak.CanQuery = true
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.WalkSpeed = def.speed
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = 0
	humanoid.HipHeight = if def.flying then 0 else math.max(0, size.Y / 2 - 1)
	humanoid.Parent = model

	if def.flying then
		-- Vol : position et orientation maintenues par contraintes physiques.
		humanoid.PlatformStand = true
		local attachment = Instance.new("Attachment")
		attachment.Parent = root
		local align = Instance.new("AlignPosition")
		align.Name = "Hover"
		align.Mode = Enum.PositionAlignmentMode.OneAttachment
		align.Attachment0 = attachment
		align.MaxForce = 1e6
		align.Responsiveness = 18
		align.Position = cframe.Position
		align.Parent = root
		local orient = Instance.new("AlignOrientation")
		orient.Name = "Facing"
		orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
		orient.Attachment0 = attachment
		orient.MaxTorque = 1e6
		orient.Responsiveness = 20
		orient.CFrame = cframe.Rotation
		orient.Parent = root
	end

	return { model = model, root = root, humanoid = humanoid, eye = eye }
end

return RobotFactory
