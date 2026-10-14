--!strict
--[[
	LootService : conteneurs de loot dans le monde (section 9).

	Trois sortes de conteneurs :
	- "crate"    : caisses de la carte (ravitaillement, coffre militaire,
	               casier d'AXIOM) — contenu généré à l'ouverture ;
	- "deathbag" : sac de dépouille d'un combattant mort (tout son équipement) ;
	- "ground"   : objets posés au sol (jetés, ou arme remplacée).

	Interaction : ProximityPrompt (maintenir), qui fonctionne au clavier, à la
	manette et au tactile. Le serveur vérifie la durée réelle de maintien
	(début enregistré côté serveur) et la distance. Une fois ouvert, le
	contenu est envoyé aux joueurs qui le consultent ; chaque prise est
	validée (distance, cadence, place dans le sac).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Guard = require(Shared.Util.Guard)
local InventoryLogic = require(Shared.Items.InventoryLogic)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local ItemRules = require(Shared.Items.ItemRules)
local ItemModels = require(Shared.Visuals.ItemModels)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)

local Fighter = require(script.Parent.Parent.Combat.Fighter)
local ItemFactory = require(script.Parent.Parent.Inventory.ItemFactory)
local LootGenerator = require(script.Parent.Parent.Loot.LootGenerator)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local CombatService = require(script.Parent.CombatService)

type ItemInstance = Types.ItemInstance
type Fighter = Fighter.Fighter

export type ContainerKind = "crate" | "deathbag" | "ground"

export type Container = {
	id: string,
	kind: ContainerKind,
	crateType: string?,
	opened: boolean,
	items: { ItemInstance },
	model: Model,
	prompt: ProximityPrompt,
	viewers: { [Player]: boolean },
	holdStarts: { [Player]: number },
}

local Pickup = Config.Match.pickup

local LootService = {}

-- (position, rayon) : bruit qui attire les robots (alarme de casier…), utilisé en P4.
LootService.NoiseMade = Signal.new() :: Signal.Signal<Vector3, number>
-- (conteneur) : une caisse vient d'être ouverte.
LootService.CrateOpened = Signal.new() :: Signal.Signal<Container>
-- (joueur, objet) : un objet a été pris dans un conteneur.
LootService.ItemTaken = Signal.new() :: Signal.Signal<Player, ItemInstance>

local containers: { [string]: Container } = {}
local lastTake: { [Player]: number } = {}
local nextId = 0
local folder: Folder
local random = Random.new()

-- Mode de la partie en cours (fixé par le déroulé de partie ; « easy » dans l'arène).
LootService.modeId = "easy"

local CRATE_STYLE: { [string]: { color: Color3, accent: Color3, size: Vector3 } } = {
	supply = { color = Color3.fromRGB(70, 78, 88), accent = Color3.fromRGB(0, 229, 255), size = Vector3.new(3, 2, 2) },
	military = {
		color = Color3.fromRGB(64, 74, 52),
		accent = Color3.fromRGB(255, 138, 0),
		size = Vector3.new(4, 2.4, 2.4),
	},
	medical = {
		color = Color3.fromRGB(220, 224, 230),
		accent = Color3.fromRGB(255, 59, 59),
		size = Vector3.new(3, 2, 2),
	},
	parts_bin = {
		color = Color3.fromRGB(110, 84, 60),
		accent = Color3.fromRGB(255, 176, 32),
		size = Vector3.new(3.2, 2.2, 2.2),
	},
	tech = {
		color = Color3.fromRGB(40, 44, 60),
		accent = Color3.fromRGB(176, 92, 255),
		size = Vector3.new(3, 2.2, 2),
	},
	axiom_locker = {
		color = Color3.fromRGB(24, 24, 30),
		accent = Color3.fromRGB(255, 59, 59),
		size = Vector3.new(2.4, 5, 2),
	},
}

local function containerPosition(container: Container): Vector3
	local primary = container.model.PrimaryPart
	return if primary then primary.Position else container.model:GetPivot().Position
end

local function playerRoot(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function isNear(player: Player, container: Container, extra: number?): boolean
	local root = playerRoot(player)
	if root == nil then
		return false
	end
	local reach = math.max(container.prompt.MaxActivationDistance, Pickup.maxDistance) + (extra or 3)
	return (root.Position - containerPosition(container)).Magnitude <= reach
end

local function newPart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: EnumItem): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = name == "Body"
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function makePrompt(parent: BasePart, actionKey: string, objectKey: string, holdDuration: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	-- Textes traduits côté client à partir de ces clés (chaque joueur a sa langue).
	prompt:SetAttribute("ActionKey", actionKey)
	prompt:SetAttribute("ObjectKey", objectKey)
	prompt.ActionText = actionKey
	prompt.ObjectText = objectKey
	prompt.HoldDuration = holdDuration
	prompt.MaxActivationDistance = Pickup.maxDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = parent
	return prompt
end

-- Contenu envoyé au client (copie, aucune référence partagée).
local function view(container: Container): { [string]: any }
	local items = {}
	for _, item in container.items do
		table.insert(items, table.clone(item))
	end
	return {
		id = container.id,
		kind = container.kind,
		crateType = container.crateType,
		items = items,
	}
end

local function broadcast(container: Container)
	local payload = view(container)
	for viewer in container.viewers do
		if viewer.Parent == Players then
			ServerNet.fire("ContainerSync", viewer, payload)
		end
	end
end

local function closeFor(player: Player, container: Container)
	if container.viewers[player] then
		container.viewers[player] = nil
		ServerNet.fire("ContainerSync", player, { id = container.id, closed = true })
	end
end

local function destroyContainer(container: Container)
	for viewer in table.clone(container.viewers) do
		closeFor(viewer, container)
	end
	containers[container.id] = nil
	container.model:Destroy()
end

-- Pièce d'habillage d'un conteneur (ni collision, ni tirs).
local function detail(
	model: Model,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: EnumItem
): Part
	local part = newPart(name, size, cframe, color, material)
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = model
	return part
end

local FRAME = Color3.fromRGB(24, 26, 31)
local STEEL = Color3.fromRGB(112, 118, 128)

--[[
	Habillage d'une caisse : couvercle articulé (il se lève à l'ouverture), montants,
	poignées, loquet, et un emblème propre à chaque type sur la face avant.
]]
local function dressCrate(
	model: Model,
	body: BasePart,
	style: { color: Color3, accent: Color3, size: Vector3 },
	crateType: string
)
	local sx, sy, sz = style.size.X, style.size.Y, style.size.Z
	local at = body.CFrame
	local front = -sz / 2 - 0.04
	local lidColor = style.color:Lerp(Color3.new(), 0.3)

	if crateType == "axiom_locker" then
		-- Casier d'AXIOM : porte pleine (charnière à gauche), fente rouge qui grésille.
		local door = detail(
			model,
			"Lid",
			Vector3.new(sx - 0.3, sy - 0.5, 0.14),
			at * CFrame.new(0, 0, front - 0.04),
			lidColor,
			Enum.Material.DiamondPlate
		)
		door:SetAttribute("Hinge", "side")
		local eye = detail(
			model,
			"Eye",
			Vector3.new(sx * 0.5, 0.14, 0.08),
			at * CFrame.new(0, sy * 0.28, front - 0.14),
			style.accent,
			Enum.Material.Neon
		)
		CollectionService:AddTag(eye, "Flicker")
		detail(
			model,
			"Vent",
			Vector3.new(sx * 0.7, 0.2, sz * 0.7),
			at * CFrame.new(0, sy / 2 + 0.1, 0),
			FRAME,
			Enum.Material.Metal
		)
		for _, side in { -1, 1 } do
			detail(
				model,
				"Rail",
				Vector3.new(0.14, sy, 0.3),
				at * CFrame.new(side * (sx / 2 + 0.07), 0, 0),
				FRAME,
				Enum.Material.Metal
			)
		end
		return
	end

	local lid = detail(
		model,
		"Lid",
		Vector3.new(sx + 0.16, 0.24, sz + 0.16),
		at * CFrame.new(0, sy / 2 + 0.12, 0),
		lidColor,
		Enum.Material.DiamondPlate
	)
	lid:SetAttribute("Hinge", "top")
	for _, cornerX in { -1, 1 } do
		for _, cornerZ in { -1, 1 } do
			detail(
				model,
				"Corner",
				Vector3.new(0.22, sy + 0.04, 0.22),
				at * CFrame.new(cornerX * sx / 2, 0, cornerZ * sz / 2),
				FRAME,
				Enum.Material.Metal
			)
		end
		detail(
			model,
			"Handle",
			Vector3.new(0.12, 0.3, sz * 0.4),
			at * CFrame.new(cornerX * (sx / 2 + 0.08), sy * 0.1, 0),
			FRAME,
			Enum.Material.Metal
		)
	end
	detail(
		model,
		"Latch",
		Vector3.new(0.5, 0.36, 0.12),
		at * CFrame.new(0, sy * 0.36, front),
		STEEL,
		Enum.Material.Metal
	)

	-- Emblème : on reconnaît le type de caisse de loin.
	local function mark(name: string, width: number, height: number, x: number, y: number, rotation: number?): Part
		return detail(
			model,
			name,
			Vector3.new(width, height, 0.06),
			at * CFrame.new(x, y, front) * CFrame.Angles(0, 0, rotation or 0),
			style.accent,
			Enum.Material.Neon
		)
	end
	local low = -sy * 0.12
	if crateType == "medical" then
		mark("CrossH", 0.9, 0.26, 0, low)
		mark("CrossV", 0.26, 0.9, 0, low)
	elseif crateType == "military" then
		mark("ChevronL", 0.16, 0.9, -0.34, low, math.rad(-32))
		mark("ChevronR", 0.16, 0.9, 0.34, low, math.rad(32))
	elseif crateType == "tech" then
		CollectionService:AddTag(mark("Screen", 1.3, 0.6, 0, low), "Flicker")
	elseif crateType == "parts_bin" then
		for index = -1, 1 do
			detail(
				model,
				"Slat",
				Vector3.new(sx * 0.7, 0.14, 0.08),
				at * CFrame.new(0, low + index * 0.34, front),
				FRAME,
				Enum.Material.Metal
			)
		end
		mark("Tag", 0.4, 0.2, sx * 0.3, sy * 0.22)
	else
		mark("CellA", 0.3, 0.5, -0.3, low)
		mark("CellB", 0.3, 0.5, 0.3, low)
	end
end

-- Ouvre le couvercle (ou la porte) d'une caisse.
local function openLid(model: Model)
	local lid = model:FindFirstChild("Lid")
	local body = model.PrimaryPart
	if lid == nil or not lid:IsA("BasePart") or body == nil then
		return
	end
	local half = body.Size / 2
	if lid:GetAttribute("Hinge") == "side" then
		-- Porte : pivote vers l'extérieur autour de son bord gauche.
		local hinge = body.CFrame * CFrame.new(-lid.Size.X / 2, 0, -half.Z - 0.08)
		lid.CFrame = hinge * CFrame.Angles(0, math.rad(75), 0) * CFrame.new(lid.Size.X / 2, 0, 0)
	else
		-- Couvercle : se lève autour de son bord arrière.
		local hinge = body.CFrame * CFrame.new(0, half.Y, half.Z)
		lid.CFrame = hinge * CFrame.Angles(math.rad(62), 0, 0) * CFrame.new(0, lid.Size.Y / 2, -lid.Size.Z / 2)
	end
end

-- Meilleur objet d'un tas : c'est lui qu'on montre posé au sol.
local function bestItem(items: { ItemInstance }): ItemInstance?
	local best: ItemInstance? = nil
	local bestValue = -1
	for _, item in items do
		local value = ItemRules.value(item) + (item.condition or 0)
		if value > bestValue then
			best, bestValue = item, value
		end
	end
	return best
end

-- Butin au sol : le meilleur objet du tas est posé là, visible (même modèle qu'en main).
local function showGroundItem(container: Container)
	local item = bestItem(container.items)
	local shown = container.model:GetAttribute("ShownItem")
	if item == nil or shown == item.itemId then
		return
	end
	local existing = container.model:FindFirstChild("Display")
	if existing then
		existing:Destroy()
	end
	local blueprint = ItemModels.blueprint(item.itemId)
	local body = container.model.PrimaryPart
	if blueprint == nil or body == nil then
		return
	end
	local display = Instance.new("Model")
	display.Name = "Display"
	local center, extent = ItemModels.bounds(blueprint)
	local ground = body.Position - Vector3.new(0, body.Size.Y / 2, 0)
	local info = ItemCatalog.get(item.itemId)
	local turn = CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
	local cframe
	if info and (info.category == "ranged" or info.category == "melee") then
		-- Une arme repose sur le flanc (son axe X devient la verticale).
		cframe = CFrame.new(ground + Vector3.new(0, extent.X / 2 - center.X + 0.06, 0))
			* turn
			* CFrame.Angles(0, 0, math.rad(90))
	else
		cframe = CFrame.new(ground + Vector3.new(0, extent.Y / 2 - center.Y + 0.06, 0)) * turn
	end
	ItemModels.place(item.itemId, display, cframe)
	display.Parent = container.model
	container.model:SetAttribute("ShownItem", item.itemId)
end

-- Couleur d'un tas d'objets : l'état le plus élevé qu'il contient.
local function bestConditionColor(items: { ItemInstance }): Color3
	local best = 0
	for _, item in items do
		best = math.max(best, item.condition or 0)
	end
	local def = Config.Conditions.list[best]
	return if def then def.color else Color3.fromRGB(0, 229, 255)
end

local function refreshVisual(container: Container)
	if container.kind ~= "crate" then
		local glow = container.model:FindFirstChild("Glow")
		if glow and glow:IsA("BasePart") then
			glow.Color = bestConditionColor(container.items)
		end
		if container.kind == "ground" then
			showGroundItem(container)
		end
	end
end

local function afterChange(container: Container)
	if #container.items == 0 and container.kind ~= "crate" then
		destroyContainer(container)
		return
	end
	refreshVisual(container)
	broadcast(container)
end

local function openFor(player: Player, container: Container)
	container.viewers[player] = true
	ServerNet.fire("ContainerSync", player, view(container))
end

local function register(container: Container)
	containers[container.id] = container
	container.model:SetAttribute("ContainerId", container.id)
	container.model:SetAttribute("ContainerKind", container.kind)
	container.model.Parent = folder

	container.prompt.PromptButtonHoldBegan:Connect(function(player)
		container.holdStarts[player] = os.clock()
		if container.kind == "crate" and not container.opened and container.crateType then
			local def = Config.Loot.crates[container.crateType]
			if def.alarmRadius then
				-- Casier d'AXIOM : alarme audible (et bruit pour les robots).
				ServerNet.fireAll("LootAlarm", containerPosition(container), def.alarmRadius)
				LootService.NoiseMade:Fire(containerPosition(container), def.alarmRadius)
			end
		end
	end)
	container.prompt.PromptButtonHoldEnded:Connect(function(player)
		task.defer(function()
			container.holdStarts[player] = nil
		end)
	end)
	container.prompt.Triggered:Connect(function(player)
		LootService.interact(player, container)
	end)
end

local function newContainer(
	kind: ContainerKind,
	model: Model,
	prompt: ProximityPrompt,
	items: { ItemInstance }
): Container
	nextId += 1
	return {
		id = "c" .. nextId,
		kind = kind,
		crateType = nil,
		opened = kind ~= "crate",
		items = items,
		model = model,
		prompt = prompt,
		viewers = {},
		holdStarts = {},
	}
end

-- Interaction validée par le serveur (durée de maintien, distance, vie).
-- Première ouverture d'une caisse : son contenu est généré à ce moment.
local function openCrate(container: Container)
	container.opened = true
	container.items = LootGenerator.crate(container.crateType :: string, LootService.modeId, random, ItemFactory.create)
	-- Caisse ouverte : on peut la refouiller instantanément.
	container.prompt.HoldDuration = Pickup.holdTime
	container.prompt:SetAttribute("ActionKey", "prompt.search")
	container.prompt.ActionText = "prompt.search"
	container.model:SetAttribute("Opened", true)
	local light = container.model:FindFirstChild("Accent")
	if light and light:IsA("BasePart") then
		light.Transparency = 0.7
	end
	openLid(container.model)
	LootService.CrateOpened:Fire(container)
end

function LootService.interact(player: Player, container: Container)
	if containers[container.id] ~= container then
		return
	end
	local fighter = CombatService.getFighter(player)
	if fighter == nil or not Fighter.isAlive(fighter) or fighter.bag == nil then
		return
	end
	if not isNear(player, container) then
		ServerNet.flag(player, "LootInteract", "conteneur hors de portée")
		return
	end
	local hold = container.prompt.HoldDuration
	if hold > 0 then
		local started = container.holdStarts[player]
		container.holdStarts[player] = nil
		if started == nil or os.clock() - started < hold * 0.85 - 0.05 then
			ServerNet.flag(player, "LootInteract", "maintien trop court")
			return
		end
	end

	if container.kind == "crate" and not container.opened then
		openCrate(container)
	end

	-- Un seul objet au sol : ramassage direct.
	if container.kind == "ground" and #container.items == 1 then
		local only = container.items[1]
		LootService.take(player, container, only.uid, "auto", nil)
		if containers[container.id] == container and #container.items > 0 then
			openFor(player, container) -- sac plein : proposer l'échange
		end
		return
	end
	openFor(player, container)
end

--[[
	Prend un objet d'un conteneur.
	- "equip" : équipe l'objet ; l'objet remplacé reste dans le conteneur.
	- "bag"   : range dans le sac (les piles fusionnent ; un reste éventuel
	            demeure dans le conteneur). Avec `swapUid`, l'objet du sac
	            désigné est d'abord posé dans le conteneur (sac plein).
	- "auto"  : équipe si l'emplacement est libre, sinon range dans le sac.
]]
function LootService.take(player: Player, container: Container, uid: string, mode: string, swapUid: string?)
	local fighter = CombatService.getFighter(player)
	local bag = if fighter then fighter.bag else nil
	if fighter == nil or bag == nil or not Fighter.isAlive(fighter) then
		return
	end
	local index: number? = nil
	for i, item in container.items do
		if item.uid == uid then
			index = i
			break
		end
	end
	if index == nil then
		ServerNet.fire("ContainerSync", player, view(container)) -- déjà pris : resynchronisation
		return
	end
	local item = container.items[index]
	local info = ItemCatalog.get(item.itemId)
	if info == nil then
		return
	end

	local slot: Types.SlotName? = InventoryLogic.slotFor(bag, item.itemId) :: any
	local wantsEquip = mode == "equip" or (mode == "auto" and slot ~= nil and (bag.equipped :: any)[slot] == nil)

	if wantsEquip and slot ~= nil then
		local ok, failure, previous = InventoryLogic.equipFromOutside(bag, item, slot)
		if not ok then
			ServerNet.notify(player, "inventory.failure." .. tostring(failure))
			return
		end
		table.remove(container.items, index)
		if previous then
			table.insert(container.items, previous) -- « l'arme équipée tombe au sol »
		end
	else
		if swapUid ~= nil and not InventoryLogic.canStore(bag, item) then
			local swapped = InventoryLogic.removeFromBag(bag, swapUid)
			if swapped == nil then
				return
			end
			if not InventoryLogic.canStore(bag, item) then
				-- L'échange ne libère pas assez de place : on annule.
				InventoryLogic.store(bag, swapped)
				ServerNet.notify(player, "inventory.failure.bag_full")
				return
			end
			table.insert(container.items, swapped)
		end
		local stored, leftover = InventoryLogic.store(bag, item)
		if not stored then
			ServerNet.notify(player, "inventory.failure.bag_full")
			ServerNet.fire("ContainerSync", player, view(container))
			return
		end
		if leftover == nil then
			local current = table.find(container.items, item)
			if current then
				table.remove(container.items, current)
			end
		end
	end

	CombatService.equipmentChanged(fighter)
	if fighter.onInventoryChanged then
		fighter.onInventoryChanged()
	end
	afterChange(container)
	LootService.ItemTaken:Fire(player, item)
end

--[[
	« Tout prendre » : range dans le sac tout ce qui y tient (l'équipement va
	dans son emplacement s'il est vide), le plus précieux d'abord. Ce qui ne
	tient pas reste dans le conteneur. Retourne le nombre d'objets pris.
]]
function LootService.takeAll(player: Player, container: Container): number
	local fighter = CombatService.getFighter(player)
	local bag = if fighter then fighter.bag else nil
	if fighter == nil or bag == nil or not Fighter.isAlive(fighter) then
		return 0
	end
	-- Ce qui ne tient pas reste dans le conteneur : le sac n'est jamais surchargé.
	local taken, kept = InventoryLogic.takeAll(bag, container.items)
	for _, item in taken do
		local index = table.find(container.items, item)
		if index then
			table.remove(container.items, index)
		end
	end
	if #taken == 0 then
		ServerNet.notify(player, "inventory.failure.bag_full")
		return 0
	end
	if #kept > 0 then
		ServerNet.notify(player, "loot.someLeft", { count = #kept })
	end
	CombatService.equipmentChanged(fighter)
	if fighter.onInventoryChanged then
		fighter.onInventoryChanged()
	end
	afterChange(container)
	for _, item in taken do
		LootService.ItemTaken:Fire(player, item)
	end
	return #taken
end

-- Bac à sable (hors partie : arène d'entraînement, Terminus) : aucun butin ne
-- peut apparaître, donc rien ne peut être ramassé. Activé par ArenaService,
-- désactivé au début d'une partie (MatchService → ArenaService.setSandbox).
local sandbox = true

function LootService.setSandbox(enabled: boolean)
	sandbox = enabled
end

function LootService.isSandbox(): boolean
	return sandbox
end

-- Pose des objets au sol, devant le joueur (objet jeté, remplacé…). Rien en bac à sable.
function LootService.dropToGround(position: Vector3, items: { ItemInstance }): Container?
	if #items == 0 or sandbox then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	params.RespectCanCollide = true
	local hit = Workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -20, 0), params)
	local ground = if hit then hit.Position else position

	local model = Instance.new("Model")
	model.Name = "GroundLoot"
	local body = newPart(
		"Body",
		Vector3.new(1.2, 0.6, 1.2),
		CFrame.new(ground + Vector3.new(0, 0.3, 0)),
		Color3.fromRGB(40, 44, 52),
		Enum.Material.Metal
	)
	body.CanCollide = false
	-- Socle invisible (il porte l'invite) : c'est l'objet lui-même qu'on voit, sur un halo
	-- à la couleur de son état.
	body.Transparency = 1
	body.Parent = model
	local glow = newPart(
		"Glow",
		Vector3.new(0.1, 2.2, 2.2),
		CFrame.new(ground + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		bestConditionColor(items),
		Enum.Material.Neon
	)
	glow.Shape = Enum.PartType.Cylinder
	glow.Transparency = 0.35
	glow.CanQuery = false
	glow.Parent = model
	model.PrimaryPart = body
	local prompt = makePrompt(body, "prompt.pickup", "loot.ground", Pickup.holdTime)
	local container = newContainer("ground", model, prompt, items)
	showGroundItem(container)
	register(container)
	return container
end

-- Sac de dépouille : tout ce que portait le combattant mort.
function LootService.spawnDeathBag(position: Vector3, items: { ItemInstance }, ownerName: string?): Container?
	if #items == 0 or sandbox then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "DeathBag"
	local body = newPart(
		"Body",
		Vector3.new(2, 1.4, 1.6),
		CFrame.new(position - Vector3.new(0, 2.2, 0)),
		Color3.fromRGB(30, 30, 36),
		Enum.Material.Fabric
	)
	-- Le sac de dépouille est un grand sac couché (même modèle que le sac des caisses) ;
	-- la pièce d'origine reste, invisible, pour la collision et l'invite.
	body.Transparency = 1
	body.Parent = model
	ItemModels.place(
		"backpack_large",
		model,
		body.CFrame * CFrame.new(0, -0.25, 0) * CFrame.Angles(math.rad(90), 0, 0),
		{
			filter = function(spec)
				return spec.name ~= "Body"
			end,
		}
	)
	local sack = newPart(
		"Sack",
		Vector3.new(1.8, 0.9, 2.0),
		body.CFrame * CFrame.new(0, -0.25, 0),
		Color3.fromRGB(30, 30, 36),
		Enum.Material.Fabric
	)
	sack.CanQuery = false
	sack.Parent = model
	local glow = newPart(
		"Glow",
		Vector3.new(2.1, 0.12, 2.3),
		body.CFrame * CFrame.new(0, -0.68, 0),
		bestConditionColor(items),
		Enum.Material.Neon
	)
	glow.CanQuery = false
	glow.Parent = model
	model.PrimaryPart = body
	local prompt = makePrompt(body, "prompt.search", "loot.deathbag", Pickup.holdTime)
	if ownerName then
		model:SetAttribute("OwnerName", ownerName)
	end
	local container = newContainer("deathbag", model, prompt, items)
	register(container)
	return container
end

-- Caisse de la carte (fermée ; contenu généré à l'ouverture).
function LootService.spawnCrate(cframe: CFrame, crateType: string): Container
	local def = Config.Loot.crates[crateType]
	assert(def ~= nil, `type de caisse inconnu : {crateType}`)
	local style = CRATE_STYLE[crateType] or CRATE_STYLE.supply
	local model = Instance.new("Model")
	model.Name = "Crate_" .. crateType
	local body = newPart(
		"Body",
		style.size,
		cframe * CFrame.new(0, style.size.Y / 2, 0),
		style.color,
		Enum.Material.DiamondPlate
	)
	body.Parent = model
	local accent = newPart(
		"Accent",
		Vector3.new(style.size.X + 0.05, 0.2, style.size.Z + 0.05),
		body.CFrame * CFrame.new(0, style.size.Y * 0.3, 0),
		style.accent,
		Enum.Material.Neon
	)
	accent.CanQuery = false
	accent.Parent = model
	model.PrimaryPart = body
	dressCrate(model, body, style, crateType)
	local prompt = makePrompt(body, "prompt.openCrate", "crate." .. crateType, def.openTime)
	local container = newContainer("crate", model, prompt, {})
	container.crateType = crateType
	model:SetAttribute("CrateType", crateType)
	register(container)
	return container
end

-- Conteneurs intéressants pour un mercenaire IA : caisses fermées, sacs et objets au sol.
function LootService.lootables(): { Container }
	local list = {}
	for _, container in containers do
		if
			(container.kind == "crate" and not container.opened) or (container.kind ~= "crate" and #container.items > 0)
		then
			table.insert(list, container)
		end
	end
	return list
end

function LootService.positionOf(container: Container): Vector3
	return containerPosition(container)
end

--[[
	Fouille par un mercenaire IA : ouvre la caisse si besoin et prend ce qui
	tient dans son sac, le plus précieux d'abord. Retourne le nombre d'objets pris.
]]
function LootService.botLoot(container: Container, bag: InventoryLogic.Inventory): number
	if containers[container.id] ~= container then
		return 0
	end
	if container.kind == "crate" and not container.opened then
		openCrate(container)
	end
	local sorted = table.clone(container.items)
	table.sort(sorted, function(a, b)
		return ItemRules.value(a) > ItemRules.value(b)
	end)
	local taken = 0
	for _, item in sorted do
		local stored, leftover = InventoryLogic.store(bag, item)
		if stored and leftover == nil then
			local index = table.find(container.items, item)
			if index then
				table.remove(container.items, index)
			end
			taken += 1
		end
	end
	afterChange(container)
	return taken
end

function LootService.remove(container: Container)
	if containers[container.id] == container then
		destroyContainer(container)
	end
end

function LootService.get(id: string): Container?
	return containers[id]
end

-- Supprime tous les conteneurs (fin de partie) ; l'état des armes est oublié.
function LootService.clearAll()
	for _, container in table.clone(containers) do
		destroyContainer(container)
	end
	Fighter.clearWeaponStates()
end

function LootService.init()
	folder = Instance.new("Folder")
	folder.Name = "Loot"
	folder.Parent = Workspace

	ServerNet.onEvent(
		"TakeItem",
		Guard.tuple(Guard.uid(), Guard.uid(), Guard.enum({ "auto", "bag", "equip" }), Guard.optional(Guard.uid())),
		function(player, containerId: string, uid: string, mode: string, swapUid: string?)
			local container = containers[containerId]
			if container == nil or not container.opened or not container.viewers[player] then
				return
			end
			if not isNear(player, container) then
				closeFor(player, container)
				return
			end
			-- Un clic par objet : une prise au plus par intervalle.
			local clock = os.clock()
			if clock - (lastTake[player] or 0) < Pickup.takeInterval * 0.8 then
				ServerNet.flag(player, "TakeItem", "ramassage trop rapide")
				return
			end
			lastTake[player] = clock
			LootService.take(player, container, uid, mode, swapUid)
		end
	)

	ServerNet.onEvent("TakeAll", Guard.tuple(Guard.uid()), function(player, containerId: string)
		local container = containers[containerId]
		if container == nil or not container.opened or not container.viewers[player] then
			return
		end
		if not isNear(player, container) then
			closeFor(player, container)
			return
		end
		lastTake[player] = os.clock()
		LootService.takeAll(player, container)
	end)

	ServerNet.onEvent("CloseContainer", Guard.tuple(Guard.uid()), function(player, containerId: string)
		local container = containers[containerId]
		if container then
			closeFor(player, container)
		end
	end)

	-- Mort : tout l'équipement tombe dans un sac de dépouille (jamais en bac à sable :
	-- l'équipement y est une copie, rendue intacte à la réapparition).
	CombatService.FighterDied:Connect(function(fighter)
		local bag = fighter.bag
		if bag == nil or sandbox then
			return
		end
		local items = InventoryLogic.drainAll(bag)
		Fighter.syncEquipment(fighter)
		if fighter.onInventoryChanged then
			fighter.onInventoryChanged()
		end
		local name = if fighter.player then fighter.player.DisplayName else nil
		LootService.spawnDeathBag(fighter.root.Position, items, name)
	end)
end

function LootService.start()
	Players.PlayerRemoving:Connect(function(player)
		lastTake[player] = nil
		for _, container in containers do
			container.viewers[player] = nil
			container.holdStarts[player] = nil
		end
	end)

	-- Ferme les conteneurs consultés de trop loin.
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.5 then
			return
		end
		accumulator = 0
		for _, container in containers do
			for viewer in container.viewers do
				if viewer.Parent ~= Players or not isNear(viewer, container, 6) then
					closeFor(viewer, container)
				end
			end
		end
	end)
end

return LootService
