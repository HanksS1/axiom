--!strict
--[[
	ItemCard : carte d'objet (section 17.3, écran 4).

	Vignette 3D de l'objet, nom, état (pastilles + nom : jamais la couleur
	seule), quantité, valeur, et une rangée de boutons d'action. Les actions
	marquées `hold` se déclenchent après un maintien (ramassage : 0,3 s), au
	doigt, à la souris comme à la manette.

	- Encombrement : badge « n UP » à gauche des actions, toujours au même
	  endroit (on compare deux objets d'un regard, d'une carte à l'autre).
	- Armes : action « Détails » (fiche WeaponDetail), ajoutée d'office comme
	  les autres actions ; la vignette elle-même ouvre aussi la fiche.
	- `options.blocked` : l'objet ne peut pas être pris (« il manque 3 UP ») :
	  carte estompée, cadre et raison en rouge (même rouge que la jauge pleine).
	  `options.warning` : une seule action est impossible (les autres restent
	  valables) : raison en rouge, carte normale. C'est une aide : le serveur
	  refuse et explique de toute façon.
	- Panneau étroit (téléphone) : la vignette s'efface et les actions passent
	  sur une seconde ligne, sous le texte (rien n'est masqué).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local ItemRules = require(Shared.Items.ItemRules)
local Types = require(Shared.Types)

local Create = require(script.Parent.Create)
local ItemIcon = require(script.Parent.ItemIcon)
local Theme = require(script.Parent.Theme)
local WeaponDetail = require(script.Parent.WeaponDetail)

local TweenService = game:GetService("TweenService")

export type Action = {
	label: string, -- texte déjà traduit
	color: Color3?,
	hold: number?, -- durée de maintien (secondes), sinon clic simple
	-- Action impossible pour l'instant (la raison est écrite sur la carte) :
	-- bouton estompé, sans effet.
	disabled: boolean?,
	callback: () -> (),
}

export type Options = {
	blocked: string?, -- raison déjà traduite : l'objet ne peut pas être pris
	warning: string?, -- raison déjà traduite : une action (grisée) est impossible
	details: boolean?, -- false : pas d'action « Détails » (aperçu déjà ouvert…)
}

export type Translate = (key: string, params: { [string]: any }?) -> string

local ItemCard = {}

local CARD_HEIGHT = 64
local ICON_SIZE = 52
local TEXT_X = 12 -- sans vignette
local ICON_TEXT_X = 70 -- avec vignette
local NARROW = 380 -- en dessous, la carte n'affiche plus la vignette
local MARGIN = 8
local ACTION_MIN_WIDTH = 64 -- boutons d'action : largeur du texte, au moins celle-ci
local ACTION_PADDING = 10
local BADGE_WIDTH = 50 -- badge d'encombrement « n UP »
local GAP = 6
local BLOCKED_TRANSPARENCY = 0.55 -- carte d'un objet qui ne rentre pas

local function actionButton(action: Action, order: number, holdHint: string): TextButton
	local color = if action.disabled then Theme.textDim else action.color or Theme.cyan
	local button = Create("TextButton", {
		LayoutOrder = order,
		Size = UDim2.fromOffset(0, Theme.minButtonSize),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = if action.disabled then 0.6 else 0.1,
		AutoButtonColor = not action.disabled,
		Font = Theme.fontText,
		TextSize = 14,
		TextColor3 = color,
		TextTransparency = if action.disabled then 0.35 else 0,
		Text = action.label,
	}, {
		Stroke = Create("UIStroke", { Color = color, Transparency = 0.5 }),
		MinWidth = Create("UISizeConstraint", { MinSize = Vector2.new(ACTION_MIN_WIDTH, 0) }),
		Padding = Create("UIPadding", {
			PaddingLeft = UDim.new(0, ACTION_PADDING),
			PaddingRight = UDim.new(0, ACTION_PADDING),
		}),
		Fill = Create("Frame", {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.6,
			BorderSizePixel = 0,
			ZIndex = 0,
		}),
	})
	if action.disabled then
		return button -- raison écrite sur la carte ; le serveur refuserait de toute façon
	end
	local hold = action.hold
	if hold == nil or hold <= 0 then
		button.Activated:Connect(action.callback)
		return button
	end
	-- Maintien : barre de progression, relâcher annule.
	local fill = button:FindFirstChild("Fill") :: Frame
	local holding = false
	local token = 0
	local function stop()
		holding = false
		token += 1
		fill.Size = UDim2.fromScale(0, 1)
	end
	-- Relâché avant la fin (simple clic) : le bouton rappelle qu'il faut maintenir.
	local flash = 0
	local function release()
		if holding then
			flash += 1
			local mine = flash
			button.Text = holdHint
			task.delay(1, function()
				if flash == mine and button.Parent ~= nil then
					button.Text = action.label
				end
			end)
		end
		stop()
	end
	local function start()
		if holding then
			return
		end
		holding = true
		token += 1
		local myToken = token
		local started = os.clock()
		local connection: RBXScriptConnection
		connection = RunService.RenderStepped:Connect(function()
			if token ~= myToken then
				connection:Disconnect()
				return
			end
			local progress = math.clamp((os.clock() - started) / hold, 0, 1)
			fill.Size = UDim2.fromScale(progress, 1)
			if progress >= 1 then
				connection:Disconnect()
				stop()
				action.callback()
			end
		end)
	end
	button.MouseButton1Down:Connect(start)
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(stop)
	button.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.ButtonA then
			start()
		end
	end)
	button.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.ButtonA then
			release()
		end
	end)
	return button
end

-- Titre d'un objet : nom traduit + quantité éventuelle + mention « Kit ».
function ItemCard.title(item: Types.ItemInstance, t: Translate): string
	local name = t("item." .. item.itemId)
	if item.stack and item.stack > 1 then
		name ..= ` ×{item.stack}`
	end
	if item.isKit then
		name ..= ` [{t("item.tag.kit")}]`
	end
	return name
end

-- Ouvre la fiche de l'arme (sans effet pour un autre objet).
function ItemCard.openDetail(item: Types.ItemInstance, t: Translate)
	if WeaponDetail.has(item.itemId) then
		WeaponDetail.open(t, item.itemId, item.condition)
	end
end

function ItemCard.create(
	item: Types.ItemInstance,
	t: Translate,
	actions: { Action },
	order: number?,
	options: Options?
): Frame
	local opts: Options = options or {}
	local info = ItemCatalog.get(item.itemId)
	local condition = item.condition
	local conditionDef = if condition then Config.Conditions.list[condition] else nil
	local accent = if conditionDef then conditionDef.color else Theme.textDim
	local blocked = opts.blocked
	-- Raison écrite sur la carte (refus complet, ou action grisée).
	local reason = blocked or opts.warning
	local hasDetail = opts.details ~= false and WeaponDetail.has(item.itemId)

	local pips = Create("Frame", {
		Size = UDim2.fromOffset(70, 10),
		Position = UDim2.fromOffset(12, 30),
		BackgroundTransparency = 1,
	}, {
		Layout = Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3) }),
	})
	if condition then
		for index = 1, Config.Conditions.MAX do
			Create("Frame", {
				LayoutOrder = index,
				Size = UDim2.fromOffset(9, 9),
				BackgroundColor3 = if index <= condition then accent else Theme.panel,
				BorderSizePixel = 0,
				Parent = pips,
			}, { Corner = Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		end
	end

	local details = {}
	if conditionDef then
		table.insert(details, t("condition." .. conditionDef.key))
	end
	local value = ItemRules.value(item)
	if value > 0 then
		table.insert(details, t("inventory.value", { value = value }))
	end
	-- Module de calibration : son usage (sinon le joueur ne sait pas quoi en faire).
	if info and info.category == "calibration" then
		table.insert(details, 1, t("inventory.calibrationUse"))
	end
	-- Munitions : la cellule d'une arme, ou les armes qui utilisent une cellule.
	local ammo = ItemRules.ammoOf(item.itemId)
	if ammo then
		table.insert(details, 1, t("inventory.ammo", { cell = t("item." .. ammo) }))
	elseif info and info.category == "cell" then
		local names = {}
		for _, weaponId in ItemRules.weaponsUsing(item.itemId) do
			table.insert(names, t("item." .. weaponId))
		end
		if #names > 0 then
			table.insert(details, 1, t("inventory.ammoFor", { weapons = table.concat(names, ", ") }))
		end
	end

	local actionRow = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -MARGIN, 0.5, 0),
		Size = UDim2.fromOffset(0, Theme.minButtonSize),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
	}, {
		Layout = Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})
	local holdHint = t("hint.hold")
	for index, action in actions do
		actionButton(action, index, holdHint).Parent = actionRow
	end
	if hasDetail then
		actionButton({
			label = t("item.action.details"),
			callback = function()
				ItemCard.openDetail(item, t)
			end,
		}, #actions + 1, holdHint).Parent =
			actionRow
	end

	-- Encombrement : badge à part, aligné d'une carte à l'autre.
	local upBadge = Create("TextLabel", {
		Name = "Up",
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(BADGE_WIDTH, 24),
		BackgroundColor3 = Theme.background,
		BackgroundTransparency = 0.2,
		Font = Theme.fontNumbers,
		TextSize = 14,
		TextColor3 = if reason then Theme.red else Theme.text,
		Text = t("inventory.up", { up = if info then info.up else 0 }),
	}, {
		Corner = Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
		Stroke = Create("UIStroke", { Color = if reason then Theme.red else Theme.textDim, Transparency = 0.4 }),
	})

	local icon = ItemIcon.create(item.itemId, UDim2.fromOffset(ICON_SIZE, ICON_SIZE), condition)
	icon.Position = UDim2.fromOffset(10, (CARD_HEIGHT - ICON_SIZE) / 2)
	if hasDetail then
		-- La vignette est le geste naturel : un clic ouvre la fiche (les boutons
		-- d'action restent le chemin de la manette, la vignette n'est pas une étape).
		local hit = Create("TextButton", {
			Name = "OpenDetail",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Selectable = false,
			Text = "",
			ZIndex = 3,
			Parent = icon,
		})
		hit.Activated:Connect(function()
			ItemCard.openDetail(item, t)
		end)
	end
	local nameLabel = Create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.fontText,
		TextSize = 16,
		TextColor3 = if blocked then Theme.textDim else Theme.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = ItemCard.title(item, t),
	})
	local detailText = table.concat(details, "  ·  ")
	local detailLabel = Create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.fontNumbers,
		TextSize = 13,
		TextColor3 = Theme.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		RichText = reason ~= nil,
		Text = if reason
			then `<font color="#FF3B3B">{reason}</font>` .. (if detailText ~= "" then "  ·  " .. detailText else "")
			else detailText,
	})
	local card = Create("Frame", {
		Name = item.uid,
		LayoutOrder = order or 0,
		Size = UDim2.new(1, 0, 0, CARD_HEIGHT),
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = if blocked then BLOCKED_TRANSPARENCY else Theme.panelTransparency,
		BorderSizePixel = 0,
	}, {
		Edge = Create("Frame", {
			Size = UDim2.new(0, 4, 1, 0),
			BackgroundColor3 = if blocked then Theme.red else accent,
			BorderSizePixel = 0,
		}),
		Stroke = Create("UIStroke", {
			Color = if blocked then Theme.red else accent,
			Transparency = if blocked then 0.3 else 0.6,
		}),
		Icon = icon,
		Name_ = nameLabel,
		Pips = pips,
		Details = detailLabel,
		Up = upBadge,
		Actions = actionRow,
	})

	--[[
		Mise en page : la place des actions est mesurée (plus de largeur fixe).
		Large : vignette, texte, badge UP et actions sur une ligne. Étroit :
		texte et badge en haut, actions sur une seconde ligne.
	]]
	local function layout()
		local width = card.AbsoluteSize.X
		local narrow = width > 0 and width < NARROW
		local x = if narrow then TEXT_X else ICON_TEXT_X
		icon.Visible = not narrow
		local actionsWidth = actionRow.AbsoluteSize.X
		local right = if narrow then MARGIN else MARGIN + actionsWidth + GAP
		card.Size = UDim2.new(1, 0, 0, if narrow then CARD_HEIGHT + Theme.minButtonSize + GAP else CARD_HEIGHT)
		actionRow.AnchorPoint = if narrow then Vector2.new(1, 1) else Vector2.new(1, 0.5)
		actionRow.Position = if narrow then UDim2.new(1, -MARGIN, 1, -GAP) else UDim2.new(1, -MARGIN, 0.5, 0)
		upBadge.Position = if narrow then UDim2.new(1, -MARGIN, 0, CARD_HEIGHT / 2) else UDim2.new(1, -right, 0.5, 0)
		local textRight = right + BADGE_WIDTH + GAP
		nameLabel.Position = UDim2.fromOffset(x, 6)
		nameLabel.Size = UDim2.new(1, -(x + textRight), 0, 20)
		pips.Position = UDim2.fromOffset(x, 30)
		local detailX = if condition then x + 78 else x
		detailLabel.Position = UDim2.fromOffset(detailX, 26)
		detailLabel.Size = UDim2.new(1, -(detailX + textRight), 0, 18)
	end
	layout()
	card:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	actionRow:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	card:SetAttribute("Accent", accent)
	return card
end

--[[
	Apparition d'une carte (ouverture d'une caisse) : les objets se révèlent un
	par un, avec un éclair à la couleur de leur état. `order` : rang dans la liste.
]]
function ItemCard.reveal(card: Frame, order: number)
	card.Visible = false
	task.delay((order - 1) * 0.09, function()
		if card.Parent == nil then
			return
		end
		card.Visible = true
		local accent = card:GetAttribute("Accent")
		local flash = Create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = if typeof(accent) == "Color3" then accent else Theme.cyan,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = card,
		})
		local tween = TweenService:Create(flash, TweenInfo.new(0.3), { BackgroundTransparency = 1 })
		tween.Completed:Once(function()
			flash:Destroy()
		end)
		tween:Play()
	end)
end

return ItemCard
