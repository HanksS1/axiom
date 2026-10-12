--!strict
--[[
	GadgetService : gadgets (section 8.5), 2 emplacements.

	L'état (efficacité) module la stat principale : durée, PV du mur, portée,
	et la recharge est divisée par le multiplicateur d'état.

	- Bottes de saut : saut propulsé (~20 studs), recharge 15 s.
	- Grappin : s'accroche à une surface (≤ 60 studs), recharge 12 s.
	- Drone de reconnaissance : révèle joueurs et robots (40 studs, 8 s) au
	  joueur et à son coéquipier ; destructible ; 2 utilisations par partie.
	- Mur déployable : 6 × 8 studs, 300 PV, 45 s ; 2 utilisations.
	- Fumigène : nuage de 15 studs pendant 12 s ; 3 utilisations.

	Les déplacements (saut, grappin) sont appliqués par le client sur son
	personnage, APRÈS validation serveur, qui accorde la tolérance de vitesse
	correspondante au contrôle anti-triche.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Guard = require(Shared.Util.Guard)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local ItemRules = require(Shared.Items.ItemRules)
local Types = require(Shared.Types)

local Fighter = require(script.Parent.Parent.Combat.Fighter)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local CombatService = require(script.Parent.CombatService)
local MovementGuardService = require(script.Parent.MovementGuardService)

type Fighter = Fighter.Fighter

local G = Config.Match.gadgets

local GadgetService = {}

type GadgetState = { cooldownUntil: number, usesLeft: number? }

-- État par objet (uid) pour la partie en cours : utilisations et recharge.
local states: { [string]: GadgetState } = {}
local folder: Folder?

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function gadgetFolder(): Folder
	if folder == nil or folder.Parent == nil then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "Gadgets"
		newFolder.Parent = Workspace
		folder = newFolder
	end
	return folder :: Folder
end

local function stateFor(item: Types.ItemInstance, def: any): GadgetState
	local state = states[item.uid]
	if state == nil then
		state = { cooldownUntil = 0, usesLeft = def.usesPerMatch }
		states[item.uid] = state
	end
	return state
end

-- Stat modulée par l'état (les dimensions physiques ne le sont pas).
local function stat(def: any, key: string, efficiency: number): number
	local value = def.stats[key] or 0
	if Config.Equipment.gadgetFixedStats[key] then
		return value
	end
	return value * efficiency
end

local function sendState(player: Player, slot: string, item: Types.ItemInstance, state: GadgetState)
	ServerNet.fire("GadgetState", player, slot, item.uid, state.usesLeft, state.cooldownUntil)
end

local function teammates(owner: Player): { Player }
	local list = { owner }
	local team = owner:GetAttribute("TeamId")
	if team ~= nil then
		for _, other in Players:GetPlayers() do
			if other ~= owner and other:GetAttribute("TeamId") == team then
				table.insert(list, other)
			end
		end
	end
	return list
end

local function objectPart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: EnumItem): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function deployWall(owner: Fighter, def: any, efficiency: number)
	local root = owner.root
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local width, height = stat(def, "width", efficiency), stat(def, "height", efficiency)
	local base = root.Position + look * G.wallDistance
	local cframe = CFrame.lookAt(base, base + look) * CFrame.new(0, height / 2 - 2.5, 0)
	local model = Instance.new("Model")
	model.Name = "DeployableWall"
	local wall = objectPart(
		"HumanoidRootPart",
		Vector3.new(width, height, 0.8),
		cframe,
		Color3.fromRGB(60, 66, 76),
		Enum.Material.DiamondPlate
	)
	wall.Parent = model
	local strip = objectPart(
		"Strip",
		Vector3.new(width, 0.25, 0.85),
		cframe * CFrame.new(0, height / 2 - 0.4, 0),
		Color3.fromRGB(0, 229, 255),
		Enum.Material.Neon
	)
	strip.CanCollide = false
	strip.CanQuery = false
	strip.Parent = model
	model.PrimaryPart = wall
	model.Parent = gadgetFolder()
	local fighter = Fighter.newObject(model, wall, stat(def, "health", efficiency), Fighter.teamOf(owner))
	CombatService.register(fighter)
	task.delay(stat(def, "duration", efficiency), function()
		if model.Parent then
			model:Destroy()
		end
	end)
end

local function deploySmoke(position: Vector3, def: any, efficiency: number)
	local radius = stat(def, "radius", efficiency)
	local cloud = Instance.new("Part")
	cloud.Name = "Smoke"
	cloud.Shape = Enum.PartType.Ball
	cloud.Size = Vector3.one * radius * 2
	cloud.CFrame = CFrame.new(position)
	cloud.Color = Color3.fromRGB(150, 155, 160)
	cloud.Material = Enum.Material.SmoothPlastic
	cloud.Transparency = 0.15
	cloud.Anchored = true
	cloud.CanCollide = false
	cloud.CanQuery = false
	cloud.CanTouch = false
	cloud.CastShadow = false
	cloud:SetAttribute("Radius", radius)
	cloud.Parent = gadgetFolder()
	-- Lu par l'IA des robots (P4) : la fumée bloque leur vision.
	CollectionService:AddTag(cloud, "Smoke")
	task.delay(stat(def, "duration", efficiency), function()
		cloud:Destroy()
	end)
end

local function deployDrone(owner: Fighter, player: Player, def: any, efficiency: number)
	local position = owner.root.Position + Vector3.new(0, G.droneHoverHeight, 0)
	local model = Instance.new("Model")
	model.Name = "ReconDrone"
	local body = objectPart(
		"HumanoidRootPart",
		Vector3.new(1.6, 0.6, 1.6),
		CFrame.new(position),
		Color3.fromRGB(40, 44, 52),
		Enum.Material.Metal
	)
	body.CanCollide = false
	body.Parent = model
	local eye = objectPart(
		"Eye",
		Vector3.new(0.5, 0.5, 0.5),
		CFrame.new(position - Vector3.new(0, 0.4, 0)),
		Color3.fromRGB(0, 229, 255),
		Enum.Material.Neon
	)
	eye.CanCollide = false
	eye.CanQuery = false
	eye.Parent = model
	model.PrimaryPart = body
	model.Parent = gadgetFolder()
	local drone = Fighter.newObject(model, body, G.droneHealth, Fighter.teamOf(owner))
	CombatService.register(drone)

	local radius = stat(def, "radius", efficiency)
	local duration = stat(def, "duration", efficiency)
	local endsAt = now() + duration
	local viewers = teammates(player)
	task.spawn(function()
		-- Révélation périodique tant que le drone existe.
		while Fighter.isAlive(drone) and now() < endsAt and model.Parent do
			local revealed = {}
			for _, other in CombatService.allFighters() do
				if
					other.kind ~= "object"
					and Fighter.isAlive(other)
					and not Fighter.sameTeam(other, owner)
					and other ~= owner
					and (other.root.Position - position).Magnitude <= radius
				then
					table.insert(revealed, other.character)
				end
			end
			for _, viewer in viewers do
				if viewer.Parent == Players then
					ServerNet.fire("Reveal", viewer, revealed, 0.7)
				end
			end
			task.wait(0.5)
		end
		if model.Parent then
			model:Destroy()
		end
	end)
end

--[[
	Utilisation d'un gadget. `target` : point visé (grappin, fumigène).
]]
local function onUseGadget(player: Player, slot: string, target: Vector3?)
	local fighter = CombatService.getFighter(player)
	local bag = if fighter then fighter.bag else nil
	if fighter == nil or bag == nil or not Fighter.isAlive(fighter) then
		return
	end
	Fighter.refresh(fighter, now())
	if fighter.move.stunned or fighter.usingItemId ~= nil then
		return
	end
	local item = (bag.equipped :: any)[slot] :: Types.ItemInstance?
	local info = if item then ItemCatalog.get(item.itemId) else nil
	if item == nil or info == nil or info.category ~= "gadget" then
		return
	end
	local def = info.def
	local efficiency = ItemRules.efficiency(item.condition :: number)
	local state = stateFor(item, def)
	local time = now()
	if time < state.cooldownUntil then
		return
	end
	if state.usesLeft ~= nil and state.usesLeft <= 0 then
		ServerNet.notify(player, "gadget.noUses")
		return
	end

	local root = fighter.root
	local itemId = item.itemId
	if itemId == "jump_boots" then
		local height = stat(def, "jumpHeight", efficiency)
		local velocity = math.sqrt(2 * Workspace.Gravity * height)
		MovementGuardService.grantAllowance(player, velocity, 2.5, height + 4)
		ServerNet.fire("GadgetEffect", player, "jump", velocity)
	elseif itemId == "grappling_hook" then
		local range = stat(def, "range", efficiency)
		if target == nil or (target - root.Position).Magnitude > range + 4 then
			return
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { fighter.character }
		local hit = Workspace:Raycast(root.Position, target - root.Position, params)
		if hit == nil or (hit.Position - target).Magnitude > 4 then
			return -- pas de surface accrochable à cet endroit
		end
		local rise = math.max(0, target.Y - root.Position.Y) + 6
		MovementGuardService.grantAllowance(player, G.grappleSpeed * 1.2, G.grappleMaxTime + 0.6, rise)
		ServerNet.fire("GadgetEffect", player, "grapple", hit.Position)
		ServerNet.fireAllExcept("GadgetVisual", player, player, "grapple", hit.Position)
	elseif itemId == "recon_drone" then
		deployDrone(fighter, player, def, efficiency)
	elseif itemId == "deployable_wall" then
		deployWall(fighter, def, efficiency)
	elseif itemId == "smoke_deployer" then
		local position = root.Position
		if target and (target - root.Position).Magnitude <= 30 then
			position = target
		end
		deploySmoke(position, def, efficiency)
	else
		return
	end

	if def.cooldown then
		state.cooldownUntil = time + def.cooldown / efficiency
	end
	if state.usesLeft ~= nil then
		state.usesLeft -= 1
	end
	sendState(player, slot, item, state)
end

-- Remet à zéro utilisations et recharges (début / fin de partie).
function GadgetService.reset()
	table.clear(states)
	if folder then
		folder:Destroy()
		folder = nil
	end
end

function GadgetService.init()
	ServerNet.onEvent(
		"UseGadget",
		Guard.tuple(Guard.enum({ "gadget1", "gadget2" }), Guard.optional(Guard.vector3(100_000))),
		onUseGadget
	)
end

function GadgetService.start() end

return GadgetService
