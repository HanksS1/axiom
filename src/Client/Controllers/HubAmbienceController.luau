--!strict
--[[
	HubAmbienceController : la vie du Terminus, jouée côté client (aucun coût
	serveur). Actif seulement quand la caméra est près du Terminus ; sur une
	carte de partie, seuls les néons qui grésillent et les gerbes d'étincelles
	tournent (mêmes tags, posés par MapRenderer).

	- Néons et lumières qui grésillent, gyrophares, lampes qui se balancent,
	  drones de maintenance, rongeurs mécaniques, hologrammes instables,
	  cubes de données en orbite, étincelles de l'établi.
	- PNJ : respiration, regard qui vagabonde puis suit le joueur proche,
	  salutation (bulle tapée lettre par lettre) quand on s'approche.
	- Textes localisés des enseignes, affiches et tags (attribut TextKey).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Zone = require(Shared.Match.Zone)
local TextKeys = require(script.Parent.Parent.UI.TextKeys)
local ProfileController = require(script.Parent.ProfileController)

local HubAmbienceController = {}

local player = Players.LocalPlayer
local t = ProfileController.t
local random = Random.new()

local ACTIVE_DISTANCE = Config.Maps.hub.radius
local GREET_DISTANCE = 12
local LOOK_DISTANCE = 16
local GREET_COOLDOWN = 25
local LINES_PER_NPC = 3

type Animated = { instance: Instance, base: CFrame?, phase: number, data: { [string]: any } }

local tracked: { [string]: { [Instance]: Animated } } = {
	Flicker = {},
	Spin = {},
	Sway = {},
	Drone = {},
	Orbit = {},
	Critter = {},
	Hologram = {},
	SparkBurst = {},
}

type Npc = {
	model: Model,
	root: BasePart,
	head: BasePart?,
	neck: Motor6D?,
	waist: Motor6D?,
	rightShoulder: Motor6D?,
	leftShoulder: Motor6D?,
	original: { [Motor6D]: CFrame },
	yaw: number,
	pitch: number,
	phase: number,
	lastGreet: number,
	near: boolean,
}
local npcs: { [Model]: Npc } = {}

local function terminus(): Instance?
	return Workspace:FindFirstChild("Terminus")
end

local function cframeOf(instance: Instance): CFrame?
	if instance:IsA("BasePart") then
		return instance.CFrame
	elseif instance:IsA("Model") then
		return instance:GetPivot()
	end
	return nil
end

local function setCFrame(instance: Instance, cframe: CFrame)
	if instance:IsA("BasePart") then
		instance.CFrame = cframe
	elseif instance:IsA("Model") then
		instance:PivotTo(cframe)
	end
end

local function track(tag: string, instance: Instance)
	tracked[tag][instance] = {
		instance = instance,
		base = cframeOf(instance),
		phase = random:NextNumber(0, math.pi * 2),
		data = { nextAt = os.clock() + random:NextNumber(1, 8), untilAt = 0 },
	}
end

-- PNJ ------------------------------------------------------------------------

local function addNpc(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local function motor(partName: string, motorName: string): Motor6D?
		local part = model:FindFirstChild(partName)
		local found = if part then part:FindFirstChild(motorName) else nil
		return if found and found:IsA("Motor6D") then found else nil
	end
	local npc: Npc = {
		model = model,
		root = root,
		head = model:FindFirstChild("Head") :: BasePart?,
		neck = motor("Head", "Neck"),
		waist = motor("UpperTorso", "Waist"),
		rightShoulder = motor("RightUpperArm", "RightShoulder"),
		leftShoulder = motor("LeftUpperArm", "LeftShoulder"),
		original = {},
		yaw = 0,
		pitch = 0,
		phase = random:NextNumber(0, math.pi * 2),
		lastGreet = -math.huge,
		near = false,
	}
	for _, joint in { npc.neck, npc.waist, npc.rightShoulder, npc.leftShoulder } do
		if joint then
			npc.original[joint] = joint.C0
		end
	end
	npcs[model] = npc
end

-- Bulle de dialogue tapée lettre par lettre.
local function say(npc: Npc)
	local head = npc.head
	local id = npc.model:GetAttribute("NpcId")
	-- PNJ masqué localement (défi du stand de tir) : il se tait.
	if head == nil or type(id) ~= "string" or npc.model:GetAttribute("LocallyHidden") == true then
		return
	end
	local existing = head:FindFirstChild("SpeechBubble")
	if existing then
		existing:Destroy()
	end
	local text = t(`npc.{id}.line.{random:NextInteger(1, LINES_PER_NPC)}`)
	local gui = Instance.new("BillboardGui")
	gui.Name = "SpeechBubble"
	gui.Size = UDim2.fromOffset(280, 70)
	gui.StudsOffset = Vector3.new(0, 4.4, 0)
	gui.MaxDistance = 30
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(14, 16, 22)
	label.BackgroundTransparency = 0.2
	label.Font = Enum.Font.Code
	label.TextSize = 16
	label.TextWrapped = true
	label.TextColor3 = Color3.fromRGB(230, 235, 240)
	label.Text = ""
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 229, 255)
	stroke.Transparency = 0.4
	stroke.Parent = label
	gui.Parent = head
	task.spawn(function()
		for index = 1, utf8.len(text) or #text do
			if gui.Parent == nil then
				return
			end
			local cut = utf8.offset(text, index + 1)
			label.Text = if cut then string.sub(text, 1, cut - 1) else text
			task.wait(0.03)
		end
		task.wait(4)
		gui:Destroy()
	end)
end

local function updateNpc(npc: Npc, time: number, dt: number, me: Vector3?)
	local root = npc.root
	local targetYaw = math.sin(time * 0.35 + npc.phase) * 0.6
	local targetPitch = math.sin(time * 0.5 + npc.phase) * 0.08
	if me then
		local offset = root.CFrame:PointToObjectSpace(me)
		local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
		if distance < LOOK_DISTANCE then
			-- Suivre le joueur du regard (dans la limite du cou).
			targetYaw = math.clamp(math.atan2(-offset.X, -offset.Z), -1.1, 1.1)
			targetPitch = math.clamp(math.atan2(offset.Y - 1.5, distance), -0.4, 0.4)
		end
		local near = distance < GREET_DISTANCE
		if near and not npc.near and time - npc.lastGreet > GREET_COOLDOWN then
			npc.lastGreet = time
			say(npc)
		end
		npc.near = near
	end
	local alpha = math.clamp(dt * 3, 0, 1)
	npc.yaw += (targetYaw - npc.yaw) * alpha
	npc.pitch += (targetPitch - npc.pitch) * alpha
	local breathe = math.sin(time * 1.6 + npc.phase)
	if npc.neck then
		npc.neck.C0 = npc.original[npc.neck] * CFrame.Angles(npc.pitch, npc.yaw, 0)
	end
	if npc.waist then
		npc.waist.C0 = npc.original[npc.waist] * CFrame.Angles(breathe * 0.025, npc.yaw * 0.15, 0)
	end
	if npc.rightShoulder then
		npc.rightShoulder.C0 = npc.original[npc.rightShoulder]
			* CFrame.Angles(math.sin(time * 1.1 + npc.phase) * 0.05, 0, 0)
	end
	if npc.leftShoulder then
		npc.leftShoulder.C0 = npc.original[npc.leftShoulder]
			* CFrame.Angles(math.sin(time * 0.9 + npc.phase) * 0.04, 0, 0)
	end
end

-- Animation du décor ------------------------------------------------------------

local function flickerStep(time: number)
	local clock = os.clock()
	for instance, entry in tracked.Flicker do
		local data = entry.data
		if clock >= data.nextAt then
			data.untilAt = clock + random:NextNumber(0.15, 0.5)
			data.nextAt = clock + random:NextNumber(2, 9)
		end
		local off = clock < data.untilAt and random:NextNumber() < 0.55
		if instance:IsA("BasePart") then
			if data.baseTransparency == nil then
				data.baseTransparency = instance.Transparency
			end
			instance.Transparency = if off then math.min(1, data.baseTransparency + 0.65) else data.baseTransparency
		elseif instance:IsA("Light") then
			-- Coupure de courant (Noyau Zéro) : une lumière éteinte le reste.
			instance.Enabled = not off and instance:GetAttribute("PoweredOff") ~= true
		end
	end
	local _ = time
end

local function sparkStep()
	local clock = os.clock()
	for instance, entry in tracked.SparkBurst do
		if clock >= entry.data.nextAt then
			entry.data.nextAt = clock + random:NextNumber(1.2, 3.5)
			for _, child in instance:GetChildren() do
				if child:IsA("ParticleEmitter") then
					child:Emit(random:NextInteger(12, 26))
				end
			end
		end
	end
end

-- La caméra est-elle près du Terminus ?
local function nearTerminus(): boolean
	local root = terminus()
	local camera = Workspace.CurrentCamera
	if root == nil or camera == nil then
		return false
	end
	local anchor = root:FindFirstChild("Structure")
	local platform = if anchor then anchor:FindFirstChild("Platform") else nil
	if platform == nil or not platform:IsA("BasePart") then
		return false
	end
	return (camera.CFrame.Position - platform.Position).Magnitude <= ACTIVE_DISTANCE
end

-- La caméra est-elle dans l'Arène FFA ? (même décor animé : néons, hologramme…)
local function inArena(): boolean
	local camera = Workspace.CurrentCamera
	return camera ~= nil and Workspace:FindFirstChild("Arena") ~= nil and Zone.inArena(camera.CFrame.Position)
end

local function step(dt: number)
	if not nearTerminus() and not inArena() then
		-- Carte de partie : néons défaillants et étincelles seulement.
		if Workspace:FindFirstChild("Map") then
			flickerStep(os.clock())
			sparkStep()
		end
		return
	end
	local time = os.clock()
	flickerStep(time)

	for instance, entry in tracked.Spin do
		local base = entry.base
		if base then
			local speed = instance:GetAttribute("Speed")
			setCFrame(
				instance,
				base * CFrame.Angles(0, time * (if type(speed) == "number" then speed else 0.5) * math.pi * 2, 0)
			)
		end
	end
	for instance, entry in tracked.Sway do
		local base = entry.base
		local pivot = instance:GetAttribute("Pivot")
		local amplitude = instance:GetAttribute("Amplitude")
		if base and typeof(pivot) == "Vector3" then
			local angle =
				math.rad(math.sin(time * 0.9 + entry.phase) * (if type(amplitude) == "number" then amplitude else 4))
			local rotation = CFrame.new(pivot) * CFrame.Angles(angle, 0, angle * 0.5) * CFrame.new(-pivot)
			setCFrame(instance, rotation * base)
		end
	end
	for instance, entry in tracked.Drone do
		local center = instance:GetAttribute("Center")
		local radius = instance:GetAttribute("Radius")
		local speed = instance:GetAttribute("Speed")
		if typeof(center) == "Vector3" and type(radius) == "number" and type(speed) == "number" then
			local angle = time * speed * math.pi * 2 + entry.phase
			local position = center
				+ Vector3.new(math.cos(angle) * radius, math.sin(time * 1.3) * 0.8, math.sin(angle) * radius)
			local ahead = center + Vector3.new(math.cos(angle + 0.1) * radius, 0, math.sin(angle + 0.1) * radius)
			setCFrame(instance, CFrame.lookAt(position, Vector3.new(ahead.X, position.Y, ahead.Z)))
		end
	end
	for instance, entry in tracked.Orbit do
		local center = instance:GetAttribute("Center")
		local radius = instance:GetAttribute("Radius")
		local speed = instance:GetAttribute("Speed")
		local phase = instance:GetAttribute("Phase")
		if typeof(center) == "Vector3" and type(radius) == "number" and type(speed) == "number" then
			local angle = time * speed * math.pi * 2 + (if type(phase) == "number" then phase else entry.phase)
			setCFrame(
				instance,
				CFrame.new(
					center
						+ Vector3.new(
							math.cos(angle) * radius,
							math.sin(time * 2 + angle) * 0.3,
							math.sin(angle) * radius
						)
				) * CFrame.Angles(time, time * 1.3, 0)
			)
		end
	end
	for instance, entry in tracked.Critter do
		local a, b = instance:GetAttribute("PointA"), instance:GetAttribute("PointB")
		if typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			-- Course de 5 s, pause de 3 s, retour.
			local cycle = (time + entry.phase * 3) % 16
			local progress, forward
			if cycle < 5 then
				progress, forward = cycle / 5, true
			elseif cycle < 8 then
				progress, forward = 1, true
			elseif cycle < 13 then
				progress, forward = 1 - (cycle - 8) / 5, false
			else
				progress, forward = 0, false
			end
			local position = a:Lerp(b, progress)
			local facing = if forward then b - a else a - b
			if facing.Magnitude > 0.01 then
				setCFrame(instance, CFrame.lookAt(position, position + facing))
			end
		end
	end
	for instance, entry in tracked.Hologram do
		local parts: { BasePart } = entry.data.parts
		if parts == nil then
			parts = {}
			if instance:IsA("BasePart") then
				table.insert(parts, instance)
			end
			for _, descendant in instance:GetDescendants() do
				if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
					table.insert(parts, descendant)
				end
			end
			entry.data.parts = parts
			local bases = {}
			for _, part in parts do
				bases[part] = part.Transparency
			end
			entry.data.bases = bases
		end
		local glitch = random:NextNumber() < 0.04
		for _, part in parts do
			local base = entry.data.bases[part] or 0
			part.Transparency = if glitch
				then math.min(1, base + 0.5)
				else math.clamp(base + math.sin(time * 6 + entry.phase) * 0.08, 0, 1)
		end
	end
	sparkStep()

	-- PNJ.
	local character = player.Character
	local myRoot = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local me = if myRoot and myRoot:IsA("BasePart") then myRoot.Position else nil
	for model, npc in npcs do
		if model.Parent == nil then
			npcs[model] = nil
		else
			updateNpc(npc, time, dt, me)
		end
	end
end

function HubAmbienceController.init() end

function HubAmbienceController.start()
	for tag in tracked do
		for _, instance in CollectionService:GetTagged(tag) do
			track(tag, instance)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
			track(tag, instance)
		end)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
			tracked[tag][instance] = nil
		end)
	end
	for _, model in CollectionService:GetTagged("HubNpc") do
		addNpc(model)
	end
	CollectionService:GetInstanceAddedSignal("HubNpc"):Connect(function(model)
		-- Les pièces du PNJ arrivent avec le modèle ; on attend une image par sécurité.
		task.defer(addNpc, model)
	end)

	-- Textes localisés (enseignes, fresques, affiches, plaques des PNJ, Mur des
	-- Légendes) : remplis à l'arrivée de chaque texte, quel que soit l'ordre
	-- d'arrivée (les PNJ et leurs plaques sont créés après le décor, parfois
	-- plusieurs secondes après), et re-traduits au changement de langue.
	TextKeys.setTranslator(t)
	local existing = terminus()
	if existing then
		TextKeys.watch(existing)
	end
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Terminus" then
			TextKeys.watch(child)
		end
	end)
	ProfileController.Changed:Connect(TextKeys.refresh)

	RunService.RenderStepped:Connect(step)
end

return HubAmbienceController
