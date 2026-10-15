--!strict
--[[
	WeaponDetail : fiche de détail d'une arme (bouton « i » des cartes d'objets).

	Vignette 3D qui tourne, nom, rareté, état, puis les caractéristiques avec
	une barre comparée aux autres armes de la même catégorie (dégâts, dégâts
	par seconde, cadence, chargeur, précision, portée, munitions), les
	particularités (tête, lunette, explosion…) et une courte description.
	Les chiffres viennent de Shared/Combat/WeaponStats (calcul pur et testé).
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

	-- Gauche : l'arme, sa rareté, son état et sa description.
	local left = Create("Frame", {
		Size = UDim2.new(0.42, -10, 1, 0),
		BackgroundTransparency = 1,
		Parent = body,
	}, {
		Layout = Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local icon = ItemIcon.create(itemId, UDim2.new(1, 0, 0, 200), condition, nil, true)
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

	-- Droite : caractéristiques et particularités.
	local right = Panel.list("Stats")
	right.Position = UDim2.new(0.42, 10, 0, 0)
	right.Size = UDim2.new(0.58, -10, 1, 0)
	right.Parent = body
	for index, line in sheet.lines do
		statLine(right, t, line, index, color)
	end
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
	note.Size = UDim2.new(1, -8, 0, 32)
	note.Parent = right

	current:open()
end

-- L'objet a-t-il une fiche (arme à distance ou de mêlée) ?
function WeaponDetail.has(itemId: string): boolean
	return Config.Weapons.ranged[itemId] ~= nil or Config.Weapons.melee[itemId] ~= nil
end

return WeaponDetail
