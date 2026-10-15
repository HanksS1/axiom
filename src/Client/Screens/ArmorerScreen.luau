--!strict
--[[
	ArmorerScreen : l'Armurier (sections 7.3 et 17.3, écran 6).

	Réparation d'un état à la fois : comparaison avant / après (état,
	dégâts ou efficacité, gain en %, valeur), coût, Module de calibration
	requis pour passer en Neuf. Réparer pour revendre fait toujours perdre de
	l'argent.

	Améliorer une arme = monter son état : c'est expliqué par une aide à la
	première visite (« Compris » la range, le bouton « ? » la rouvre), avec
	l'efficacité de chaque état (Config.Conditions) et l'origine du Module de
	calibration (butin du mode Difficile).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local ItemRules = require(Shared.Items.ItemRules)
local Pricing = require(Shared.Economy.Pricing)
local Types = require(Shared.Types)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
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

-- Stat principale d'un objet à un état donné : libellé (clé), valeur affichée et
-- valeur brute (pour le gain en %).
local function mainStat(item: Types.ItemInstance, condition: number): (string, string, number)
	local info = ItemCatalog.get(item.itemId)
	if info == nil then
		return "armorer.stat.efficiency", "", 0
	end
	local efficiency = ItemRules.efficiency(condition)
	local def = info.def
	if info.category == "ranged" or info.category == "melee" then
		local damage = def.damage * efficiency
		return "armorer.stat.damage", string.format("%.1f", damage), damage
	elseif info.category == "vest" then
		local shield = def.shieldByCondition[condition]
		return "armorer.stat.shield", tostring(shield), shield
	elseif info.category == "helmet" then
		local multiplier = def.headMultiplierByCondition[condition]
		return "armorer.stat.head", "×" .. tostring(multiplier), multiplier
	elseif info.category == "backpack" then
		local capacity = def.capacityByCondition[condition]
		return "armorer.stat.capacity", tostring(capacity), capacity
	end
	return "armorer.stat.efficiency", string.format("×%.2f", efficiency), efficiency
end

-- Efficacité de chaque état, dans l'ordre : « Endommagé ×0,70 → … → Neuf ×1,15 ».
local function conditionLadder(t: Translate): string
	local steps = {}
	for _, condition in Config.Conditions.list do
		table.insert(steps, t("condition." .. condition.key) .. " ×" .. string.format("%.2f", condition.efficiency))
	end
	return table.concat(steps, "  →  ")
end

function ArmorerScreen.create(parent: Instance, t: Translate): Screen
	local panel = Panel.create("ArmorerScreen", parent, Theme.orange)
	local hint = Panel.label("", 14, Theme.textDim)
	hint.Size = UDim2.new(1, -60, 0, 24)
	hint.Parent = panel.body
	-- « ? » : rouvre l'aide (comment améliorer une arme).
	local helpButton = Panel.button("?", Theme.cyan, 44)
	helpButton.AnchorPoint = Vector2.new(1, 0)
	helpButton.Position = UDim2.new(1, 0, 0, -10)
	helpButton.Parent = panel.body
	local list = Panel.list("Repairs")
	list.Position = UDim2.fromOffset(0, 30)
	list.Size = UDim2.new(1, 0, 1, -30)
	list.Parent = panel.body
	local showGuide = false -- rouverte à la demande (« ? »)
	local current: Types.ProfileView? = nil
	local creditsLabel = Panel.label("", 16, Theme.text)
	creditsLabel.Size = UDim2.fromOffset(260, 44)
	creditsLabel.Font = Theme.fontNumbers
	creditsLabel.Parent = panel.footer

	local render: (view: Types.ProfileView) -> ()

	-- Aide : ce qu'apporte l'amélioration, et comment passer en Neuf.
	local function guide(view: Types.ProfileView, modules: number)
		local box = Create("Frame", {
			LayoutOrder = -1,
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Theme.panel,
			Parent = list,
		}, {
			Stroke = Create("UIStroke", { Color = Theme.cyan, Transparency = 0.3 }),
			Padding = Create("UIPadding", {
				PaddingTop = UDim.new(0, 8),
				PaddingBottom = UDim.new(0, 8),
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 10),
			}),
			Layout = Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local function line(order: number, text: string, color: Color3, size: number?)
			local label = Panel.label(text, size or 14, color)
			label.LayoutOrder = order
			label.TextWrapped = true
			label.AutomaticSize = Enum.AutomaticSize.Y
			label.Size = UDim2.new(1, 0, 0, 0)
			label.Parent = box
		end
		line(1, t("armorer.guide.title"), Theme.cyan, 16)
		line(2, t("armorer.guide.body"), Theme.text)
		line(3, conditionLadder(t), Theme.orange)
		line(4, t("armorer.guide.module", { count = modules }), Theme.text)
		local ok = Panel.button(t("armorer.guide.ok"), Theme.cyan, 160)
		ok.LayoutOrder = 5
		ok.Parent = box
		ok.Activated:Connect(function()
			showGuide = false
			if view.guidesSeen.armorer ~= true then
				ClientNet.fire("GuideSeen", "armorer")
			end
			render(view)
		end)
	end

	function render(view: Types.ProfileView)
		current = view
		panel.title.Text = t("station.armorer")
		hint.Text = t("armorer.hint")
		creditsLabel.Text = t("topbar.credits", { credits = view.credits })
		Panel.clear(list)
		local modules = 0
		for _, item in view.vault do
			if item.itemId == Config.Economy.repair.calibrationItemId then
				modules += 1
			end
		end
		local hasCalibration = modules > 0
		if showGuide or view.guidesSeen.armorer ~= true then
			guide(view, modules)
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
			local statKey, statFrom, rawFrom = mainStat(item, condition)
			local _, statTo, rawTo = mainStat(item, condition + 1)
			local gain = if rawFrom > 0 then math.floor((rawTo / rawFrom - 1) * 100 + 0.5) else 0
			local comparison = t("armorer.compare", {
				from = t("condition." .. before.key),
				to = t("condition." .. after.key),
				stat = t(statKey),
				statFrom = statFrom,
				statTo = statTo,
				gain = gain,
				valueFrom = ItemRules.valueAt(item.itemId, condition),
				valueTo = ItemRules.valueAt(item.itemId, condition + 1),
			})
			local blocked = needsCalibration and not hasCalibration
			if needsCalibration then
				-- Dernier cran : dire ce qu'il faut, et où le trouver.
				comparison ..= "\n" .. (if blocked
					then t("armorer.moduleWhere", {
						mode = t("mode.hard"),
						robot = t("robot.warden"),
						locker = t("crate.axiom_locker"),
						bin = t("crate.parts_bin"),
					})
					else t("armorer.moduleUsed"))
			end
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
				details.TextWrapped = true
			end
			card.Parent = list
		end
		if order == 0 then
			Panel.label(t("armorer.nothing"), 14, Theme.textDim).Parent = list
		end
	end

	helpButton.Activated:Connect(function()
		showGuide = true
		local view = current
		if view then
			render(view)
		end
	end)

	return { panel = panel, render = render }
end

return ArmorerScreen
