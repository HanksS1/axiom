--!strict
--[[
	LoadoutView : ce que le joueur PORTE, en zones (inventaire en partie, coffre
	côté équipement). Remplace les deux listes verticales de cartes.

	┌ ARMES ──────────────────────────────┐
	│ [ Principale ]   [ Secondaire ]      │  grandes cases
	├ PROTECTIONS ──────┬ GADGETS ────────┤
	│ [Casque] [Gilet]   │ [G1] [G2]        │
	├ SAC À DOS ─────────────────────────┤
	│ [Sac]  jauge « 6 / 8 UP » + « ce sac fixe la place »
	├ CONTENU DU SAC ────────────────────┤
	│ [ ][ ][ ][ ][ ] grille, quantités   │
	└────────────────────────────────────┘
	  Carte de l'objet choisi + ses actions (ItemCard), toujours visible en bas.

	- Un emplacement vide reste une case : silhouette estompée + nom.
	- Choisir une case (clic, toucher, A à la manette — les cases sont des
	  boutons : la manette passe de case en case) affiche sa carte et ses
	  actions en bas ; choisir de nouveau une arme déjà choisie ouvre sa fiche.
	- Souris : glisser-déposer (UI/DragDrop) si l'écran fournit `drag`.
	- Mises à jour CIBLÉES : une case n'est recréée que si son objet change
	  (uid, état) ; la quantité d'une pile se met à jour sur place. Rien n'est
	  reconstruit à chaque synchronisation (vignettes 3D coûteuses).
	Affichage seulement : aucune règle d'inventaire ici (InventoryLogic, serveur).
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local ItemRules = require(Shared.Items.ItemRules)
local Types = require(Shared.Types)

local CapacityGauge = require(script.Parent.CapacityGauge)
local Create = require(script.Parent.Create)
local DragDrop = require(script.Parent.DragDrop)
local ItemCard = require(script.Parent.ItemCard)
local ItemIcon = require(script.Parent.ItemIcon)
local Theme = require(script.Parent.Theme)
local WeaponDetail = require(script.Parent.WeaponDetail)

type ItemInstance = Types.ItemInstance
type Translate = (key: string, params: { [string]: any }?) -> string

export type Where = "equipped" | "bag"

export type Options = {
	t: Translate,
	-- Actions de la carte de l'objet choisi.
	actionsFor: (item: ItemInstance, where: Where, slot: string?) -> { ItemCard.Action },
	-- Options de cette carte (raison d'une action grisée…). Facultatif.
	cardOptions: ((item: ItemInstance, where: Where, slot: string?) -> ItemCard.Options?)?,
	-- Glisser-déposer à la souris : contenu porté par la case, et noms des zones
	-- de dépôt (cases d'équipement, grille du sac). Facultatif.
	drag: {
		payload: (item: ItemInstance, where: Where, slot: string?) -> any,
		slotTarget: string,
		bagTarget: string,
	}?,
}

export type View = {
	frame: Frame,
	set: (equipped: { [string]: ItemInstance }, bag: { ItemInstance }, used: number, capacity: number) -> (),
	refreshTexts: () -> (),
	-- Choisit la première case (arme principale) et la retourne (sélection manette).
	selectFirst: () -> TextButton?,
}

local LoadoutView = {}

local V = Config.Visuals.inventory
local HEADER_HEIGHT = 18
-- Carte de l'objet choisi (ItemCard : 64 px, plus une ligne d'actions sur un panneau étroit) + marge.
local SELECTION_HEIGHT = 70
local SELECTION_HEIGHT_NARROW = 120
local NARROW = 380

-- Case : un bouton (sélection manette / tactile), vignette, badges, état choisi.
type Tile = {
	button: TextButton,
	item: ItemInstance?,
	key: string?, -- objet affiché (uid + état) : la vignette n'est recréée que s'il change
	set: (item: ItemInstance?) -> (),
	setSelected: (selected: boolean) -> (),
	payload: { [string]: any }, -- glisser-déposer (mis à jour sur place)
}

local function sectionHeader(text: string, order: number): TextLabel
	return Create("TextLabel", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
		BackgroundTransparency = 1,
		Font = Theme.fontTitle,
		TextSize = 13,
		TextColor3 = Theme.cyan,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
	})
end

local function badge(name: string, anchor: Vector2, position: UDim2): TextLabel
	return Create("TextLabel", {
		Name = name,
		AnchorPoint = anchor,
		Position = position,
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.background,
		BackgroundTransparency = 0.15,
		Font = Theme.fontNumbers,
		TextSize = 13,
		TextColor3 = Theme.text,
		Text = "",
		Visible = false,
		ZIndex = 4,
	}, {
		Corner = Create("UICorner", { CornerRadius = UDim.new(0, 3) }),
		Padding = Create("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }),
	})
end

--[[
	Nouvelle case. `slot` : emplacement d'équipement (case vide affichée avec
	sa silhouette), nil pour une case du sac. `label` : nom de l'emplacement.
]]
local function newTile(size: UDim2, slot: string?, label: string?, t: Translate, onActivate: (tile: Tile) -> ()): Tile
	local stroke = Create("UIStroke", { Color = Theme.textDim, Transparency = 0.6, Thickness = 1 })
	local button = Create("TextButton", {
		Size = size,
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = 0.2,
		AutoButtonColor = false,
		Text = "",
		Selectable = true,
	}, {
		Corner = Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Stroke = stroke,
	})
	local slotLabel = Create("TextLabel", {
		Name = "SlotName",
		Position = UDim2.fromOffset(6, 3),
		Size = UDim2.new(1, -12, 0, 14),
		BackgroundTransparency = 1,
		Font = Theme.fontTitle,
		TextSize = 11,
		TextColor3 = Theme.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = label or "",
		Visible = label ~= nil,
		ZIndex = 4,
		Parent = button,
	})
	local up = badge("Up", Vector2.new(1, 0), UDim2.new(1, -4, 0, 4))
	up.Parent = button
	local count = badge("Count", Vector2.new(1, 1), UDim2.new(1, -4, 1, -4))
	count.Parent = button
	local emptyText = Create("TextLabel", {
		Name = "Empty",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -8, 0, 14),
		BackgroundTransparency = 1,
		Font = Theme.fontText,
		TextSize = 11,
		TextColor3 = Theme.textDim,
		Text = t("inventory.empty"),
		Visible = false,
		ZIndex = 4,
		Parent = button,
	})
	local icon: Frame? = nil
	local tile: Tile
	tile = {
		button = button,
		item = nil,
		key = nil,
		payload = {},
		set = function(item: ItemInstance?)
			tile.item = item
			local key = if item then `{item.uid}:{item.itemId}:{item.condition or 0}` else "empty"
			if key ~= tile.key then
				tile.key = key
				if icon then
					icon:Destroy()
					icon = nil
				end
				local iconId = if item then item.itemId elseif slot then V.silhouettes[slot] else nil
				if iconId then
					local created =
						ItemIcon.create(iconId, UDim2.new(1, -8, 1, -8), if item then item.condition else nil)
					created.AnchorPoint = Vector2.new(0.5, 0.5)
					created.Position = UDim2.fromScale(0.5, 0.5)
					created.Active = false
					if item == nil then
						ItemIcon.silhouette(created, V.silhouetteTransparency)
					end
					created.Parent = button
					icon = created
				end
			end
			local info = if item then ItemCatalog.get(item.itemId) else nil
			up.Visible = info ~= nil
			up.Text = if info then t("inventory.up", { up = info.up }) else ""
			local stack = if item then item.stack else nil
			count.Visible = stack ~= nil and stack > 1
			count.Text = if stack then t("inventory.stack", { count = stack }) else ""
			emptyText.Visible = item == nil and slot ~= nil
			slotLabel.TextColor3 = if item then Theme.text else Theme.textDim
		end,
		setSelected = function(selected: boolean)
			stroke.Color = if selected then Theme.cyan else Theme.textDim
			stroke.Thickness = if selected then 2 else 1
			stroke.Transparency = if selected then 0 else 0.6
		end,
	}
	button.Activated:Connect(function()
		onActivate(tile)
	end)
	return tile
end

-- Rangée de cases (groupe d'une zone), en largeur égale.
local function tileRow(order: number, height: number, columns: number): Frame
	return Create("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
	}, {
		Grid = Create("UIGridLayout", {
			CellSize = UDim2.new(1 / columns, -V.gap, 0, height),
			CellPadding = UDim2.fromOffset(V.gap, 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

function LoadoutView.create(options: Options): View
	local t = options.t
	local frame = Create("Frame", {
		Name = "Loadout",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	local scroll = Create("ScrollingFrame", {
		Name = "Zones",
		Size = UDim2.new(1, 0, 1, -SELECTION_HEIGHT),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = frame,
	}, {
		Layout = Create("UIListLayout", { Padding = UDim.new(0, V.gap), SortOrder = Enum.SortOrder.LayoutOrder }),
		Padding = Create("UIPadding", { PaddingRight = UDim.new(0, 8) }),
	})
	local selectionHolder = Create("Frame", {
		Name = "Selection",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, SELECTION_HEIGHT - V.gap),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	local selectionHint = Create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Theme.fontText,
		TextSize = 13,
		TextColor3 = Theme.textDim,
		TextWrapped = true,
		Text = "",
		Parent = selectionHolder,
	})

	local headers: { [string]: TextLabel } = {}
	local tiles: { [string]: Tile } = {}
	local bagTiles: { [string]: Tile } = {}
	local selected: Tile? = nil
	local selectionCard: Frame? = nil
	local selectionKey: string? = nil

	local function slotLabel(slot: string): string
		if slot == "ranged" then
			return t("inventory.slot.primary")
		elseif slot == "melee" then
			return t("inventory.slot.secondary")
		end
		return t("slot." .. slot)
	end

	local function whereOf(tile: Tile): (Where, string?)
		for slot, candidate in tiles do
			if candidate == tile then
				return "equipped", slot
			end
		end
		return "bag", nil
	end

	-- Carte de l'objet choisi (recréée seulement si l'objet ou son état change).
	local function refreshSelection(force: boolean?)
		local tile = selected
		local item = if tile then tile.item else nil
		if item == nil then
			if selectionCard then
				selectionCard:Destroy()
				selectionCard = nil
			end
			selectionKey = nil
			local slot: string? = nil
			if tile then
				local _, emptySlot = whereOf(tile)
				slot = emptySlot
			end
			selectionHint.Text = if slot
				then t("inventory.emptySlotHint", { slot = slotLabel(slot) })
				else t("inventory.selectHint")
			selectionHint.Visible = true
			return
		end
		local where, slot = whereOf(tile :: Tile)
		local key = `{where}:{slot or ""}:{item.uid}:{item.stack or 0}:{item.condition or 0}`
		if key == selectionKey and not force then
			return
		end
		selectionKey = key
		-- Manette : si la sélection était sur un bouton de l'ancienne carte (« Équiper »…),
		-- elle revient sur la case choisie au lieu de se perdre avec la carte détruite.
		local focus = GuiService.SelectedObject
		local hadFocus = selectionCard ~= nil and focus ~= nil and focus:IsDescendantOf(selectionCard)
		if selectionCard then
			selectionCard:Destroy()
		end
		selectionHint.Visible = false
		local cardOptions = if options.cardOptions then options.cardOptions(item, where, slot) else nil
		local card = ItemCard.create(item, t, options.actionsFor(item, where, slot), 1, cardOptions)
		card.Parent = selectionHolder
		selectionCard = card
		if hadFocus and tile then
			GuiService.SelectedObject = tile.button
		end
	end

	local function choose(tile: Tile)
		local item = tile.item
		if selected == tile and item and WeaponDetail.has(item.itemId) then
			-- Seconde sélection d'une arme : sa fiche.
			ItemCard.openDetail(item, t)
			return
		end
		if selected then
			selected.setSelected(false)
		end
		selected = tile
		tile.setSelected(true)
		refreshSelection()
	end

	local function attachDrag(tile: Tile, where: Where, slot: string?)
		local drag = options.drag
		if drag == nil then
			return
		end
		DragDrop.attach(tile.button, tile.payload)
		if where == "equipped" then
			DragDrop.target(tile.button, drag.slotTarget)
		end
		tile.payload.where = where
		tile.payload.slot = slot
	end

	-- Zones fixes : armes, protections + gadgets, sac à dos (+ jauge), contenu.
	headers.weapons = sectionHeader("", 1)
	headers.weapons.Parent = scroll
	local weapons = tileRow(2, V.weaponTile, 2)
	weapons.Parent = scroll
	local middle = Create("Frame", {
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, HEADER_HEIGHT + V.slotTile),
		BackgroundTransparency = 1,
		Parent = scroll,
	})
	local function group(name: string, x: number): Frame
		headers[name] = sectionHeader("", 0)
		headers[name].Position = UDim2.fromScale(x, 0)
		headers[name].Size = UDim2.new(0.5, -V.gap, 0, HEADER_HEIGHT)
		headers[name].Parent = middle
		local row = tileRow(0, V.slotTile, 2)
		row.Position = UDim2.new(x, 0, 0, HEADER_HEIGHT)
		row.Size = UDim2.new(0.5, -V.gap, 0, V.slotTile)
		row.Parent = middle
		return row
	end
	local protections = group("protection", 0)
	local gadgets = group("gadgets", 0.5)
	headers.backpack = sectionHeader("", 4)
	headers.backpack.Parent = scroll
	local backpackRow = Create("Frame", {
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, V.slotTile),
		BackgroundTransparency = 1,
		Parent = scroll,
	})
	local gauge = CapacityGauge.create(t, "bag", true)
	gauge.frame.Position = UDim2.fromOffset(V.slotTile + V.gap * 2, 0)
	gauge.frame.Size = UDim2.new(1, -(V.slotTile + V.gap * 2), 0, 38)
	gauge.frame.Parent = backpackRow
	-- Le lien entre le sac porté et sa place, écrit à côté de la jauge.
	local capacityNote = Create("TextLabel", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, V.slotTile + V.gap * 2, 1, 0),
		Size = UDim2.new(1, -(V.slotTile + V.gap * 2), 0, 18),
		BackgroundTransparency = 1,
		Font = Theme.fontText,
		TextSize = 12,
		TextColor3 = Theme.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
		Parent = backpackRow,
	})
	headers.contents = sectionHeader("", 6)
	headers.contents.Parent = scroll
	local grid = Create("Frame", {
		Name = "BagGrid",
		LayoutOrder = 7,
		Size = UDim2.new(1, 0, 0, V.bagCell),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = scroll,
	}, {
		Grid = Create("UIGridLayout", {
			CellSize = UDim2.fromOffset(V.bagCell, V.bagCell),
			CellPadding = UDim2.fromOffset(V.gap, V.gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local bagEmpty = Create("TextLabel", {
		LayoutOrder = 8,
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Font = Theme.fontText,
		TextSize = 13,
		TextColor3 = Theme.textDim,
		Text = "",
		Visible = false,
		Parent = scroll,
	})
	local drag = options.drag
	if drag then
		DragDrop.target(grid, drag.bagTarget)
	end

	local placements: { { slot: string, parent: Frame, order: number, size: UDim2 } } = {
		{ slot = "ranged", parent = weapons, order = 1, size = UDim2.fromScale(1, 1) },
		{ slot = "melee", parent = weapons, order = 2, size = UDim2.fromScale(1, 1) },
		{ slot = "helmet", parent = protections, order = 1, size = UDim2.fromScale(1, 1) },
		{ slot = "vest", parent = protections, order = 2, size = UDim2.fromScale(1, 1) },
		{ slot = "gadget1", parent = gadgets, order = 1, size = UDim2.fromScale(1, 1) },
		{ slot = "gadget2", parent = gadgets, order = 2, size = UDim2.fromScale(1, 1) },
		{ slot = "backpack", parent = backpackRow, order = 1, size = UDim2.fromOffset(V.slotTile, V.slotTile) },
	}
	for _, placement in placements do
		local tile = newTile(placement.size, placement.slot, slotLabel(placement.slot), t, choose)
		tile.button.LayoutOrder = placement.order
		tile.button.Parent = placement.parent
		tile.set(nil)
		attachDrag(tile, "equipped", placement.slot)
		tiles[placement.slot] = tile
	end

	local function refreshTexts()
		headers.weapons.Text = t("inventory.zone.weapons")
		headers.protection.Text = t("inventory.zone.protection")
		headers.gadgets.Text = t("inventory.zone.gadgets")
		headers.backpack.Text = t("inventory.zone.backpack")
		headers.contents.Text = t("inventory.zone.contents")
		for slot, tile in tiles do
			(tile.button:FindFirstChild("SlotName") :: TextLabel).Text = slotLabel(slot)
		end
		bagEmpty.Text = t("inventory.empty")
	end

	local function set(equipped: { [string]: ItemInstance }, bag: { ItemInstance }, used: number, capacity: number)
		for slot, tile in tiles do
			local item = equipped[slot]
			tile.set(item)
			tile.payload.uid = if item then item.uid else nil
			tile.payload.itemId = if item then item.itemId else nil
			if item == nil then
				tile.payload.from = nil -- case vide : rien à glisser
			end
			if item and options.drag then
				local payload = options.drag.payload(item, "equipped", slot)
				for k, v in payload do
					tile.payload[k] = v
				end
			end
		end
		-- Grille du sac : cases gardées par uid, créées / détruites au besoin.
		local seen: { [string]: boolean } = {}
		for index, item in bag do
			seen[item.uid] = true
			local tile = bagTiles[item.uid]
			if tile == nil then
				tile = newTile(UDim2.fromOffset(V.bagCell, V.bagCell), nil, nil, t, choose)
				tile.button.Parent = grid
				attachDrag(tile, "bag", nil)
				bagTiles[item.uid] = tile
			end
			tile.button.LayoutOrder = index
			tile.set(item)
			if options.drag then
				for k, v in options.drag.payload(item, "bag", nil) do
					tile.payload[k] = v
				end
			end
		end
		for uid, tile in bagTiles do
			if not seen[uid] then
				if selected == tile then
					selected = nil
				end
				tile.button:Destroy()
				bagTiles[uid] = nil
			end
		end
		bagEmpty.Visible = #bag == 0
		gauge.set(used, capacity)
		local backpack = equipped.backpack
		capacityNote.Text = if backpack
			then t("inventory.backpackCapacity", { capacity = ItemRules.bagCapacity(backpack) })
			else t("inventory.noBackpack", { capacity = ItemRules.bagCapacity(nil) })
		-- Les actions dépendent de l'état (emplacement libre…) : la carte choisie suit.
		refreshSelection(true)
	end

	local function selectFirst(): TextButton?
		local first = tiles.ranged
		if first == nil then
			return nil
		end
		if selected ~= first then
			choose(first)
		end
		return first.button
	end

	-- Hauteur de la carte choisie : une ligne d'actions de plus sur un panneau étroit.
	local function layout()
		local narrow = frame.AbsoluteSize.X > 0 and frame.AbsoluteSize.X < NARROW
		local height = if narrow then SELECTION_HEIGHT_NARROW else SELECTION_HEIGHT
		scroll.Size = UDim2.new(1, 0, 1, -height)
		selectionHolder.Size = UDim2.new(1, 0, 0, height - V.gap)
	end
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()
	refreshTexts()
	refreshSelection()

	return { frame = frame, set = set, refreshTexts = refreshTexts, selectFirst = selectFirst }
end

return LoadoutView
