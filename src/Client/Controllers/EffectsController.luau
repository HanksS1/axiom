--!strict
--[[
	EffectsController : effets visuels de combat (côté client uniquement).

	- Tracés des tirs (les siens immédiatement, ceux des autres via ShotFired).
	- Coups de mêlée (bras animé de façon procédurale, en attendant les animations).
	- Flash de parade.
	- Mort : désintégration en voxels néon (~1,2 s), sans gore (section 6.9).

	Budget d'effets réduit sur mobile.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)

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
	local color = if shape then shape.accent else Visuals.tracer.color
	local def = Config.Weapons.ranged[itemId]
	-- L'Aiguille : tracé visible longtemps (révèle la position du tireur).
	local lifetime = if def and def.tracerDuration then def.tracerDuration else Visuals.tracer.lifetime
	local maxTracers = if isMobile then 3 else 8
	for index, endpoint in endpoints do
		if index > maxTracers then
			break
		end
		tracer(muzzle, endpoint, color, Visuals.tracer.width, lifetime)
		if isLocal or index <= 2 then
			impact(endpoint, color)
		end
	end
end

-- Coup de mêlée : rotation rapide de l'épaule droite (procédural, local).
function EffectsController.playSwing(character: Model)
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
	local perPart = if isMobile then spec.voxelsPerPartMobile else spec.voxelsPerPart
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
	ClientNet.on("ShotFired", function(shooter: Player?, itemId: string, origin: Vector3, endpoints: { Vector3 })
		if
			shooter == player
			or type(itemId) ~= "string"
			or typeof(origin) ~= "Vector3"
			or type(endpoints) ~= "table"
		then
			return
		end
		local muzzle = origin
		local character = if shooter then shooter.Character else nil
		local visual = if character then character:FindFirstChild("WeaponVisual") else nil
		local body = if visual then visual:FindFirstChild("Body") else nil
		if body and body:IsA("BasePart") then
			muzzle = (body.CFrame * CFrame.new(0, 0, -body.Size.Z / 2)).Position
		end
		EffectsController.playShot(itemId, muzzle, endpoints, false)
	end)

	ClientNet.on("MeleeSwing", function(attacker: Player?)
		if attacker and attacker ~= player and attacker.Character then
			EffectsController.playSwing(attacker.Character)
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
