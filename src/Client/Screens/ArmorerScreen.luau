--!strict
--[[
	ArmorerScreen : l'Armurier (sections 7.3 et 17.3, écran 6).

	Réparation d'un état à la fois : comparaison avant / après (état,
	dégâts ou efficacité, valeur), coût, Module de calibration requis pour
	passer en Neuf. Réparer pour revendre fait toujours perdre de l'argent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local ItemRules = require(Shared.Items.ItemRules)
local Pricing = require(Shared.Economy.Pricing)
local Types = require(Shared.Types)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local ItemCard = require(script.Parent.Parent.UI.ItemCard)
local Panel = require(script.Parent.Parent.UI.Panel)
local Sparks = require(script.Parent.Parent.UI.Sparks)
local Theme = require(script.Parent.Parent.UI.Theme)

type Translate = (key: string, params: { [string]: any }?) -> string

local ArmorerScreen = {}

export type Screen = {
	panel: Panel.Panel,
	render: (view: Types.ProfileView) -> (),
}

-- Stat principale d'un objet à un état donné (pour la comparaison avant / après).
local function mainStat(item: Types.ItemInstance, condition: number): string
	local info = ItemCatalog.get(item.itemId)
	if info == nil then
		return ""
	end
	local efficiency = ItemRules.efficiency(condition)
	local def = info.def
	if info.category == "ranged" or info.category == "melee" then
		return string.format("%.1f", def.damage * efficiency)
	elseif info.category == "vest" then
		return tostring(def.shieldByCondition[condition])
	elseif info.category == "helmet" then
		return "×" .. tostring(def.headMultiplierByCondition[condition])
	elseif info.category == "backpack" then
		return tostring(def.capacityByCondition[condition])
	end
	return string.format("×%.2f", efficiency)
end

function ArmorerScreen.create(parent: Instance, t: Translate): Screen
	local panel = Panel.create("ArmorerScreen", parent, Theme.orange)
	local hint = Panel.label("", 14, Theme.textDim)
	hint.Parent = panel.body
	local list = Panel.list("Repairs")
	list.Position = UDim2.fromOffset(0, 26)
	list.Size = UDim2.new(1, 0, 1, -26)
	list.Parent = panel.body
	local creditsLabel = Panel.label("", 16, Theme.text)
	creditsLabel.Size = UDim2.fromOffset(260, 44)
	creditsLabel.Font = Theme.fontNumbers
	creditsLabel.Parent = panel.footer

	local function render(view: Types.ProfileView)
		panel.title.Text = t("station.armorer")
		hint.Text = t("armorer.hint")
		creditsLabel.Text = t("topbar.credits", { credits = view.credits })
		Panel.clear(list)
		local hasCalibration = false
		for _, item in view.vault do
			if item.itemId == Config.Economy.repair.calibrationItemId then
				hasCalibration = true
			end
		end
		local candidates: { Types.ItemInstance } = {}
		for _, slot in ItemCatalog.slotNames do
			local item = (view.loadout :: any)[slot] :: Types.ItemInstance?
			if item then
				table.insert(candidates, item)
			end
		end
		for _, item in view.vault do
			table.insert(candidates, item)
		end
		local order = 0
		for _, item in candidates do
			local cost, needsCalibration = Pricing.repairCost(item)
			if cost == nil then
				continue
			end
			order += 1
			local condition = item.condition :: number
			local before = Config.Conditions.list[condition]
			local after = Config.Conditions.list[condition + 1]
			local comparison = t("armorer.compare", {
				from = t("condition." .. before.key),
				to = t("condition." .. after.key),
				statFrom = mainStat(item, condition),
				statTo = mainStat(item, condition + 1),
				valueFrom = ItemRules.valueAt(item.itemId, condition),
				valueTo = ItemRules.valueAt(item.itemId, condition + 1),
			})
			local blocked = needsCalibration and not hasCalibration
			local card = ItemCard.create(item, t, {
				{
					label = if blocked then t("armorer.needsModule") else t("armorer.repair", { credits = cost }),
					color = if blocked or view.credits < cost then Theme.textDim else Theme.orange,
					callback = function()
						if not blocked then
							ClientNet.fire("Repair", item.uid)
							Sparks.burst(panel.frame)
						end
					end,
				},
			}, order)
			local details = card:FindFirstChild("Details") :: TextLabel?
			if details then
				details.Text = comparison
			end
			card.Parent = list
		end
		if order == 0 then
			Panel.label(t("armorer.nothing"), 14, Theme.textDim).Parent = list
		end
	end

	return { panel = panel, render = render }
end

return ArmorerScreen
