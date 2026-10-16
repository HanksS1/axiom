--!strict
--[[
	WeaponDetail : fiche de détail d'une arme (action « Détails » des cartes
	d'objets, ou clic sur leur vignette ; cases de l'inventaire).

	Vignette 3D qui tourne, nom, rareté, état, puis les caractéristiques avec
	une barre comparée aux autres armes de la même catégorie (le rappel est
	écrit EN TÊTE des barres), la place dans le sac (sans barre : moins, c'est
	mieux), l'effet de l'état sur l'efficacité (70 % à 115 %), les
	particularités (tête, lunette, explosion…) et une courte description.
	Les chiffres viennent de Shared/Combat/WeaponStats (calcul pur et testé).
	Petit écran : les deux colonnes s'empilent dans une seule liste défilante.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local WeaponStats = require(Shared.Combat.WeaponStats)

local Create = require(script.Parent.Create)
local ItemIcon = require(script.Parent.ItemIcon)
local Panel = require(script.Parent.Panel)
local Theme = require(script.Parent.Theme)

type Translate = (key: string, params: { [string]: any }?) -> string

local WeaponDetail = {}

local panel: Panel.Panel? = nil

-- En deçà (px de large), la fiche passe sur une colonne.
local NARROW = 600
local ICON_HEIGHT = 200
local ICON_HEIGHT_NARROW = 140
local CHIP_HEIGHT = 40

local function rarityColor(rarity: string): Color3
	return (Config.Monetization.rarityColors :: any)[rarity] or Theme.textDim
end

local function ensurePanel(): Panel.Panel?
	if panel and panel.frame.Parent then
		return panel
	end
	local gui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local root = if gui then gui:FindFirstChild("HUD") else nil
	if root == nil then
		return nil
	end
	local created = Panel.create("WeaponDetail", root, Theme.cyan)
	-- Au-dessus des écrans du Terminus (coffre, Marchand…) d'où on l'ouvre.
	created.frame.ZIndex = 40
	created.frame.Size = UDim2.fromScale(0.7, 0.8)
	panel = created
	return created
end

-- Ligne de caractéristique : libellé, valeur, barre de comparaison.
local function statLine(parent: Instance, t: Translate, line: WeaponStats.Line, order: number, color: Color3)
	local row = Create("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	Create("TextLabel", {
		Size = UDim2.new(0.42, 0, 0, 18),
		BackgroundTransparency = 1,
		Font = Theme.fontText,
		TextSize = 14,
		TextColor3 = Theme.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = t("weapon.stat." .. line.key),
		Parent = row,
	})
	Create("TextLabel", {
		Position = UDim2.fromScale(0.42, 0),
		Size = UDim2.new(0.58, 0, 0, 18),
		BackgroundTransparency = 1,
		Font = Theme.fontNumbers,
		TextSize = 15,
		TextColor3 = Theme.text,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = t(line.text, line.params),
		Parent = row,
	})
	local ratio = line.ratio
	if ratio then
		Create("Frame", {
			Position = UDim2.fromOffset(0, 22),
			Size = UDim2.new(1, 0, 0, 6),
			BackgroundColor3 = Theme.background,
			BorderSizePixel = 0,
			Parent = row,
		}, {
			Fill = Create("Frame", {
				Size = UDim2.fromScale(math.clamp(ratio, 0.03, 1), 1),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
			}),
		})
	end
end

