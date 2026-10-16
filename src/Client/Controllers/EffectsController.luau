--!strict
--[[
	EffectsController : effets visuels de combat (côté client uniquement).

	- Tracés des tirs (les siens immédiatement, ceux des autres via ShotFired).
	- Projectiles lents (Lance-clous, Court-Circuit) : image du projectile en
	  vol, explosion à l'impact annoncé par le serveur.
	- Recul des tirs et coups de mêlée : posture de l'arme et des bras
	  (WeaponPoseController ; ancienne animation de l'épaule pour un avatar R6).
	- Flash de parade.
	- Mort : désintégration en voxels néon (~1,2 s), sans gore (section 6.9).

	Budget d'effets réduit sur mobile.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Damage = require(Shared.Combat.Damage)
local Projectiles = require(Shared.Combat.Projectiles)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local ProfileController = require(script.Parent.ProfileController)
local WeaponPoseController = require(script.Parent.WeaponPoseController)

local Visuals = Config.Visuals
local Combat = Config.Combat

local EffectsController = {}

local player = Players.LocalPlayer
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local effectsFolder: Folder
local random = Random.new()

local function decorative(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

local function tracer(from: Vector3, to: Vector3, color: Color3, width: number, lifetime: number)
	local length = (to - from).Magnitude
	if length < 0.1 then
		return
	end
	local beam = Instance.new("Part")
	beam.Name = "Tracer"
	beam.Size = Vector3.new(width, width, length)
	beam.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2)
	beam.Color = color
	beam.Material = Enum.Material.Neon
	decorative(beam)
	beam.Parent = effectsFolder
	TweenService:Create(beam, TweenInfo.new(lifetime), { Transparency = 1 }):Play()
	Debris:AddItem(beam, lifetime + 0.05)
end

local function impact(position: Vector3, color: Color3)
	local spark = Instance.new("Part")
	spark.Name = "Impact"
	spark.Shape = Enum.PartType.Ball
	spark.Size = Vector3.new(0.4, 0.4, 0.4)
	spark.CFrame = CFrame.new(position)
	spark.Color = color
	spark.Material = Enum.Material.Neon
	decorative(spark)
	spark.Parent = effectsFolder
	TweenService:Create(spark, TweenInfo.new(0.15), { Size = Vector3.new(1.2, 1.2, 1.2), Transparency = 1 }):Play()
	Debris:AddItem(spark, 0.2)
end

-- Tracés d'un tir (rafale / plombs inclus).
function EffectsController.playShot(itemId: string, muzzle: Vector3, endpoints: { Vector3 }, isLocal: boolean)
	local shape = Visuals.weapons[itemId]
	local isRobot = string.sub(itemId, 1, 6) == "robot_"
	local color = if shape then shape.accent elseif isRobot then Visuals.tracer.robotColor else Visuals.tracer.color
	local def = Config.Weapons.ranged[itemId]
	-- L'Aiguille : tracé visible longtemps (révèle la position du tireur).
	local lifetime = if def and def.tracerDuration then def.tracerDuration else Visuals.tracer.lifetime
	local width = Visuals.tracer.width
	if def and def.beamTick then
		-- Rayon continu : un tracé épais par tic, qui dure jusqu'au tic suivant.
		lifetime = def.beamTick * 1.6
		width = Visuals.tracer.beamWidth
	end
	local maxTracers = if isMobile then 3 else 8
	-- Tir d'un autre combattant en rafale (un seul message) : tracés étalés comme les tirs.
	local perBullet = if def and def.pellets then def.pellets else 1
	local interval = if not isLocal and def and def.burstCount > 1 then def.burstInterval or 0 else 0
	for index, endpoint in endpoints do
		if index > maxTracers then
			break
		end
		local delay = math.floor((index - 1) / perBullet) * interval
		local showImpact = isLocal or index <= 2
		if delay > 0 then
			task.delay(delay, function()
				tracer(muzzle, endpoint, color, width, lifetime)
				if showImpact then
					impact(endpoint, color)
				end
			end)
		else
			tracer(muzzle, endpoint, color, width, lifetime)
			if showImpact then
				impact(endpoint, color)
			end
		end
	end
end

-- Projectiles lents ------------------------------------------------------------

type Flying = { part: BasePart, params: RaycastParams }
local flying: { Projectiles.Projectile } = {}
local MAX_FLYING = 24

local function accentOf(itemId: string): Color3
	local shape = Visuals.weapons[itemId]
	return if shape then shape.accent else Visuals.tracer.color
end

--[[
	Image d'un projectile en vol (même trajectoire que le serveur). Elle
	s'arrête au premier obstacle ; les dégâts et l'explosion viennent du
	serveur (ProjectileImpact).
]]
function EffectsController.playProjectile(itemId: string, origin: Vector3, velocity: Vector3, ignore: Instance?)
	local def = Config.Weapons.ranged[itemId]
	if def == nil or def.projectileSpeed == nil or #flying >= MAX_FLYING then
		return
	end
	local part = Instance.new("Part")
	part.Name = "Projectile"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * (if def.splashRadius then 1.1 else 0.4)
	part.CFrame = CFrame.new(origin)
	part.Color = accentOf(itemId)
	part.Material = Enum.Material.Neon
	decorative(part)
	part.Parent = effectsFolder
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.FilterDescendantsInstances = if ignore then { effectsFolder, ignore } else { effectsFolder }
	local entry: Flying = { part = part, params = params }
	table.insert(
		flying,
		Projectiles.new(
			origin,
			velocity,
			def.arcGravity or 0,
			Damage.maxRange(def.effectiveRange),
			os.clock() + Combat.projectiles.maxLifetime,
			entry
		)
	)
end

local function castFlying(projectile: Projectiles.Projectile, from: Vector3, displacement: Vector3): (Vector3?, any?)
	local result = Workspace:Raycast(from, displacement, (projectile.data :: Flying).params)
	if result then
		return result.Position, result.Instance
	end
	return nil, nil
end

local function endFlying(projectile: Projectiles.Projectile)
	(projectile.data :: Flying).part:Destroy()
end

local function stepFlying(dt: number)
	if #flying == 0 then
		return
	end
	Projectiles.step(flying, dt, os.clock(), castFlying, endFlying)
	for _, projectile in flying do
		(projectile.data :: Flying).part.CFrame = CFrame.new(projectile.position)
	end
end

-- Explosion en zone : sphère qui gonfle jusqu'au rayon réel des dégâts.
local function explosion(position: Vector3, radius: number, color: Color3)
	local blast = Instance.new("Part")
	blast.Name = "Explosion"
	blast.Shape = Enum.PartType.Ball
	blast.Size = Vector3.one
	blast.CFrame = CFrame.new(position)
	blast.Color = color
	blast.Material = Enum.Material.Neon
	blast.Transparency = 0.25
	decorative(blast)
	blast.Parent = effectsFolder
	TweenService:Create(blast, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * radius * 2,
		Transparency = 1,
	}):Play()
	Debris:AddItem(blast, 0.35)
end

-- Coup de mêlée : geste de l'arme, les mains suivent (WeaponPoseController).
-- Avatar R6 (arme dans la main) : rotation rapide de l'épaule droite.
function EffectsController.playSwing(character: Model)
	if WeaponPoseController.swing(character) then
		return
	end
	local upperArm = character:FindFirstChild("RightUpperArm")
	local shoulder = if upperArm then upperArm:FindFirstChild("RightShoulder") else nil
	if shoulder == nil or not shoulder:IsA("Motor6D") then
		return
	end
	local motor = shoulder :: Motor6D
	local original = motor:GetAttribute("OriginalC0") :: CFrame?
	if original == nil then
		original = motor.C0
		motor:SetAttribute("OriginalC0", original)
	end
	local base = original :: CFrame
	local raised = base * CFrame.Angles(math.rad(110), 0, math.rad(-20))
	local struck = base * CFrame.Angles(math.rad(-30), 0, math.rad(25))
	local up = TweenService:Create(motor, TweenInfo.new(0.07), { C0 = raised })
	local down =
		TweenService:Create(motor, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { C0 = struck })
	local back = TweenService:Create(motor, TweenInfo.new(0.15), { C0 = base })
	up.Completed:Once(function()
		down:Play()
	end)
	down.Completed:Once(function()
		back:Play()
	end)
	up:Play()
end

-- Flash de parade (étincelles cyan devant le personnage).
function EffectsController.playParryFlash(character: Model, color: Color3?)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local flash = Instance.new("Part")
	flash.Name = "ParryFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(1, 1, 1)
	flash.CFrame = root.CFrame * CFrame.new(0, 0.5, -1.5)
	flash.Color = color or Color3.fromRGB(0, 229, 255)
	flash.Material = Enum.Material.Neon
	decorative(flash)
	flash.Parent = effectsFolder
	TweenService:Create(flash, TweenInfo.new(0.25), { Size = Vector3.new(4, 4, 4), Transparency = 1 }):Play()
	Debris:AddItem(flash, 0.3)
end

-- Désintégration : le corps se décompose en voxels néon qui s'envolent.
local function disintegrate(character: Model)
	local spec = Visuals.disintegration
	-- Qualité graphique (paramètre) : « auto » suit le type d'appareil.
	local view = ProfileController.get()
	local quality = if view then view.settings.graphicsQuality else "auto"
	local perPart = if quality == "low"
		then 1
		elseif quality == "medium" then spec.voxelsPerPartMobile
		elseif quality == "high" then spec.voxelsPerPart
		elseif isMobile then spec.voxelsPerPartMobile
		else spec.voxelsPerPart
	local duration = Combat.death.disintegrateDuration
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			if descendant.Transparency < 1 then
				for _ = 1, perPart do
					local voxel = Instance.new("Part")
					voxel.Name = "Voxel"
					voxel.Size = Vector3.one * spec.voxelSize
					local offset = Vector3.new(
						random:NextNumber(-0.5, 0.5) * descendant.Size.X,
						random:NextNumber(-0.5, 0.5) * descendant.Size.Y,
						random:NextNumber(-0.5, 0.5) * descendant.Size.Z
					)
					voxel.CFrame = descendant.CFrame * CFrame.new(offset)
					voxel.Color = spec.colors[random:NextInteger(1, #spec.colors)]
					voxel.Material = Enum.Material.Neon
					decorative(voxel)
					voxel.Parent = effectsFolder
					local drift = Vector3.new(
						random:NextNumber(-spec.spread, spec.spread),
						spec.riseSpeed * random:NextNumber(0.6, 1.4),
						random:NextNumber(-spec.spread, spec.spread)
					) * duration
					TweenService
						:Create(voxel, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							CFrame = voxel.CFrame
								* CFrame.new(drift)
								* CFrame.Angles(random:NextNumber(0, 3), random:NextNumber(0, 3), 0),
							Size = Vector3.one * 0.05,
							Transparency = 1,
						})
						:Play()
					Debris:AddItem(voxel, duration + 0.1)
				end
			end
			descendant.LocalTransparencyModifier = 1
		elseif descendant:IsA("Decal") then
			descendant.Transparency = 1
		end
	end
end

local function watchCharacter(character: Model)
	if character:GetAttribute("Dead") == true then
		disintegrate(character)
		return
	end
	local connection: RBXScriptConnection
	connection = character:GetAttributeChangedSignal("Dead"):Connect(function()
		if character:GetAttribute("Dead") == true then
			connection:Disconnect()
			disintegrate(character)
		end
	end)
	-- Garde levée : le personnage brille légèrement (visible par tous).
	character:GetAttributeChangedSignal("Parrying"):Connect(function()
		local highlight = character:FindFirstChild("ParryHighlight")
		if character:GetAttribute("Parrying") == true then
			if highlight == nil then
				local h = Instance.new("Highlight")
				h.Name = "ParryHighlight"
				h.FillTransparency = 1
				h.OutlineColor = Color3.fromRGB(0, 229, 255)
				h.OutlineTransparency = 0.2
				h.DepthMode = Enum.HighlightDepthMode.Occluded
				h.Parent = character
			end
		elseif highlight then
			highlight:Destroy()
		end
	end)
end

-- Tout combattant (joueurs, mannequins, robots) est marqué « Fighter » par le serveur.
local function watchModel(instance: Instance)
	if instance:IsA("Model") then
		watchCharacter(instance)
	end
end

function EffectsController.init()
	effectsFolder = Instance.new("Folder")
	effectsFolder.Name = "LocalEffects"
	effectsFolder.Parent = Workspace
end

function EffectsController.start()
	-- `model` : personnage d'un tireur qui n'est pas un joueur (mercenaire).
	ClientNet.on(
		"ShotFired",
		function(shooter: Player?, itemId: string, origin: Vector3, endpoints: { Vector3 }, model: Instance?)
			if
				shooter == player
				or type(itemId) ~= "string"
				or typeof(origin) ~= "Vector3"
				or type(endpoints) ~= "table"
			then
				return
			end
			local muzzle = origin
			local character = if shooter
				then shooter.Character
				elseif typeof(model) == "Instance" and model:IsA("Model") then model
				else nil
			WeaponPoseController.kick(character)
			local visual = if character then character:FindFirstChild("WeaponVisual") else nil
			local body = if visual then visual:FindFirstChild("Body") else nil
			if body and body:IsA("BasePart") then
				muzzle = (body.CFrame * CFrame.new(0, 0, -body.Size.Z / 2)).Position
			end
			EffectsController.playShot(itemId, muzzle, endpoints, false)
		end
	)

	ClientNet.on("ProjectileFired", function(shooter: Player?, itemId: string, origin: Vector3, velocity: Vector3)
		if
			shooter == player
			or type(itemId) ~= "string"
			or typeof(origin) ~= "Vector3"
			or typeof(velocity) ~= "Vector3"
		then
			return
		end
		local character = if shooter then shooter.Character else nil
		WeaponPoseController.kick(character)
		EffectsController.playProjectile(itemId, origin, velocity, character)
	end)

	ClientNet.on("ProjectileImpact", function(itemId: string, position: Vector3, radius: number)
		if type(itemId) ~= "string" or typeof(position) ~= "Vector3" or type(radius) ~= "number" then
			return
		end
		if radius > 0 then
			explosion(position, radius, accentOf(itemId))
		else
			impact(position, accentOf(itemId))
		end
	end)

	RunService.Heartbeat:Connect(stepFlying)

	-- Alarme de casier d'AXIOM : onde rouge visible dans son rayon.
	ClientNet.on("LootAlarm", function(position: Vector3, radius: number)
		if typeof(position) ~= "Vector3" or type(radius) ~= "number" then
			return
		end
		local ring = Instance.new("Part")
		ring.Name = "Alarm"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.2, 2, 2)
		ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
		ring.Color = Color3.fromRGB(255, 59, 59)
		ring.Material = Enum.Material.Neon
		ring.Transparency = 0.3
		decorative(ring)
		ring.Parent = effectsFolder
		TweenService:Create(ring, TweenInfo.new(1.2), {
			Size = Vector3.new(0.2, radius * 2, radius * 2),
			Transparency = 1,
		}):Play()
		Debris:AddItem(ring, 1.3)
	end)

	-- `model` : personnage d'un combattant qui n'est pas un joueur (mercenaire).
	ClientNet.on("MeleeSwing", function(attacker: Player?, _itemId: string?, model: Instance?)
		if attacker and attacker ~= player and attacker.Character then
			EffectsController.playSwing(attacker.Character)
		elseif attacker == nil and typeof(model) == "Instance" and model:IsA("Model") then
			EffectsController.playSwing(model)
		end
	end)

	ClientNet.on("ParryResult", function(result: string)
		local character = player.Character
		if character and (result == "perfect" or result == "broken") then
			EffectsController.playParryFlash(
				character,
				if result == "perfect" then Color3.fromRGB(0, 229, 255) else Color3.fromRGB(255, 59, 59)
			)
		end
	end)

	for _, instance in CollectionService:GetTagged("Fighter") do
		watchModel(instance)
	end
	CollectionService:GetInstanceAddedSignal("Fighter"):Connect(watchModel)
end

return EffectsController
