--!strict
--[[
	ContainerController : contenu d'une caisse, d'un sac de dépouille ou d'un
	tas d'objets au sol (section 9.3).

	- Prendre (ranger dans le sac) ou Équiper : un clic. Fouiller dans une
	  zone à risque doit rester court ; c'est l'ouverture de la caisse qui
	  prend du temps, pas le tri de son contenu.
	- « Tout prendre » (bouton, ou la touche d'interaction) : tout ce qui
	  tient dans le sac, le plus précieux d'abord, en une seule fois.
	- Sac plein : « Échanger » propose de choisir un objet du sac à laisser.
	- Le panneau se ferme si on s'éloigne (le serveur l'impose aussi).
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local InventoryLogic = require(Shared.Items.InventoryLogic)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local Types = require(Shared.Types)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local CapacityGauge = require(script.Parent.Parent.UI.CapacityGauge)
local Create = require(script.Parent.Parent.UI.Create)
local ItemCard = require(script.Parent.Parent.UI.ItemCard)
local PanelState = require(script.Parent.Parent.UI.PanelState)
local Theme = require(script.Parent.Parent.UI.Theme)
local HUDController = require(script.Parent.HUDController)
local InputController = require(script.Parent.InputController)
local InventoryController = require(script.Parent.InventoryController)
local ProfileController = require(script.Parent.ProfileController)

local ContainerController = {}

type ContainerView = {
	id: string,
	kind: string,
	crateType: string?,
	ownerName: string?, -- sac de dépouille
	items: { Types.ItemInstance },
	closed: boolean?,
}

local t = ProfileController.t
-- Touche de « Tout prendre » : celle qui a ouvert la caisse (invite d'interaction).
local TAKE_ALL_ACTION: InputController.Action = "gadget1"

local current: ContainerView? = nil
local swapFor: Types.ItemInstance? = nil -- objet à prendre en attente d'un échange
local panel: Frame
local title: TextLabel
local hint: TextLabel
local list: ScrollingFrame
local footer: TextLabel
local takeAllButton: TextButton
local gauge: CapacityGauge.Gauge -- place du sac pendant la fouille
-- Caisses déjà vues : leur contenu ne se « révèle » qu'à la première ouverture.
local seen: { [string]: boolean } = {}
local seenCount = 0
local revealNext = false

local function localInventory(): InventoryLogic.Inventory
	local state = InventoryController.state()
	return {
		equipped = state.equipped :: any,
		bag = state.bag,
		bonusUp = state.bonusUp,
	}
end

local function take(item: Types.ItemInstance, mode: string, swapUid: string?)
	local view = current
	if view then
		ClientNet.fire("TakeItem", view.id, item.uid, mode, swapUid)
	end
end

-- Objet suivant qu'on peut prendre sans échange : emplacement vide, ou place dans le sac.
local function nextTakeable(view: ContainerView): Types.ItemInstance?
	local inventory = localInventory()
	for _, item in view.items do
		local info = ItemCatalog.get(item.itemId)
		local slot = InventoryLogic.slotFor(inventory, item.itemId)
		local emptySlot = slot ~= nil and info ~= nil and info.hasCondition and (inventory.equipped :: any)[slot] == nil
		if emptySlot or InventoryLogic.canStore(inventory, item) then
			return item
		end
	end
	return nil
end

local function refreshTakeAll()
	local view = current
	local key = if InputController.device() == "keyboard" then InputController.hint(TAKE_ALL_ACTION) else nil
	takeAllButton.Text = t("loot.takeAll") .. (if key then `  [{key}]` else "")
	takeAllButton.Visible = view ~= nil and swapFor == nil and nextTakeable(view) ~= nil
end

-- Tout ce qui tient dans le sac, en une requête (le serveur trie et décide).
local function takeAll()
	local view = current
	if view and swapFor == nil and nextTakeable(view) ~= nil then
		ClientNet.fire("TakeAll", view.id)
	end
end

local function clear()
	for _, child in list:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

local function render()
	local view = current
	if view == nil then
		return
	end
	clear()
	refreshTakeAll()
	local inventory = localInventory()
	local bagState = InventoryController.state()
	gauge.set(bagState.used, bagState.capacity)

	if swapFor then
		-- Choix de l'objet du sac à laisser dans le conteneur.
		local wanted = swapFor
		hint.Text = t("inventory.swapHint")
		hint.Visible = true
		for index, bagItem in inventory.bag do
			ItemCard.create(bagItem, t, {
				{
					label = t("inventory.action.swap"),
					color = Theme.orange,
					callback = function()
						swapFor = nil
						take(wanted, "bag", bagItem.uid)
					end,
				},
			}, index).Parent =
				list
		end
		return
	end

	hint.Visible = false
	for index, item in view.items do
		local actions: { ItemCard.Action } = {}
		local info = ItemCatalog.get(item.itemId)
		local slot = InventoryLogic.slotFor(inventory, item.itemId)
		if slot ~= nil and info and info.hasCondition then
			table.insert(actions, {
				label = t("inventory.action.equip"),
				callback = function()
					take(item, "equip")
				end,
			})
		end
		if InventoryLogic.canStore(inventory, item) then
			table.insert(actions, {
				label = t("inventory.action.take"),
				color = Theme.green,
				callback = function()
					take(item, "bag")
				end,
			})
		elseif #inventory.bag > 0 then
			table.insert(actions, {
				label = t("inventory.action.swap"),
				color = Theme.orange,
				callback = function()
					swapFor = item
					render()
				end,
			})
		end
		local card = ItemCard.create(item, t, actions, index)
		card.Parent = list
		if revealNext then
			ItemCard.reveal(card, index)
		end
	end
	revealNext = false
	if #view.items == 0 then
		Create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			Font = Theme.fontText,
			TextSize = 14,
			TextColor3 = Theme.textDim,
			Text = t("inventory.empty"),
			Parent = list,
		})
	end
end

local function titleFor(view: ContainerView): string
	if view.kind == "crate" and view.crateType then
		return t("crate." .. view.crateType)
	elseif view.kind == "deathbag" then
		local owner = view.ownerName
		return if owner then t("loot.deathbagOf", { name = owner }) else t("loot.deathbag")
	end
	return t("loot.ground")
end

function ContainerController.close(notifyServer: boolean)
	local view = current
	current = nil
	swapFor = nil
	panel.Visible = false
	PanelState.set("container", false)
	if view and notifyServer then
		ClientNet.fire("CloseContainer", view.id)
	end
end

local function onSync(payload: ContainerView)
	if type(payload) ~= "table" or type(payload.id) ~= "string" then
		return
	end
	if payload.closed then
		if current and current.id == payload.id then
			ContainerController.close(false)
		end
		return
	end
	local wasOpen = current ~= nil
	if not seen[payload.id] then
		-- Première ouverture : les objets obtenus apparaissent un par un.
		if seenCount > 400 then
			table.clear(seen)
			seenCount = 0
		end
		seen[payload.id] = true
		seenCount += 1
		revealNext = true
	end
	current = payload
	title.Text = titleFor(payload)
	-- Rappel du geste, avec la touche de fermeture du périphérique utilisé.
	local closeKey = InputController.hint("inventory")
	footer.Text = t("hint.container") .. (if closeKey then `  ·  [{closeKey}] {t("hint.close")}` else "")
	panel.Visible = true
	PanelState.set("container", true)
	render()
	if not wasOpen and InputController.device() == "gamepad" then
		-- Manette : « Tout prendre » est sélectionné d'emblée (une pression suffit).
		GuiService.SelectedObject = if takeAllButton.Visible
			then takeAllButton
			else list:FindFirstChildWhichIsA("TextButton", true)
	end
end

function ContainerController.init() end

function ContainerController.start()
	title = Create("TextLabel", {
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -230, 0, 28),
		BackgroundTransparency = 1,
		Font = Theme.fontTitle,
		TextSize = 20,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = Theme.orange,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
	gauge = CapacityGauge.create(t, "bag", false)
	gauge.frame.Position = UDim2.fromOffset(12, 40)
	gauge.frame.Size = UDim2.new(1, -24, 0, 38)
	hint = Create("TextLabel", {
		Position = UDim2.fromOffset(12, 82),
		Size = UDim2.new(1, -24, 0, 18),
		BackgroundTransparency = 1,
		Font = Theme.fontText,
		TextSize = 14,
		TextColor3 = Theme.orange,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		Text = "",
	})
	list = Create("ScrollingFrame", {
		Position = UDim2.fromOffset(12, 104),
		Size = UDim2.new(1, -24, 1, -138),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, {
		Layout = Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local close = Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 6),
		Size = UDim2.fromOffset(Theme.minButtonSize, Theme.minButtonSize - 10),
		BackgroundTransparency = 1,
		Font = Theme.fontTitle,
		TextSize = 22,
		TextColor3 = Theme.textDim,
		Text = "✕",
	})
	footer = Create("TextLabel", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -8),
		Size = UDim2.new(1, -24, 0, 18),
		BackgroundTransparency = 1,
		Font = Theme.fontText,
		TextSize = 12,
		TextColor3 = Theme.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
	})
	takeAllButton = Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8 - Theme.minButtonSize - 6, 0, 8),
		Size = UDim2.fromOffset(150, Theme.minButtonSize - 14),
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = 0.1,
		Font = Theme.fontText,
		TextSize = 14,
		TextColor3 = Theme.green,
		Visible = false,
		Text = "",
	}, {
		Stroke = Create("UIStroke", { Color = Theme.green, Transparency = 0.5 }),
	})
	panel = Create("Frame", {
		Name = "ContainerPanel",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.new(0.46, 0, 0.7, 0),
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = 0.1,
		Visible = false,
		ZIndex = 5,
		Parent = HUDController.root(),
	}, {
		Stroke = Create("UIStroke", { Color = Theme.orange, Transparency = 0.4 }),
		SizeLimit = Create("UISizeConstraint", { MinSize = Vector2.new(320, 220), MaxSize = Vector2.new(620, 800) }),
		Title = title,
		Gauge = gauge.frame,
		Hint = hint,
		List = list,
		Footer = footer,
		TakeAll = takeAllButton,
		Close = close,
	})
	close.Activated:Connect(function()
		ContainerController.close(true)
	end)
	takeAllButton.Activated:Connect(takeAll)

	ClientNet.on("ContainerSync", onSync)
	-- Le sac change : les actions possibles (prendre / échanger) aussi.
	InventoryController.Changed:Connect(render)
	InputController.ActionBegan:Connect(function(action)
		if action == "inventory" and current ~= nil then
			ContainerController.close(true)
		end
	end)
	-- La touche d'interaction, panneau ouvert : tout prendre (les gadgets sont
	-- bloqués tant qu'un panneau est ouvert, la touche est donc libre).
	InputController.Tapped:Connect(function(action)
		if action == TAKE_ALL_ACTION and current ~= nil and InputController.device() == "keyboard" then
			takeAll()
		end
	end)
end

return ContainerController
