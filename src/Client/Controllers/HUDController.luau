--!strict
--[[
	HUDController : affichage en jeu (section 17.3, écrans 11 et 13 — version P1).

	- En bas à gauche : bouclier (cyan) et PV, posture.
	- En bas à droite : arme active (nom, état en pastilles), munitions,
	  cellules restantes, recharge, jauge de surchauffe.
	- Au centre : réticule dynamique, marqueur de touche (blanc ; rouge pour
	  la tête), indicateurs de garde / étourdissement / parade.
	- Indicateurs de direction des dégâts reçus.
	- Écran de mort (désintégration).

	L'état d'un objet n'est jamais indiqué par la couleur seule (pastilles + nom).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemRules = require(Shared.Items.ItemRules)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
local Theme = require(script.Parent.Parent.UI.Theme)
local ProfileController = require(script.Parent.ProfileController)
local MovementController = require(script.Parent.MovementController)
local WeaponController = require(script.Parent.WeaponController)

local HUDController = {}

local player = Players.LocalPlayer
local t = ProfileController.t

local gui: ScreenGui
local healthFill: Frame
local healthText: TextLabel
local shieldContainer: Frame
local shieldFill: Frame
local shieldText: TextLabel
local stanceLabel: TextLabel
local weaponName: TextLabel
local conditionPips: { Frame } = {}
local ammoLabel: TextLabel
local statusLabel: TextLabel
local reloadBar: Frame
local heatBar: Frame
local heatFill: Frame
local crosshair: Frame
local crosshairLines: { Frame } = {}
local hitmarker: Frame
local centerLabel: TextLabel
local damageArcs: Frame
local deathOverlay: Frame
local deathTitle: TextLabel
local deathSubtitle: TextLabel

local function bar(name: string, color: Color3, order: number): (Frame, Frame, TextLabel)
	local container = Create("Frame", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = Theme.panelTransparency,
		BorderSizePixel = 0,
	}, {
		Fill = Create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
		}),
		Value = Create("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Theme.fontNumbers,
			TextSize = 13,
			TextColor3 = Color3.new(0, 0, 0),
			TextStrokeTransparency = 1,
			Text = "",
			ZIndex = 2,
		}),
	})
	return container, container:FindFirstChild("Fill") :: Frame, container:FindFirstChild("Value") :: TextLabel
end

local function buildBottomLeft(parent: Instance)
	local shieldFrame, shieldFillFrame, shieldValue = bar("Shield", Theme.shield, 1)
	shieldContainer = shieldFrame
	local healthContainer, healthFillFrame, healthValue = bar("Health", Theme.health, 2)
	shieldFill, shieldText = shieldFillFrame, shieldValue
	healthFill, healthText = healthFillFrame, healthValue
	stanceLabel = Create("TextLabel", {
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Font = Theme.fontText,
		TextSize = 13,
		TextColor3 = Theme.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
	Create("Frame", {
		Name = "Vitals",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(240, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = parent,
	}, {
		Layout = Create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
		}),
		Shield = shieldFrame,
		Health = healthContainer,
		Stance = stanceLabel,
	})
end

local function buildBottomRight(parent: Instance)
	local pips = Create("Frame", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundTransparency = 1,
	}, {
		Layout = Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 4),
		}),
	})
	for index = 1, Config.Conditions.MAX do
		local pip = Create("Frame", {
			LayoutOrder = index,
			Size = UDim2.fromOffset(8, 8),
			BorderSizePixel = 0,
			Parent = pips,
		}, {
			Corner = Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		})
		table.insert(conditionPips, pip)
	end

	weaponName = Create("TextLabel", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Font = Theme.fontTitle,
		TextSize = 16,
		TextColor3 = Theme.text,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
	})
	ammoLabel = Create("TextLabel", {
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		Font = Theme.fontNumbers,
		TextSize = 30,
		TextColor3 = Theme.text,
		TextXAlignment = Enum.TextXAlignment.Right,
		RichText = true,
		Text = "",
	})
	statusLabel = Create("TextLabel", {
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Font = Theme.fontText,
		TextSize = 13,
		TextColor3 = Theme.orange,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
	})
	local reloadContainer = Create("Frame", {
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = Theme.panel,
		BorderSizePixel = 0,
		Visible = false,
	}, {
		Fill = Create("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.cyan, BorderSizePixel = 0 }),
	})
	reloadBar = reloadContainer
	heatBar = Create("Frame", {
		LayoutOrder = 6,
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = Theme.panel,
		BorderSizePixel = 0,
		Visible = false,
	}, {
		Fill = Create("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.orange, BorderSizePixel = 0 }),
	})
	heatFill = heatBar:FindFirstChild("Fill") :: Frame

	Create("Frame", {
		Name = "Weapon",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(260, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = parent,
	}, {
		Layout = Create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 3),
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
		}),
		WeaponName = weaponName,
		Pips = pips,
		Ammo = ammoLabel,
		Status = statusLabel,
		Reload = reloadContainer,
		Heat = heatBar,
	})
end

