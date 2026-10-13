--!strict
--[[
	HintController : aides contextuelles (une ligne discrète, au bon moment).

	Le jeu a beaucoup de gestes qui ne se devinent pas (soin, batterie,
	parade, sac plein, extraction…). Plutôt qu'un mode d'emploi, une courte
	ligne rappelle la commande quand elle sert, avec la touche du périphérique
	utilisé. Règles (Config/Hints, Shared/Hints/HintRules) : une seule aide à
	la fois, peu de répétitions, rien pendant un échange de tirs sauf les
	aides urgentes, et plus rien une fois le geste accompli par le joueur.

	La ligne ne capte aucune entrée et ne recouvre ni le réticule, ni la
	barre rapide. Désactivable dans Paramètres → Affichage.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local HintRules = require(Shared.Hints.HintRules)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
local PanelState = require(script.Parent.Parent.UI.PanelState)
local Theme = require(script.Parent.Parent.UI.Theme)
local HUDController = require(script.Parent.HUDController)
local InputController = require(script.Parent.InputController)
local InventoryController = require(script.Parent.InventoryController)
local MatchHUDController = require(script.Parent.MatchHUDController)
local ProfileController = require(script.Parent.ProfileController)
local WeaponController = require(script.Parent.WeaponController)

local H = Config.Hints

local HintController = {}

local player = Players.LocalPlayer
local t = ProfileController.t

local state = HintRules.new()
local frame: Frame
local label: TextLabel
local stroke: UIStroke
local token = 0

local lastCombatAt = -math.huge
local inTutorial = false
local matchStartedAt: number? = nil
local tipsThisMatch = 0
local lastTipAt = -math.huge
local hubSince: number? = nil
local accumulator = 0

local context: HintRules.Context = { enabled = true, blocked = false, calm = true, gap = H.display.gap }

-- Placement : au-dessus de la barre rapide ; au tactile, sous le réticule (les pouces
-- occupent le bas de l'écran).
local function place()
	if InputController.device() == "touch" then
		frame.AnchorPoint = Vector2.new(0.5, 0)
		frame.Position = UDim2.new(0.5, 0, 0.5, 96)
	else
		frame.AnchorPoint = Vector2.new(0.5, 1)
		frame.Position = UDim2.new(0.5, 0, 1, -112)
	end
end

local function fade(visible: boolean)
	local info = TweenInfo.new(H.display.fade)
	TweenService:Create(frame, info, { BackgroundTransparency = if visible then 0.35 else 1 }):Play()
	TweenService:Create(label, info, { TextTransparency = if visible then 0 else 1 }):Play()
	TweenService:Create(stroke, info, { Transparency = if visible then 0.6 else 1 }):Play()
end

-- Valeurs citées dans les textes (jamais écrites en dur dans les traductions).
local PARAMS: { [string]: { [string]: any } } = {
	heal = { amount = Config.Equipment.consumables.nanite_injector.effect.heal },
	battery = { amount = Config.Equipment.consumables.shield_battery.effect.shield },
	extract = { seconds = Config.Match.extraction.holdTime },
}

-- Affiche l'aide `id` si les règles le permettent. `action` : touche à rappeler.
local function try(id: string, action: InputController.Action?): boolean
	local now = os.clock()
	if not HintRules.canShow(state, id, (H.hints :: any)[id], now, context) then
		return false
	end
	HintRules.markShown(state, id, now, H.display.duration)
	local key = if action then InputController.hint(action) else nil
	label.Text = (if key then `[{key}]  ` else "") .. t("hint." .. id, PARAMS[id])
	frame.Visible = true
	fade(true)
	token += 1
	local mine = token
	task.delay(H.display.duration, function()
		if token ~= mine then
			return
		end
		fade(false)
		task.delay(H.display.fade + 0.05, function()
			if token == mine then
				frame.Visible = false
			end
		end)
	end)
	return true
end

local function numberAttribute(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

-- La caméra est-elle au Terminus ? (même repère que l'ambiance du hub)
local function atTerminus(position: Vector3): boolean
	local terminus = Workspace:FindFirstChild("Terminus")
	local structure = if terminus then terminus:FindFirstChild("Structure") else nil
	local platform = if structure then structure:FindFirstChild("Platform") else nil
	return platform ~= nil and platform:IsA("BasePart") and (platform.Position - position).Magnitude <= H.hubRadius
end

-- Conseils de partie, un à la fois, espacés (au calme seulement).
local function matchTip(duo: boolean): boolean
	return try("extract") or try("stance", "crouch") or (duo and try("ping", "ping"))
end

local function poll()
	local now = os.clock()
	local view = ProfileController.get()
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local alive = character ~= nil
		and root ~= nil
		and root:IsA("BasePart")
		and character:GetAttribute("Dead") ~= true
		and numberAttribute(character, "Health") > 0

	context.enabled = view == nil or view.settings.hints ~= false
	context.blocked = PanelState.anyOpen() or inTutorial or not alive
	context.calm = now - lastCombatAt >= H.calmDelay

	local status = MatchHUDController.status()
	local inMatch = status == "alive"
	if inMatch and matchStartedAt == nil then
		matchStartedAt = now
		tipsThisMatch = 0
		lastTipAt = now
	elseif status == "none" then
		matchStartedAt = nil
	end

	if character == nil or not alive then
		hubSince = nil
		return
	end

	-- Gestes accomplis par le joueur : l'aide correspondante devient inutile.
	local snap = WeaponController.snapshot()
	if snap.usingItemId == "nanite_injector" then
		HintRules.learn(state, "heal")
	elseif snap.usingItemId == "shield_battery" then
		HintRules.learn(state, "battery")
	end
	if character:GetAttribute("Parrying") == true then
		HintRules.learn(state, "melee")
	end
	if character:GetAttribute("Stance") == "crouch" or character:GetAttribute("Stance") == "prone" then
		HintRules.learn(state, "stance")
	end

	-- Survie : PV bas avec un injecteur en poche, bouclier bas avec une batterie.
	if
		numberAttribute(character, "Health") <= H.healBelow
		and snap.usingItemId == nil
		and InventoryController.count("nanite_injector") > 0
		and try("heal", "heal")
	then
		return
	end
	local maxShield = numberAttribute(character, "MaxShield")
	if
		maxShield > 0
		and numberAttribute(character, "Shield") / maxShield <= H.batteryBelow
		and snap.usingItemId == nil
		and InventoryController.count("shield_battery") > 0
		and try("battery", "battery")
	then
		return
	end

	-- Arme : plus de cellules (passer à la mêlée), surchauffe.
	if snap.activeSlot == "ranged" and snap.rangedId ~= nil then
		local empty = snap.reserve <= 0 and (snap.capacity == nil or snap.ammo <= 0) and snap.reloadProgress == nil
		local switch: InputController.Action = if InputController.device() == "gamepad" then "switch" else "weapon2"
		if empty and try("noCells", if snap.meleeId then switch else nil) then
			return
		end
		if snap.overheated and try("overheat") then
			return
		end
	elseif snap.activeSlot == "melee" and snap.meleeId ~= nil and try("melee", "parry") then
		return
	end

	if inMatch and matchStartedAt ~= nil then
		local elapsed = now - matchStartedAt
		local inventory = InventoryController.state()
		if inventory.capacity > 0 and inventory.used >= inventory.capacity and try("bagFull", "inventory") then
			return
		end
		if elapsed >= H.objectiveDelay and try("objective") then
			return
		end
		if elapsed >= H.tips.after and tipsThisMatch < H.tips.maxPerMatch and now - lastTipAt >= H.tips.interval then
			local matchState = ReplicatedStorage:FindFirstChild("MatchState")
			local duo = matchState ~= nil and matchState:GetAttribute("Format") == "duo"
			if matchTip(duo) then
				tipsThisMatch += 1
				lastTipAt = now
			end
		end
		return
	end

	-- Terminus : rappel des comptoirs et de la Porte de déploiement.
	if status == "none" and atTerminus((root :: BasePart).Position) then
		hubSince = hubSince or now
		if now - (hubSince :: number) >= H.hubDelay then
			try("hub")
		end
	else
		hubSince = nil
	end
end

function HintController.init() end

function HintController.start()
	label = Create("TextLabel", {
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = Theme.fontText,
		TextSize = 14,
		TextColor3 = Theme.text,
		TextTransparency = 1,
		Text = "",
	})
	stroke = Create("UIStroke", { Color = Theme.cyan, Transparency = 1 })
	frame = Create("Frame", {
		Name = "Hint",
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		Visible = false,
		ZIndex = 2,
		Parent = HUDController.root(),
	}, {
		Padding = Create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
		Corner = Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
		Stroke = stroke,
		Label = label,
	})
	place()
	InputController.DeviceChanged:Connect(place)

	-- « En combat » : un tir, une touche, des dégâts reçus.
	local function combat()
		lastCombatAt = os.clock()
	end
	WeaponController.Fired:Connect(combat)
	ClientNet.on("DamageTaken", combat)
	ClientNet.on("HitConfirm", combat)

	-- Le tutoriel guide déjà le joueur : pas d'aide par-dessus.
	ClientNet.on("TutorialState", function(payload: any)
		inTutorial = type(payload) == "table" and payload.done ~= true
	end)

	InputController.ActionBegan:Connect(function(action)
		if action == "ping" then
			HintRules.learn(state, "ping")
		elseif action == "inventory" then
			HintRules.learn(state, "bagFull")
		end
	end)
	-- Un comptoir ouvert au Terminus : le joueur a compris.
	PanelState.Changed:Connect(function(anyOpen)
		if anyOpen and hubSince ~= nil then
			HintRules.learn(state, "hub")
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= H.pollInterval then
			accumulator = 0
			poll()
		end
	end)
end

return HintController
