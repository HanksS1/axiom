--!strict
--[[
	ReviveService : réanimation en duo, l'Orbe et l'Accélérateur (section 6.10).

	- À sa mort, le joueur devient une Orbe (aux couleurs du duo) pendant 1:30.
	  Elle peut être détruite par les ennemis (100 PV).
	- Le coéquipier la ramasse (elle ne prend pas de place) ; le compte à
	  rebours continue pendant le transport.
	- Un Accélérateur apparaît sur un emplacement de la carte situé entre 80
	  et 200 studs du lieu de la mort. Y déposer l'orbe et maintenir 5 s
	  (faisceau visible par tous) réanime le joueur (50 PV, kit de base).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Signal = require(Shared.Util.Signal)

local Fighter = require(script.Parent.Parent.Combat.Fighter)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local CombatService = require(script.Parent.CombatService)
local MapService = require(script.Parent.MapService)

type Fighter = Fighter.Fighter

local R = Config.Combat.revive
local MR = Config.Match.revive

local ReviveService = {}

-- (joueur mort, position de l'Accélérateur) : réanimation réussie.
ReviveService.Revived = Signal.new() :: Signal.Signal<Player, CFrame>
-- (joueur mort, raison "expired" | "destroyed" | "abandoned") : plus de réanimation possible.
ReviveService.Lost = Signal.new() :: Signal.Signal<Player, string>

type Revive = {
	dead: Player,
	teammate: Player,
	teamId: string,
	expiresAt: number,
	orb: Model,
	orbFighter: Fighter?,
	carriedBy: Player?,
	accelerator: Model,
	acceleratorCFrame: CFrame,
	holdStartedAt: number?,
}

local revives: { [Player]: Revive } = {}
local folder: Folder?

local TEAM_COLORS = {
	Color3.fromRGB(0, 229, 255),
	Color3.fromRGB(255, 46, 196),
	Color3.fromRGB(57, 255, 20),
	Color3.fromRGB(255, 176, 32),
}

local function teamColor(teamId: string): Color3
	local hash = 0
	for index = 1, #teamId do
		hash = (hash * 31 + string.byte(teamId, index)) % 1000003
	end
	return TEAM_COLORS[hash % #TEAM_COLORS + 1]
end

local function container(): Folder
	if folder == nil or folder.Parent == nil then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "Revive"
		newFolder.Parent = Workspace
		folder = newFolder
	end
	return folder :: Folder
end

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

-- Emplacement d'Accélérateur entre 80 et 200 studs (sinon le plus proche de cette plage).
local function chooseSpot(deathPosition: Vector3, random: Random): CFrame
	local inRange: { CFrame } = {}
	local best: CFrame? = nil
	local bestGap = math.huge
	for _, marker in MapService.acceleratorSpots() do
		local distance = (marker.position - deathPosition).Magnitude
		if distance >= R.acceleratorMinDistance and distance <= R.acceleratorMaxDistance then
			table.insert(inRange, marker.cframe)
		end
		local gap = if distance < R.acceleratorMinDistance
			then R.acceleratorMinDistance - distance
			else math.max(0, distance - R.acceleratorMaxDistance)
		if gap < bestGap then
			bestGap = gap
			best = marker.cframe
		end
	end
	if #inRange > 0 then
		return inRange[random:NextInteger(1, #inRange)]
	end
	return best or CFrame.new(deathPosition + Vector3.new(R.acceleratorMinDistance, 0, 0))
end

local function sendState(revive: Revive)
	local payload = {
		deadUserId = revive.dead.UserId,
		deadName = revive.dead.DisplayName,
		teammateUserId = revive.teammate.UserId,
		expiresAt = revive.expiresAt,
		accelerator = revive.acceleratorCFrame.Position,
		carried = revive.carriedBy ~= nil,
	}
	for _, player in { revive.dead, revive.teammate } do
		if player.Parent == Players then
			ServerNet.fire("ReviveState", player, payload)
		end
	end
end

local function clearState(revive: Revive)
	for _, player in { revive.dead, revive.teammate } do
		if player.Parent == Players then
			ServerNet.fire("ReviveState", player, nil)
		end
	end
end

local function finish(revive: Revive)
	if revives[revive.dead] ~= revive then
		return
	end
	revives[revive.dead] = nil
	local orbFighter = revive.orbFighter
	if orbFighter then
		CombatService.unregister(orbFighter)
	end
	revive.orb:Destroy()
	revive.accelerator:Destroy()
	clearState(revive)
end

local function lose(revive: Revive, reason: string)
	if revives[revive.dead] ~= revive then
		return
	end
	finish(revive)
	ReviveService.Lost:Fire(revive.dead, reason)
end

local function makePrompt(parent: BasePart, actionKey: string, hold: number, distance: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt:SetAttribute("ActionKey", actionKey)
	prompt:SetAttribute("ObjectKey", "revive.object")
	prompt.ActionText = actionKey
	prompt.ObjectText = "revive.object"
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = distance
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	return prompt
end

local function buildOrb(revive: Revive, position: Vector3, color: Color3)
	local model = Instance.new("Model")
	model.Name = "Orb"
	local core = Instance.new("Part")
	core.Name = "HumanoidRootPart"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(2.2, 2.2, 2.2)
	core.CFrame = CFrame.new(position)
	core.Color = color
	core.Material = Enum.Material.Neon
	core.Anchored = true
	core.CanCollide = false
	core.Parent = model
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 14
	light.Brightness = 2
	light.Parent = core
	model.PrimaryPart = core
	model:SetAttribute("OrbOf", revive.dead.UserId)
	model.Parent = container()
	revive.orb = model

	-- L'orbe est une cible : elle peut être détruite par les ennemis.
	local fighter = Fighter.newObject(model, core, R.orbHealth, revive.teamId)
	revive.orbFighter = fighter
	CombatService.register(fighter)

	local prompt = makePrompt(core, "prompt.pickupOrb", MR.orbPickupHold, MR.orbPickupDistance)
	prompt.Triggered:Connect(function(player)
		if player ~= revive.teammate or revive.carriedBy ~= nil or revives[revive.dead] ~= revive then
			return
		end
		local carrier = CombatService.getFighter(player)
		local root = rootOf(player)
		if carrier == nil or not Fighter.isAlive(carrier) or root == nil then
			return
		end
		if (root.Position - core.Position).Magnitude > MR.orbPickupDistance + 4 then
			return
		end
		-- Transport : l'orbe n'est plus une cible et suit le coéquipier.
		revive.carriedBy = player
		if revive.orbFighter then
			CombatService.unregister(revive.orbFighter)
			revive.orbFighter = nil
		end
		prompt:Destroy()
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:Destroy() -- sinon l'humanoïde tenterait de « tenir debout » l'orbe
		end
		core.Anchored = false
		core.Massless = true
		core.CanQuery = false
		core.Size = Vector3.new(1.2, 1.2, 1.2)
		core.CFrame = root.CFrame * CFrame.new(0, 3.5, 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = core
		weld.Parent = core
		sendState(revive)
	end)
end

local function buildAccelerator(revive: Revive, cframe: CFrame, color: Color3)
	local model = Instance.new("Model")
	model.Name = "Accelerator"
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(6, 1.2, 6)
	base.CFrame = cframe * CFrame.new(0, 0.6, 0)
	base.Color = Color3.fromRGB(36, 40, 48)
	base.Material = Enum.Material.DiamondPlate
	base.Anchored = true
	base.Parent = model
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Shape = Enum.PartType.Cylinder
	core.Size = Vector3.new(0.4, 4, 4)
	core.CFrame = base.CFrame * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, math.rad(90))
	core.Color = color
	core.Material = Enum.Material.Neon
	core.Anchored = true
	core.CanCollide = false
	core.Parent = model
	model.PrimaryPart = base
	model.Parent = container()
	revive.accelerator = model
	revive.acceleratorCFrame = cframe

	local prompt = makePrompt(base, "prompt.revive", R.channelTime, Config.Match.revive.acceleratorDistance)
	local beam: Part? = nil
	local function removeBeam()
		if beam then
			beam:Destroy()
			beam = nil
		end
	end
	prompt.PromptButtonHoldBegan:Connect(function(player)
		if player ~= revive.carriedBy then
			return
		end
		revive.holdStartedAt = os.clock()
		-- Faisceau lumineux visible par tous : la réanimation est un risque.
		removeBeam()
		local light = Instance.new("Part")
		light.Name = "ReviveBeam"
		light.Size = Vector3.new(2.5, 300, 2.5)
		light.CFrame = base.CFrame * CFrame.new(0, 150, 0)
		light.Color = color
		light.Material = Enum.Material.Neon
		light.Transparency = 0.35
		light.Anchored = true
		light.CanCollide = false
		light.CanQuery = false
		light.CastShadow = false
		light.Parent = model
		beam = light
	end)
	prompt.PromptButtonHoldEnded:Connect(function()
		task.defer(removeBeam)
	end)
	prompt.Triggered:Connect(function(player)
		if player ~= revive.carriedBy or revives[revive.dead] ~= revive then
			return
		end
		local started = revive.holdStartedAt
		revive.holdStartedAt = nil
		if started == nil or os.clock() - started < R.channelTime * 0.85 - 0.05 then
			ServerNet.flag(player, "Revive", "maintien trop court")
			return
		end
		local root = rootOf(player)
		if root == nil or (root.Position - base.Position).Magnitude > Config.Match.revive.acceleratorDistance + 4 then
			return
		end
		local spawnAt = cframe * CFrame.new(0, 3, -5)
		finish(revive)
		ReviveService.Revived:Fire(revive.dead, spawnAt)
	end)
end

--[[
	Un joueur de duo vient de mourir alors que son coéquipier est vivant :
	création de l'orbe et de l'Accélérateur.
]]
function ReviveService.begin(dead: Player, teammate: Player, teamId: string, deathPosition: Vector3, random: Random)
	local existing = revives[dead]
	if existing then
		finish(existing)
	end
	local color = teamColor(teamId)
	local revive: Revive = {
		dead = dead,
		teammate = teammate,
		teamId = teamId,
		expiresAt = now() + R.orbLifetime,
		orb = nil :: any,
		orbFighter = nil,
		carriedBy = nil,
		accelerator = nil :: any,
		acceleratorCFrame = CFrame.new(),
		holdStartedAt = nil,
	}
	revives[dead] = revive
	buildOrb(revive, deathPosition, color)
	buildAccelerator(revive, chooseSpot(deathPosition, random), color)
	sendState(revive)
end

-- Le coéquipier meurt ou quitte la partie : plus de réanimation possible.
function ReviveService.abandonFor(teammate: Player)
	for _, revive in table.clone(revives) do
		if revive.teammate == teammate then
			lose(revive, "abandoned")
		end
	end
end

function ReviveService.isPending(dead: Player): boolean
	return revives[dead] ~= nil
end

function ReviveService.clearAll()
	for _, revive in table.clone(revives) do
		finish(revive)
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
end

function ReviveService.init()
	CombatService.FighterDied:Connect(function(fighter)
		for _, revive in revives do
			if revive.orbFighter == fighter then
				lose(revive, "destroyed")
				return
			end
		end
	end)
end

function ReviveService.start()
	RunService.Heartbeat:Connect(function()
		local time = now()
		for _, revive in table.clone(revives) do
			if time >= revive.expiresAt then
				lose(revive, "expired")
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local revive = revives[player]
		if revive then
			lose(revive, "abandoned")
		end
		ReviveService.abandonFor(player)
	end)
end

return ReviveService