local function buildCenter(parent: Instance)
	crosshair = Create("Frame", {
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		Parent = parent,
	}, {
		Dot = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(3, 3),
			BackgroundColor3 = Theme.text,
			BorderSizePixel = 0,
		}),
	})
	for index = 1, 4 do
		local horizontal = index <= 2
		table.insert(
			crosshairLines,
			Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = if horizontal then UDim2.fromOffset(8, 2) else UDim2.fromOffset(2, 8),
				BackgroundColor3 = Theme.text,
				BorderSizePixel = 0,
				Parent = crosshair,
			})
		)
	end

	hitmarker = Create("Frame", {
		Name = "Hitmarker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(26, 26),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	})
	for index = 1, 4 do
		local angle = 45 + 90 * index
		Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(math.rad(angle)) * 9, 0.5, math.sin(math.rad(angle)) * 9),
			Size = UDim2.fromOffset(8, 2),
			Rotation = angle,
			BackgroundColor3 = Theme.text,
			BorderSizePixel = 0,
			Parent = hitmarker,
		})
	end

	centerLabel = Create("TextLabel", {
		Name = "CenterStatus",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 40),
		Size = UDim2.fromOffset(300, 24),
		BackgroundTransparency = 1,
		Font = Theme.fontTitle,
		TextSize = 18,
		TextColor3 = Theme.cyan,
		TextStrokeTransparency = 0.5,
		Text = "",
		Parent = parent,
	})

	damageArcs = Create("Frame", {
		Name = "DamageArcs",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		Parent = parent,
	})
end

local function buildDeathOverlay(parent: Instance)
	deathTitle = Create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundTransparency = 1,
		Font = Theme.fontTitle,
		TextSize = 48,
		TextColor3 = Theme.red,
		Text = "",
	})
	deathSubtitle = Create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Font = Theme.fontText,
		TextSize = 18,
		TextColor3 = Theme.textDim,
		Text = "",
	})
	deathOverlay = Create("Frame", {
		Name = "Death",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		Visible = false,
		ZIndex = 10,
		Parent = parent,
	}, {
		Title = deathTitle,
		Subtitle = deathSubtitle,
	})
end

-- Marqueur de touche : blanc, rouge pour la tête, plus grand pour un kill.
local function showHitmarker(isHead: boolean, killed: boolean)
	local color = if isHead or killed then Theme.red else Theme.text
	for _, line in hitmarker:GetChildren() do
		if line:IsA("Frame") then
			line.BackgroundColor3 = color
		end
	end
	hitmarker.Size = if killed then UDim2.fromOffset(38, 38) else UDim2.fromOffset(26, 26)
	hitmarker.Visible = true
	local stamp = os.clock()
	hitmarker:SetAttribute("Stamp", stamp)
	task.delay(0.18, function()
		if hitmarker:GetAttribute("Stamp") == stamp then
			hitmarker.Visible = false
		end
	end)
end

-- Arc rouge orienté vers la source des dégâts (s'efface en 1 s).
local function showDamageDirection(source: Vector3)
	local camera = Workspace.CurrentCamera
	local look = camera.CFrame.LookVector
	local toSource = source - camera.CFrame.Position
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local flatSource = Vector3.new(toSource.X, 0, toSource.Z)
	if flatLook.Magnitude < 1e-3 or flatSource.Magnitude < 1e-3 then
		return
	end
	flatLook, flatSource = flatLook.Unit, flatSource.Unit
	local angle = math.atan2(flatLook:Cross(flatSource).Y, flatLook:Dot(flatSource))
	local radius = 90
	local arc = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(math.sin(-angle) * radius, -math.cos(angle) * radius),
		Size = UDim2.fromOffset(48, 5),
		Rotation = math.deg(-angle),
		BackgroundColor3 = Theme.red,
		BorderSizePixel = 0,
		Parent = damageArcs,
	})
	TweenService:Create(arc, TweenInfo.new(1), { BackgroundTransparency = 1 }):Play()
	task.delay(1.05, function()
		arc:Destroy()
	end)
end

local flashMessage: string? = nil
local flashUntil = 0

local function flashCenter(key: string)
	flashMessage = key
	flashUntil = os.clock() + 0.8
end

