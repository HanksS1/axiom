--!strict
--[[
	WeaponController : tir, mêlée, parade, recharge et changement d'arme (côté client).

	Le client tire localement (raycast + affichage immédiat) puis envoie
	l'INTENTION au serveur : { t, origin, direction, hits }. Le serveur
	valide et calcule seul les dégâts. L'état des munitions est prédit
	localement avec la même logique que le serveur (WeaponLogic), puis
	corrigé à chaque message CombatState.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Damage = require(Shared.Combat.Damage)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local Movement = require(Shared.Combat.Movement)
local Signal = require(Shared.Util.Signal)
local WeaponLogic = require(Shared.Combat.WeaponLogic)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local CameraController = require(script.Parent.CameraController)
local EffectsController = require(script.Parent.EffectsController)
local InputController = require(script.Parent.InputController)
local MovementController = require(script.Parent.MovementController)
local PanelState = require(script.Parent.Parent.UI.PanelState)

local Combat = Config.Combat

local WeaponController = {}

-- (endpoints) : tir local effectué (pour le HUD : recul du réticule).
WeaponController.Fired = Signal.new() :: Signal.Signal<>

export type Snapshot = {
	activeSlot: "ranged" | "melee",
	rangedId: string?,
	rangedCondition: number?,
	ammo: number,
	capacity: number?,
	reserve: number,
	heat: number,
	overheated: boolean,
	reloadProgress: number?, -- 0..1 pendant une recharge
	meleeId: string?,
	meleeCondition: number?,
	parrying: boolean,
	spread: number, -- degrés (réticule dynamique)
	usingItemId: string?, -- consommable en cours d'utilisation
	usingProgress: number?, -- 0..1
	boostRemaining: number?, -- secondes de Surcharge restantes
}

local player = Players.LocalPlayer
local random = Random.new()

local activeSlot: "ranged" | "melee" = "ranged"
local rangedId: string? = nil
local rangedCondition: number? = nil
local rangedDef: any = nil
local rangedState: WeaponLogic.RangedState? = nil
local reserve = 0
local meleeId: string? = nil
local meleeCondition: number? = nil
local meleeDef: any = nil
local using: { itemId: string, endsAt: number, startedAt: number }? = nil
local boostUntil = 0
local lastMeleeAt = -math.huge
local parrying = false
local triggerPending = false -- un appui de détente non encore consommé (semi-auto, rafale, mêlée)
local fireReadyAt = 0 -- après un sprint : délai avant de pouvoir tirer

local shotParams = RaycastParams.new()
shotParams.FilterType = Enum.RaycastFilterType.Exclude
shotParams.IgnoreWater = true

local meleeParams = OverlapParams.new()
meleeParams.FilterType = Enum.RaycastFilterType.Exclude

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function alive(): boolean
	local character = player.Character
	if character == nil or character:GetAttribute("Dead") == true then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function stunned(): boolean
	local character = player.Character
	return character ~= nil and character:GetAttribute("Stunned") == true
end

-- Applique l'état autoritaire reçu du serveur.
local function onCombatState(state: { [string]: any })
	if type(state) ~= "table" then
		return
	end
	activeSlot = if state.activeSlot == "melee" then "melee" else "ranged"
	local ranged = state.ranged
	if type(ranged) == "table" and type(ranged.itemId) == "string" then
		local info = ItemCatalog.get(ranged.itemId)
		if info and info.category == "ranged" then
			if rangedId ~= ranged.itemId or rangedState == nil then
				rangedState = WeaponLogic.new(info.def)
			end
			rangedId = ranged.itemId
			rangedCondition = ranged.condition
			rangedDef = info.def
			local local_ = rangedState :: WeaponLogic.RangedState
			local_.ammo = ranged.ammo or 0
			local_.heat = ranged.heat or 0
			local_.heatUpdatedAt = state.serverTime or serverNow()
			local_.overheatedUntil = ranged.overheatedUntil or 0
			local_.reloadEndsAt = ranged.reloadEndsAt
			if type(ranged.lastFireAt) == "number" then
				local_.lastFireAt = math.max(local_.lastFireAt, ranged.lastFireAt)
			end
			reserve = ranged.reserve or 0
		end
	else
		rangedId, rangedDef, rangedState, rangedCondition = nil, nil, nil, nil
	end
	if type(state.using) == "table" and type(state.using.itemId) == "string" then
		local startedAt = if using and using.itemId == state.using.itemId then using.startedAt else serverNow()
		using = { itemId = state.using.itemId, endsAt = state.using.endsAt, startedAt = startedAt }
	else
		using = nil
	end
	boostUntil = if type(state.boostUntil) == "number" then state.boostUntil else 0
	local melee = state.melee
	if type(melee) == "table" and type(melee.itemId) == "string" then
		local info = ItemCatalog.get(melee.itemId)
		meleeId = melee.itemId
		meleeCondition = melee.condition
		meleeDef = if info then info.def else nil
	else
		meleeId, meleeDef, meleeCondition = nil, nil, nil
	end
end

local function currentSpread(): number
	if rangedDef == nil then
		return 0
	end
	return Movement.spread(
		rangedDef.spread,
		MovementController.stance(),
		CameraController.isAiming(),
		MovementController.isMoving()
	)
end

-- Direction aléatoire dans un cône de `degrees` autour de `direction`.
local function spreadDirection(direction: Vector3, degrees: number): Vector3
	if degrees <= 0 then
		return direction
	end
	local frame = CFrame.lookAt(Vector3.zero, direction)
	local angle = math.rad(degrees) * math.sqrt(random:NextNumber())
	local roll = random:NextNumber(0, math.pi * 2)
	return (frame * CFrame.Angles(0, 0, roll) * CFrame.Angles(angle, 0, 0)).LookVector
end

-- Personnage (modèle avec humanoïde) auquel appartient une pièce.
local function characterOf(part: Instance): Model?
	local model = part:FindFirstAncestorOfClass("Model")
	while model ~= nil do
		if model:FindFirstChildOfClass("Humanoid") then
			return model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function muzzlePosition(character: Model, fallback: Vector3): Vector3
	local visual = character:FindFirstChild("WeaponVisual")
	local body = if visual then visual:FindFirstChild("Body") else nil
	if body and body:IsA("BasePart") then
		return (body.CFrame * CFrame.new(0, 0, -body.Size.Z / 2)).Position
	end
	return fallback
end

local function fireRanged()
	local character = player.Character
	local head = if character then character:FindFirstChild("Head") else nil
	local state = rangedState
	if character == nil or head == nil or not head:IsA("BasePart") or state == nil or rangedDef == nil then
		return
	end
	local def = rangedDef
	local now = serverNow()
	local canFire, block = WeaponLogic.canFire(def, state, now, reserve)
	if not canFire then
		if block == "empty" then
			WeaponController.reload() -- recharge automatique à vide
			triggerPending = false
		end
		return
	end
	-- Semi-auto / rafale : un tir par appui. Automatique : tant que la détente est maintenue.
	triggerPending = false

	-- Point visé : ce qui se trouve sous le réticule.
	shotParams.FilterDescendantsInstances = { character }
	local ray = CameraController.centerRay()
	local aimHit = Workspace:Raycast(ray.Origin, ray.Direction * 1000, shotParams)
	local aimPoint = if aimHit then aimHit.Position else ray.Origin + ray.Direction * 1000
	local origin = head.Position
	local baseDirection = (aimPoint - origin).Unit

	local ammoBefore = state.ammo
	local fired = WeaponLogic.fire(def, state, now)
	if fired.cellsConsumed > 0 then
		reserve = math.max(0, reserve - fired.cellsConsumed)
	end
	local bullets = if def.capacity then math.min(def.burstCount, ammoBefore) else def.burstCount
	local spread = currentSpread()
	local range = Damage.maxRange(def.effectiveRange)

	local hits = {}
	local endpoints = {}
	for _ = 1, bullets do
		for _ = 1, def.pellets do
			local direction = spreadDirection(baseDirection, spread)
			local result = Workspace:Raycast(origin, direction * range, shotParams)
			local endpoint = if result then result.Position else origin + direction * range
			table.insert(endpoints, endpoint)
			if result and result.Instance:IsA("BasePart") then
				local target = characterOf(result.Instance)
				if target and target ~= character and target:GetAttribute("Dead") ~= true then
					table.insert(hits, { part = result.Instance, position = result.Position })
				end
			end
		end
	end

	EffectsController.playShot(rangedId :: string, muzzlePosition(character, origin), endpoints, true)
	ClientNet.fire("FireWeapon", {
		t = now,
		origin = origin,
		direction = baseDirection,
		hits = hits,
	})
	WeaponController.Fired:Fire()
end

local function attackMelee()
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if character == nil or root == nil or not root:IsA("BasePart") or meleeDef == nil then
		return
	end
	local now = serverNow()
	if now - lastMeleeAt < 1 / meleeDef.attacksPerSecond then
		return
	end
	lastMeleeAt = now
	triggerPending = false
	EffectsController.playSwing(character)

	-- Zone de frappe devant le personnage : la cible vivante la plus proche.
	meleeParams.FilterDescendantsInstances = { character }
	local range = meleeDef.range
	local box = root.CFrame * CFrame.new(0, 0, -range / 2)
	local parts = Workspace:GetPartBoundsInBox(box, Vector3.new(4, 6, range), meleeParams)
	local bestPart: BasePart? = nil
	local bestDistance = math.huge
	for _, part in parts do
		local target = characterOf(part)
		if target and target ~= character and target:GetAttribute("Dead") ~= true then
			local distance = (part.Position - root.Position).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				bestPart = part
			end
		end
	end
	ClientNet.fire("MeleeAttack", bestPart)
end

-- Boucle de tir (chaque image).
local function update()
	local state = rangedState
	if state and rangedDef then
		local now = serverNow()
		-- Fin de recharge prédite localement (le serveur confirmera).
		if state.reloadEndsAt ~= nil and now >= state.reloadEndsAt then
			local used = WeaponLogic.finishReload(rangedDef, state, now, reserve)
			reserve -= used
		end
		WeaponLogic.updateHeat(state, now)
	end

	if not alive() or stunned() or PanelState.anyOpen() then
		return
	end
	local character = player.Character
	if character and character:GetAttribute("Using") == true then
		return
	end
	local wantsFire = InputController.isHeld("fire") or triggerPending
	if not wantsFire or parrying then
		return
	end
	if MovementController.isSprinting() then
		MovementController.stopSprint()
		fireReadyAt = os.clock() + Combat.movement.sprintToFireDelay
		return
	end
	if os.clock() < fireReadyAt then
		return
	end
	if activeSlot == "ranged" and rangedDef then
		if rangedDef.fireMode == "auto" or triggerPending then
			fireRanged()
		end
	elseif activeSlot == "melee" and meleeDef then
		attackMelee()
	end
end

function WeaponController.reload()
	local state = rangedState
	if state == nil or rangedDef == nil or activeSlot ~= "ranged" or not alive() then
		return
	end
	if WeaponLogic.canReload(rangedDef, state, reserve) then
		WeaponLogic.startReload(rangedDef, state, serverNow())
		ClientNet.fire("ReloadWeapon")
	end
end

function WeaponController.switchTo(slot: "ranged" | "melee")
	if slot == activeSlot or not alive() then
		return
	end
	if (slot == "ranged" and rangedDef == nil) or (slot == "melee" and meleeDef == nil) then
		return
	end
	activeSlot = slot
	if rangedState then
		WeaponLogic.cancelReload(rangedState)
	end
	ClientNet.fire("SwitchWeapon", slot)
end

local function setParry(active: boolean)
	if active == parrying then
		return
	end
	if active and (meleeDef == nil or not alive() or stunned()) then
		return
	end
	parrying = active
	if active then
		MovementController.stopSprint()
		activeSlot = "melee" -- le serveur passe aussi sur l'arme de mêlée
	end
	ClientNet.fire("SetParry", active)
end

function WeaponController.snapshot(): Snapshot
	local state = rangedState
	local now = serverNow()
	local reloadProgress: number? = nil
	if state and state.reloadEndsAt and rangedDef and rangedDef.reloadTime then
		local total = rangedDef.reloadTime
		reloadProgress = math.clamp(1 - (state.reloadEndsAt - now) / total, 0, 1)
	end
	return {
		activeSlot = activeSlot,
		rangedId = rangedId,
		rangedCondition = rangedCondition,
		ammo = if state then state.ammo else 0,
		capacity = if rangedDef then rangedDef.capacity else nil,
		reserve = reserve,
		heat = if state then state.heat else 0,
		overheated = state ~= nil and now < state.overheatedUntil,
		reloadProgress = reloadProgress,
		meleeId = meleeId,
		meleeCondition = meleeCondition,
		parrying = parrying,
		spread = currentSpread(),
		usingItemId = if using and now < using.endsAt then using.itemId else nil,
		usingProgress = if using and now < using.endsAt
			then math.clamp((now - using.startedAt) / math.max(0.01, using.endsAt - using.startedAt), 0, 1)
			else nil,
		boostRemaining = if boostUntil > now then boostUntil - now else nil,
	}
end

function WeaponController.init() end

function WeaponController.start()
	ClientNet.on("CombatState", onCombatState)

	InputController.ActionBegan:Connect(function(action)
		if action == "fire" then
			triggerPending = true
		elseif action == "switch" then
			WeaponController.switchTo(if activeSlot == "ranged" then "melee" else "ranged")
		elseif action == "weapon1" then
			WeaponController.switchTo("ranged")
		elseif action == "weapon2" then
			WeaponController.switchTo("melee")
		elseif action == "parry" then
			setParry(true)
		elseif action == "aim" then
			if InputController.device() == "touch" then
				CameraController.setAiming(not CameraController.isAiming())
			else
				CameraController.setAiming(true)
			end
		end
	end)

	-- Recharge sur appui court : à la manette, X maintenu sert à interagir (5.3).
	InputController.Tapped:Connect(function(action)
		if action == "reload" then
			WeaponController.reload()
		end
	end)

	InputController.ActionEnded:Connect(function(action)
		if action == "parry" then
			setParry(false)
		elseif action == "aim" and InputController.device() ~= "touch" then
			CameraController.setAiming(false)
		end
	end)

	player.CharacterAdded:Connect(function()
		parrying = false
		triggerPending = false
		lastMeleeAt = -math.huge
		CameraController.setAiming(false)
	end)

	RunService.RenderStepped:Connect(update)
end

return WeaponController
