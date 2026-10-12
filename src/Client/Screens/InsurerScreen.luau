--!strict
--[[
	InsurerScreen : l'Assureur (sections 14.3 et 17.3, écran 7).

	SE actuel, 3 niveaux avec leur prix et leur effet. Le niveau choisi est
	payé au départ de la prochaine partie (selon le SE de départ).
	« Votre équipement assuré vous sera rendu après votre prochaine partie. »
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemRules = require(Shared.Items.ItemRules)
local Pricing = require(Shared.Economy.Pricing)
local Types = require(Shared.Types)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
local Panel = require(script.Parent.Parent.UI.Panel)
local Theme = require(script.Parent.Parent.UI.Theme)

type Translate = (key: string, params: { [string]: any }?) -> string

local InsurerScreen = {}

export type Screen = {
	panel: Panel.Panel,
	render: (view: Types.ProfileView) -> (),
}

function InsurerScreen.create(parent: Instance, t: Translate): Screen
	local panel = Panel.create("InsurerScreen", parent, Theme.cyan)
	local content = Panel.list("Tiers")
	content.Size = UDim2.fromScale(1, 1)
	content.Parent = panel.body

	local function render(view: Types.ProfileView)
		panel.title.Text = t("station.insurer")
		Panel.clear(content)
		local score = ItemRules.equipmentScore(view.loadout, view.bag)
		local header = Panel.label(t("insurer.score", { score = score }), 18, Theme.text)
		header.LayoutOrder = 1
		header.Parent = content
		local note = Panel.label(t("insurer.note"), 14, Theme.textDim)
		note.LayoutOrder = 2
		note.Parent = content

		local tiers: { { id: string, def: any } } = {}
		for id, def in Config.Economy.insurance.tiers :: { [string]: any } do
			table.insert(tiers, { id = id, def = def })
		end
		table.sort(tiers, function(a, b)
			return a.def.order < b.def.order
		end)
		for index, tier in tiers do
			local selected = view.insuranceTier == tier.id
			local price = Pricing.insuranceCost(tier.id, score) or 0
			local effect = if tier.def.conditionLoss == 0
				then t("insurer.effect.intact")
				else t("insurer.effect.loss", { states = tier.def.conditionLoss })
			local row = Create("Frame", {
				LayoutOrder = 10 + index,
				Size = UDim2.new(1, 0, 0, 70),
				BackgroundColor3 = Theme.panel,
				BackgroundTransparency = if selected then 0 else 0.3,
				Parent = content,
			}, {
				Stroke = Create(
					"UIStroke",
					{ Color = if selected then Theme.cyan else Theme.textDim, Transparency = 0.4 }
				),
				Name_ = Create("TextLabel", {
					Position = UDim2.fromOffset(12, 6),
					Size = UDim2.new(0.6, 0, 0, 24),
					BackgroundTransparency = 1,
					Font = Theme.fontTitle,
					TextSize = 18,
					TextColor3 = Theme.text,
					TextXAlignment = Enum.TextXAlignment.Left,
					Text = t("insurer.tier." .. tier.id)
						.. string.format("  ·  %d %%", math.floor(tier.def.costShare * 100 + 0.5)),
				}),
				Effect = Create("TextLabel", {
					Position = UDim2.fromOffset(12, 34),
					Size = UDim2.new(0.6, 0, 0, 24),
					BackgroundTransparency = 1,
					Font = Theme.fontText,
					TextSize = 14,
					TextColor3 = Theme.textDim,
					TextXAlignment = Enum.TextXAlignment.Left,
					Text = effect,
				}),
			})
			local button = Panel.button(
				if selected then "✔ " .. t("insurer.selected") else t("insurer.choose", { credits = price }),
				if selected then Theme.green else Theme.cyan,
				220
			)
			button.AnchorPoint = Vector2.new(1, 0.5)
			button.Position = UDim2.new(1, -12, 0.5, 0)
			button.Parent = row
			button.Activated:Connect(function()
				ClientNet.fire("SetInsurance", if selected then "none" else tier.id)
			end)
		end
	end

	return { panel = panel, render = render }
end

return InsurerScreen