local function render()
	local character = player.Character
	if character == nil then
		return
	end
	local health = character:GetAttribute("Health")
	local shield = character:GetAttribute("Shield")
	local maxShield = character:GetAttribute("MaxShield")
	local maxHealth = Config.Combat.maxHealth
	if type(health) == "number" then
		healthFill.Size = UDim2.fromScale(math.clamp(health / maxHealth, 0, 1), 1)
		healthFill.BackgroundColor3 = if health <= maxHealth * 0.3 then Theme.healthLow else Theme.health
		healthText.Text = tostring(math.ceil(health))
	end
	if type(shield) == "number" and type(maxShield) == "number" then
		shieldContainer.Visible = maxShield > 0
		shieldFill.Size = UDim2.fromScale(if maxShield > 0 then math.clamp(shield / maxShield, 0, 1) else 0, 1)
		shieldText.Text = tostring(math.ceil(shield))
	end

	local stance = MovementController.stance()
	stanceLabel.Text = if stance == "crouch"
		then t("hud.stance.crouch")
		elseif stance == "prone" then t("hud.stance.prone")
		else ""

	local snap = WeaponController.snapshot()
	local isRanged = snap.activeSlot == "ranged"
	local itemId = if isRanged then snap.rangedId else snap.meleeId
	local condition = if isRanged then snap.rangedCondition else snap.meleeCondition
	weaponName.Text = if itemId then t("item." .. itemId) else ""
	for index, pip in conditionPips do
		pip.BackgroundColor3 = if condition and index <= condition then Theme.conditionColor(condition) else Theme.panel
		pip.Visible = itemId ~= nil
	end

	local status = ""
	if isRanged and snap.rangedId then
		-- Type de munitions de l'arme (la réserve se compte dans ces cellules).
		local ammo = ItemRules.ammoOf(snap.rangedId)
		local cell = if ammo then `<font size="13" color="#969EAA">  {t("item." .. ammo)}</font>` else ""
		if snap.capacity then
			local ammoColor = if snap.ammo == 0 then "#FF3B3B" else "#EBF0F5"
			ammoLabel.Text =
				`<font color="{ammoColor}">{snap.ammo}</font><font size="18" color="#969EAA"> / {snap.reserve}</font>{cell}`
		else
			ammoLabel.Text = `<font size="18" color="#969EAA">{snap.reserve}</font>{cell}`
		end
		reloadBar.Visible = snap.reloadProgress ~= nil
		if snap.reloadProgress then
			(reloadBar:FindFirstChild("Fill") :: Frame).Size = UDim2.fromScale(snap.reloadProgress, 1)
			status = t("hud.reloading")
		end
		heatBar.Visible = snap.capacity == nil
		heatFill.Size = UDim2.fromScale(math.clamp(snap.heat / Config.Combat.overheat.max, 0, 1), 1)
		heatFill.BackgroundColor3 = if snap.overheated then Theme.red else Theme.orange
		if snap.overheated then
			status = t("hud.overheated")
		elseif snap.reserve == 0 and (snap.capacity == nil or snap.ammo == 0) then
			status = t("hud.noCells")
		end
	else
		ammoLabel.Text = ""
		reloadBar.Visible = false
		heatBar.Visible = false
	end
	statusLabel.Text = status

	-- Réticule dynamique : écartement selon la dispersion.
	local camera = Workspace.CurrentCamera
	local pixelsPerDegree = camera.ViewportSize.Y / camera.FieldOfView
	local gap = 4 + snap.spread * pixelsPerDegree
	crosshair.Visible = isRanged
	crosshairLines[1].Position = UDim2.fromOffset(-gap - 4, 0)
	crosshairLines[2].Position = UDim2.fromOffset(gap + 4, 0)
	crosshairLines[3].Position = UDim2.fromOffset(0, -gap - 4)
	crosshairLines[4].Position = UDim2.fromOffset(0, gap + 4)

	-- Statut central : message flash, sinon garde / étourdissement.
	if flashMessage and os.clock() < flashUntil then
		centerLabel.Text = t(flashMessage)
		centerLabel.TextColor3 = if flashMessage == "hud.parryBroken" then Theme.red else Theme.cyan
	elseif character:GetAttribute("Stunned") == true then
		centerLabel.Text = t("hud.stunned")
		centerLabel.TextColor3 = Theme.orange
	elseif snap.parrying then
		centerLabel.Text = t("hud.parry")
		centerLabel.TextColor3 = Theme.cyan
	else
		centerLabel.Text = ""
	end

	-- Écran de mort.
	local dead = character:GetAttribute("Dead") == true
	deathOverlay.Visible = dead
	if dead then
		deathTitle.Text = t("hud.dead")
		-- En partie, pas de réapparition (orbe en duo, écran de fin en solo).
		local state = ReplicatedStorage:FindFirstChild("MatchState")
		local inMatch = state ~= nil and state:GetAttribute("Running") == true
		deathSubtitle.Text = if inMatch then "" else t("hud.respawning")
	end
end

function HUDController.init() end

function HUDController.start()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	gui = Create("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	buildBottomLeft(gui)
	buildBottomRight(gui)
	buildCenter(gui)
	buildDeathOverlay(gui)
	gui.Parent = player:WaitForChild("PlayerGui")

	ClientNet.on("HitConfirm", function(isHead: boolean, killed: boolean)
		showHitmarker(isHead == true, killed == true)
	end)
	ClientNet.on("DamageTaken", function(source: Vector3)
		if typeof(source) == "Vector3" then
			showDamageDirection(source)
		end
	end)
	ClientNet.on("ParryResult", function(result: string)
		if result == "perfect" then
			flashCenter("hud.parryPerfect")
		elseif result == "broken" then
			flashCenter("hud.parryBroken")
		elseif result == "parried" then
			flashCenter("hud.parried")
		end
	end)

	RunService.RenderStepped:Connect(render)
end

-- Conteneur racine (les boutons tactiles s'y ajoutent).
function HUDController.root(): ScreenGui
	return gui
end

return HUDController
