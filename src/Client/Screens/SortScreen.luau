--!strict
--[[
	SortScreen : écran de tri après une partie (sections 8.7 et 17.3, écran 15).

	Le loot extrait (et les objets rendus par l'assurance) attend ici :
	Garder (rejoint le coffre s'il y a la place), Vendre, Jeter. Le jeu ne
	sauvegarde jamais un coffre au-delà de sa capacité : sans place, il faut
	vendre ou jeter. Un nouveau départ en partie exige un tri terminé.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemRules = require(Shared.Items.ItemRules)
local Pricing = require(Shared.Economy.Pricing)
local Types = require(Shared.Types)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local CapacityGauge = require(script.Parent.Parent.UI.CapacityGauge)
local ConfirmDialog = require(script.Parent.Parent.UI.ConfirmDialog)
local ItemCard = require(script.Parent.Parent.UI.ItemCard)
local Panel = require(script.Parent.Parent.UI.Panel)
local Theme = require(script.Parent.Parent.UI.Theme)

type Translate = (key: string, params: { [string]: any }?) -> string

local SortScreen = {}

export type Screen = {
	panel: Panel.Panel,
	render: (view: Types.ProfileView) -> (),
}

function SortScreen.create(parent: Instance, t: Translate): Screen
	local panel = Panel.create("SortScreen", parent, Theme.orange)
	local info = Panel.label("", 15, Theme.textDim)
	info.Parent = panel.body
	local list = Panel.list("Pending")
	list.Position = UDim2.fromOffset(0, 30)
	list.Size = UDim2.new(1, 0, 1, -30)
	list.Parent = panel.body

	local vaultGauge = CapacityGauge.create(t, "vault", false)
	vaultGauge.frame.Size = UDim2.fromOffset(300, 38)
	vaultGauge.frame.Parent = panel.footer
	local sellWrecked = Panel.button("", Theme.orange, 260)
	sellWrecked.Parent = panel.footer
	-- Tout garder : ce qui tient dans le coffre, le plus précieux d'abord (le reste attend).
	local keepAll = Panel.button("", Theme.green, 200)
	keepAll.Parent = panel.footer
	keepAll.Activated:Connect(function()
		ClientNet.fire("VaultAction", "keepAll", nil, nil)
	end)

	local current: Types.ProfileView? = nil

	local function sell(uids: { string }, total: number)
		if #uids == 0 then
			return
		end
		local function send(confirmed: boolean)
			ClientNet.fire("MerchantSell", uids, confirmed)
		end
		if total > Config.Economy.merchant.confirmAbove then
			ConfirmDialog.ask(
				parent,
				t("merchant.confirmSell", { credits = total }),
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

	sellWrecked.Activated:Connect(function()
		local view = current
		if view == nil then
			return
		end
		local uids, total = {}, 0
		for _, item in view.pendingLoot do
			if item.condition == 1 and ItemRules.isSellable(item) then
				table.insert(uids, item.uid)
				total += Pricing.sellPrice(item)
			end
		end
		sell(uids, total)
	end)

	local function render(view: Types.ProfileView)
		current = view
		panel.title.Text = t("sort.title")
		sellWrecked.Text = t("merchant.sellWrecked")
		keepAll.Text = t("sort.keepAll")
		keepAll.Visible = #view.pendingLoot > 0
		Panel.clear(list)
		local vaultUsed = ItemRules.totalUp(view.vault)
		local free = view.vaultCapacity - vaultUsed
		vaultGauge.set(vaultUsed, view.vaultCapacity)
		-- Coffre plein : le dire en tête, avec ce qu'on peut faire.
		local vaultFull = ItemRules.fillLevel(vaultUsed, view.vaultCapacity) == "full"
		info.Text = if vaultFull and #view.pendingLoot > 0
			then t("capacity.vaultFullHint")
			elseif #view.pendingLoot > 0 then t("sort.hint")
			else t("sort.done")
		info.TextColor3 = if vaultFull and #view.pendingLoot > 0 then Theme.red else Theme.textDim
		for index, item in view.pendingLoot do
			local actions: { ItemCard.Action } = {}
			if ItemRules.up(item) <= free then
				table.insert(actions, {
					label = t("sort.keep"),
					color = Theme.green,
					callback = function()
						ClientNet.fire("VaultAction", "keep", item.uid, nil)
					end,
				})
			end
			if ItemRules.isSellable(item) then
				table.insert(actions, {
					label = t("sort.sell", { credits = Pricing.sellPrice(item) }),
					color = Theme.orange,
					callback = function()
						sell({ item.uid }, Pricing.sellPrice(item))
					end,
				})
			end
			table.insert(actions, {
				label = t("inventory.action.drop"),
				color = Theme.red,
				callback = function()
					ClientNet.fire("VaultAction", "discard", item.uid, nil)
				end,
			})
			ItemCard.create(item, t, actions, index).Parent = list
		end
	end

	return { panel = panel, render = render }
end

return SortScreen
