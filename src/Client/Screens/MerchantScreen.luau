--!strict
--[[
	MerchantScreen : le Marchand (sections 14.2 et 17.3, écran 5).

	- Acheter : équipement en Dégradé et Bon état à ×2 la valeur, cellules
	  (20 crédits la pile), consommables (valeur × 1,5). Les objets Neufs ne
	  s'obtiennent que par le loot.
	- Vendre : sélection multiple (coffre et sac préparé), total en direct,
	  « Vendre tout le Très abîmé ».
	- Confirmation obligatoire au-delà de 1 000 crédits.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local ItemRules = require(Shared.Items.ItemRules)
local Pricing = require(Shared.Economy.Pricing)
local Types = require(Shared.Types)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local ConfirmDialog = require(script.Parent.Parent.UI.ConfirmDialog)
local Create = require(script.Parent.Parent.UI.Create)
local ItemCard = require(script.Parent.Parent.UI.ItemCard)
local Panel = require(script.Parent.Parent.UI.Panel)
local Theme = require(script.Parent.Parent.UI.Theme)

type Translate = (key: string, params: { [string]: any }?) -> string

local MerchantScreen = {}

local CATEGORY_ORDER = { "ranged", "melee", "gadget", "helmet", "vest", "backpack", "consumable", "cell" }

export type Screen = {
	panel: Panel.Panel,
	render: (view: Types.ProfileView) -> (),
}

function MerchantScreen.create(parent: Instance, t: Translate): Screen
	local panel = Panel.create("MerchantScreen", parent, Theme.green)
	local tab = "buy"
	local selected: { [string]: boolean } = {}
	local current: Types.ProfileView? = nil
	local confirmAbove = Config.Economy.merchant.confirmAbove

	local tabs = Panel.list("Tabs")
	tabs.Size = UDim2.new(1, 0, 0, 48)
	tabs.ScrollingEnabled = false
	(tabs:FindFirstChildOfClass("UIListLayout") :: UIListLayout).FillDirection = Enum.FillDirection.Horizontal
	tabs.Parent = panel.body
	local list = Panel.list("Offers")
	list.Position = UDim2.fromOffset(0, 54)
	list.Size = UDim2.new(1, 0, 1, -54)
	list.Parent = panel.body

	local creditsLabel = Panel.label("", 16, Theme.text)
	creditsLabel.Size = UDim2.fromOffset(240, 44)
	creditsLabel.Font = Theme.fontNumbers
	creditsLabel.Parent = panel.footer
	local totalLabel = Panel.label("", 16, Theme.orange)
	totalLabel.Size = UDim2.fromOffset(200, 44)
	totalLabel.Font = Theme.fontNumbers
	totalLabel.Parent = panel.footer
	local sellSelected = Panel.button("", Theme.orange, 220)
	sellSelected.Parent = panel.footer
	local sellWrecked = Panel.button("", Theme.orange, 260)
	sellWrecked.Parent = panel.footer

	local function confirmIfNeeded(amount: number, messageKey: string, send: (confirmed: boolean) -> ())
		if amount > confirmAbove then
			ConfirmDialog.ask(
				parent,
				t(messageKey, { credits = amount }),
				t("common.confirm"),
				t("common.cancel"),
				function()
					send(true)
				end
			)
		else
			send(false)
		end
	end

	local function sellable(view: Types.ProfileView): { Types.ItemInstance }
		local items = {}
		for _, list_ in { view.vault, view.bag } do
			for _, item in list_ do
				if ItemRules.isSellable(item) then
					table.insert(items, item)
				end
			end
		end
		return items
	end

	local function sell(uids: { string })
		local view = current
		if view == nil or #uids == 0 then
			return
		end
		local total = 0
		for _, item in sellable(view) do
			if table.find(uids, item.uid) then
				total += Pricing.sellPrice(item)
			end
		end
		confirmIfNeeded(total, "merchant.confirmSell", function(confirmed)
			ClientNet.fire("MerchantSell", uids, confirmed)
			table.clear(selected)
		end)
	end

	sellSelected.Activated:Connect(function()
		local uids = {}
		for uid in selected do
			table.insert(uids, uid)
		end
		sell(uids)
	end)
	sellWrecked.Activated:Connect(function()
		local view = current
		if view == nil then
			return
		end
		local uids = {}
		for _, item in sellable(view) do
			if item.condition == Config.Conditions.WRECKED then
				table.insert(uids, item.uid)
			end
		end
		sell(uids)
	end)

	local render: (view: Types.ProfileView) -> ()

	-- Cellules des armes à distance du joueur (équipées, au coffre, dans le sac).
	local function ammoNeeded(view: Types.ProfileView): { string }
		local cells: { string } = {}
		local function add(item: Types.ItemInstance?)
			local cell = if item then ItemRules.ammoOf(item.itemId) else nil
			if cell and table.find(cells, cell) == nil then
				table.insert(cells, cell)
			end
		end
		add(view.loadout.ranged)
		for _, items in { view.vault, view.bag } do
			for _, item in items do
				add(item)
			end
		end
		table.sort(cells)
		return cells
	end

	-- Exemplaires possédés (coffre, sac préparé) d'un objet empilable.
	local function ownedCount(view: Types.ProfileView, itemId: string): number
		local total = 0
		for _, items in { view.vault, view.bag } do
			for _, item in items do
				if item.itemId == itemId then
					total += item.stack or 1
				end
			end
		end
		return total
	end

	local function sectionTitle(order: number, key: string)
		Create("TextLabel", {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundTransparency = 1,
			Font = Theme.fontTitle,
			TextSize = 15,
			TextColor3 = Theme.orange,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = t(key),
			Parent = list,
		})
	end

	local function renderBuy(view: Types.ProfileView)
		local order = 0
		-- Survie (soins, batterie, Surcharge, exo-harnais) : achats de routine avant
		-- chaque partie, à l'unité ou par pile, avec le nombre déjà possédé.
		local survival = Config.Economy.merchant.survivalItems
		order += 1
		sectionTitle(order, "merchant.survival")
		for _, itemId in survival do
			local info = ItemCatalog.get(itemId)
			local stackSize = if info then info.stackSize or 1 else 1
			local unitPrice = Pricing.merchantPrice(itemId, nil, 1)
			local stackPrice = Pricing.merchantPrice(itemId, nil, stackSize)
			if info == nil or unitPrice == nil or stackPrice == nil then
				continue
			end
			order += 1
			local preview: Types.ItemInstance = {
				uid = `survival_{itemId}`,
				itemId = itemId,
			}
			local owned = ownedCount(view, itemId)
			local function buyAction(quantity: number, price: number, key: string)
				return {
					label = t(key, { credits = price, count = quantity }),
					color = if view.credits >= price then Theme.green else Theme.textDim,
					callback = function()
						confirmIfNeeded(price, "merchant.confirmBuy", function(confirmed)
							ClientNet.fire("MerchantBuy", itemId, nil, quantity, confirmed)
						end)
					end,
				}
			end
			local card = ItemCard.create(preview, t, {
				buyAction(1, unitPrice, "merchant.buyOne"),
				buyAction(stackSize, stackPrice, "merchant.buyStack"),
			}, order)
			-- Ce que l'on possède déjà (coffre et sac préparé), en tête des détails.
			local details = card:FindFirstChild("Details", true)
			if details and details:IsA("TextLabel") then
				details.Text = t("merchant.owned", { count = owned }) .. "  ·  " .. details.Text
			end
			card.Parent = list
		end
		-- En tête : les munitions de VOS armes (le reste du catalogue suit).
		-- En tête : les munitions de VOS armes (le reste du catalogue suit).
		local cells = ammoNeeded(view)
		if #cells > 0 then
			order += 1
			sectionTitle(order, "merchant.yourAmmo")
			for _, cellId in cells do
				local info = ItemCatalog.get(cellId) :: ItemCatalog.ItemInfo
				local price = Pricing.merchantPrice(cellId, nil)
				if price then
					order += 1
					local preview: Types.ItemInstance = {
						uid = `ammo_{cellId}`,
						itemId = cellId,
						stack = info.stackSize,
					}
					ItemCard.create(preview, t, {
						{
							label = t("merchant.buy", { credits = price }),
							color = if view.credits >= price then Theme.green else Theme.textDim,
							callback = function()
								confirmIfNeeded(price, "merchant.confirmBuy", function(confirmed)
									ClientNet.fire("MerchantBuy", cellId, nil, nil, confirmed)
								end)
							end,
						},
					}, order).Parent =
						list
				end
			end
		end
		local ids = {}
		for id in ItemCatalog.all() do
			table.insert(ids, id)
		end
		table.sort(ids, function(a, b)
			local infoA, infoB = ItemCatalog.get(a) :: any, ItemCatalog.get(b) :: any
			local rankA = table.find(CATEGORY_ORDER, infoA.category) or 99
			local rankB = table.find(CATEGORY_ORDER, infoB.category) or 99
			if rankA ~= rankB then
				return rankA < rankB
			end
			return a < b
		end)
		order += 1
		sectionTitle(order, "merchant.catalog")
		for _, itemId in ids do
			local info = ItemCatalog.get(itemId) :: ItemCatalog.ItemInfo
			if info.def.dropOnlyFromElites then
				continue -- Lame vibrante : lâchée uniquement par les élites
			end
			if table.find(survival, itemId) then
				continue -- déjà en tête (Survie)
			end
			local conditions: { number? } = if info.hasCondition
				then Config.Economy.merchant.sellsConditions :: any
				else { nil }
			for _, condition in conditions do
				local price = Pricing.merchantPrice(itemId, condition)
				if price == nil then
					continue
				end
				order += 1
				local preview: Types.ItemInstance = {
					uid = `offer_{itemId}_{condition or 0}`,
					itemId = itemId,
					condition = condition,
					stack = info.stackSize,
				}
				ItemCard.create(preview, t, {
					{
						label = t("merchant.buy", { credits = price }),
						color = if view.credits >= price then Theme.green else Theme.textDim,
						callback = function()
							confirmIfNeeded(price, "merchant.confirmBuy", function(confirmed)
								ClientNet.fire("MerchantBuy", itemId, condition, nil, confirmed)
							end)
						end,
					},
				}, order).Parent =
					list
			end
		end
	end

	local function renderSell(view: Types.ProfileView)
		local total = 0
		for index, item in sellable(view) do
			local isSelected = selected[item.uid] == true
			if isSelected then
				total += Pricing.sellPrice(item)
			end
			local card = ItemCard.create(item, t, {
				{
					label = if isSelected then "✔ " .. t("merchant.selected") else t("merchant.select"),
					color = if isSelected then Theme.orange else Theme.textDim,
					callback = function()
						if selected[item.uid] then
							selected[item.uid] = nil
						else
							selected[item.uid] = true
						end
						render(view)
					end,
				},
				{
					label = t("merchant.sellOne", { credits = Pricing.sellPrice(item) }),
					color = Theme.orange,
					callback = function()
						sell({ item.uid })
					end,
				},
			}, index)
			card.Parent = list
		end
		totalLabel.Text = t("merchant.total", { credits = total })
	end

	function render(view: Types.ProfileView)
		current = view
		panel.title.Text = t("station.merchant")
		Panel.clear(tabs)
		Panel.clear(list)
		creditsLabel.Text = t("topbar.credits", { credits = view.credits })
		for index, key in { "buy", "sell" } do
			local button =
				Panel.button(t("merchant.tab." .. key), if tab == key then Theme.green else Theme.textDim, 140)
			button.LayoutOrder = index
			button.Parent = tabs
			button.Activated:Connect(function()
				tab = key
				render(view)
			end)
		end
		local selling = tab == "sell"
		totalLabel.Visible = selling
		sellSelected.Visible = selling
		sellWrecked.Visible = selling
		sellSelected.Text = t("merchant.sellSelected")
		sellWrecked.Text = t("merchant.sellWrecked")
		-- Retire de la sélection ce qui n'existe plus.
		local present: { [string]: boolean } = {}
		for _, item in sellable(view) do
			present[item.uid] = true
		end
		for uid in selected do
			if not present[uid] then
				selected[uid] = nil
			end
		end
		if selling then
			renderSell(view)
		else
			renderBuy(view)
		end
	end

	return { panel = panel, render = render }
end

return MerchantScreen