-- Effet de l'état : une pastille par état (efficacité en %), celui de l'arme en avant.
local function conditionStrip(parent: Instance, t: Translate, condition: number?, order: number)
	local title = Panel.label(t("weapon.conditionTitle"), 15, Theme.cyan)
	title.LayoutOrder = order
	title.Font = Theme.fontTitle
	title.Parent = parent
	local row = Create("Frame", {
		LayoutOrder = order + 1,
		Size = UDim2.new(1, -8, 0, CHIP_HEIGHT),
		BackgroundTransparency = 1,
		Parent = parent,
	}, {
		Layout = Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local effects = WeaponStats.conditionEffects(condition)
	for _, effect in effects do
		local def = Config.Conditions.list[effect.index]
		Create("TextLabel", {
			LayoutOrder = effect.index,
			Size = UDim2.new(1 / #effects, -4, 1, 0),
			BackgroundColor3 = if effect.current then def.color else Theme.background,
			BackgroundTransparency = if effect.current then 0.15 else 0.3,
			Font = Theme.fontNumbers,
			TextSize = 13,
			TextColor3 = if effect.current then Theme.background else def.color,
			TextWrapped = true,
			Text = t("weapon.conditionChip", { name = t("condition." .. effect.key), percent = effect.percent }),
			Parent = row,
		}, {
			Corner = Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
			Stroke = Create("UIStroke", { Color = def.color, Transparency = if effect.current then 0 else 0.5 }),
		})
	end
	-- La phrase qui dit l'effet de l'état de CETTE arme.
	local mine = if condition then effects[condition] else nil
	if mine then
		local key = if mine.delta < 0
			then "weapon.conditionWeaker"
			elseif mine.delta > 0 then "weapon.conditionStronger"
			else "weapon.conditionReference"
		local sentence = Panel.label(
			t(key, { name = t("condition." .. mine.key), percent = mine.percent, delta = math.abs(mine.delta) }),
			13,
			Theme.text
		)
		sentence.LayoutOrder = order + 2
		sentence.AutomaticSize = Enum.AutomaticSize.Y
		sentence.Size = UDim2.new(1, -8, 0, 0)
		sentence.Parent = parent
	end
end

--[[
	Ouvre la fiche de `itemId` (une arme), dans l'état `condition` (dégâts
	selon l'état). Sans effet pour un objet qui n'est pas une arme.
]]
function WeaponDetail.open(t: Translate, itemId: string, condition: number?)
	local sheet = WeaponStats.sheet(itemId, condition)
	local current = ensurePanel()
	if sheet == nil or current == nil then
		return
	end
	local color = rarityColor(sheet.rarity)
	current.title.Text = t("item." .. itemId)
	local body = current.body
	Panel.clear(body)
	local narrow = current.frame.AbsoluteSize.X > 0 and current.frame.AbsoluteSize.X < NARROW

	-- Une colonne (petit écran) : tout dans une seule liste défilante.
	local column: Instance? = nil
	if narrow then
		local scroll = Panel.list("Detail")
		scroll.Size = UDim2.fromScale(1, 1)
		scroll.Parent = body
		column = scroll
	end

	-- Gauche (ou haut) : l'arme, sa rareté, son état et sa description.
	local left = Create("Frame", {
		LayoutOrder = 1,
		Size = if narrow then UDim2.new(1, -8, 0, 0) else UDim2.new(0.42, -10, 1, 0),
		AutomaticSize = if narrow then Enum.AutomaticSize.Y else Enum.AutomaticSize.None,
		BackgroundTransparency = 1,
		Parent = column or body,
	}, {
		Layout = Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local icon = ItemIcon.create(
		itemId,
		UDim2.new(1, 0, 0, if narrow then ICON_HEIGHT_NARROW else ICON_HEIGHT),
		condition,
		nil,
		true
	)
	icon.LayoutOrder = 1
	icon.Parent = left
	local stroke = icon:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Thickness = 2
		stroke.Transparency = 0
	end
	local conditionDef = if condition then Config.Conditions.list[condition] else nil
	local rarityText = t("rarity." .. sheet.rarity)
		.. (if conditionDef then "  ·  " .. t("condition." .. conditionDef.key) else "")
		.. "  ·  "
		.. t("weapon.category." .. sheet.category)
	local rarityLabel = Panel.label(rarityText, 16, color)
	rarityLabel.LayoutOrder = 2
	rarityLabel.Font = Theme.fontTitle
	rarityLabel.Parent = left
	local description = Panel.label(t("item." .. itemId .. ".desc"), 14, Theme.text)
	description.LayoutOrder = 3
	description.TextWrapped = true
	description.AutomaticSize = Enum.AutomaticSize.Y
	description.Size = UDim2.new(1, 0, 0, 0)
	description.Parent = left

	-- Droite (ou bas) : caractéristiques, effet de l'état, particularités.
	local right: GuiObject
	if narrow then
		right = Create("Frame", {
			LayoutOrder = 2,
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = column,
		}, {
			Layout = Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
	else
		local list = Panel.list("Stats")
		list.Position = UDim2.new(0.42, 10, 0, 0)
		list.Size = UDim2.new(0.58, -10, 1, 0)
		list.Parent = body
		right = list
	end
	-- À quoi se comparent les barres : dit avant les barres, pas en note de bas de page.
	local compare = Panel.label(t("weapon.compare." .. sheet.category), 13, Theme.textDim)
	compare.LayoutOrder = 0
	compare.AutomaticSize = Enum.AutomaticSize.Y
	compare.Size = UDim2.new(1, -8, 0, 0)
	compare.Parent = right
	for index, line in sheet.lines do
		statLine(right, t, line, index, color)
	end
	conditionStrip(right, t, condition, 60)
	if #sheet.traits > 0 then
		local title = Panel.label(t("weapon.traits"), 15, Theme.cyan)
		title.LayoutOrder = 100
		title.Font = Theme.fontTitle
		title.Parent = right
		for index, trait in sheet.traits do
			local label = Panel.label("•  " .. t("weapon.trait." .. trait), 14, Theme.text)
			label.LayoutOrder = 100 + index
			label.TextWrapped = true
			label.AutomaticSize = Enum.AutomaticSize.Y
			label.Size = UDim2.new(1, -8, 0, 0)
			label.Parent = right
		end
	end
	local note = Panel.label(t("weapon.note"), 12, Theme.textDim)
	note.LayoutOrder = 200
	note.TextWrapped = true
	note.AutomaticSize = Enum.AutomaticSize.Y
	note.Size = UDim2.new(1, -8, 0, 0)
	note.Parent = right

	current:open()
end

-- L'objet a-t-il une fiche (arme à distance ou de mêlée) ?
function WeaponDetail.has(itemId: string): boolean
	return Config.Weapons.ranged[itemId] ~= nil or Config.Weapons.melee[itemId] ~= nil
end

return WeaponDetail
