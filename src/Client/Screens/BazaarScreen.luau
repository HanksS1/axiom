--!strict
--[[
	BazaarScreen : Holo-Bazar (sections 14.5 à 14.10, écran 8).

	- Rotation du jour : 6 objets à la une, aperçu 3D qui tourne, néon de la
	  rareté, VRAI compte à rebours jusqu'à 00:00 UTC.
	- Caisses : probabilités réelles de chaque rareté (somme exactement
	  100 %), mises à jour quand la garantie s'applique, compteur de garantie,
	  aperçu du contenu. Masquées si les objets aléatoires payants sont
	  interdits pour le joueur (PolicyService).
	- Noyaux : packs avec leur prix en Robux affiché directement, extension
	  de coffre (Game Pass).
	- Collection : cosmétiques possédés, à équiper par emplacement.

	Aucun faux minuteur, aucune fausse rareté, aucune fenêtre d'achat qui
	s'ouvre seule (14.10).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Shop = require(Shared.Monetization.Shop)
local Types = require(Shared.Types)

local Create = require(script.Parent.Parent.UI.Create)
local ItemIcon = require(script.Parent.Parent.UI.ItemIcon)
local Panel = require(script.Parent.Parent.UI.Panel)
local Theme = require(script.Parent.Parent.UI.Theme)

type Translate = (key: string, params: { [string]: any }?) -> string

local M = Config.Monetization

local BazaarScreen = {}

export type Hooks = {
	buy: (cosmeticId: string) -> (),
	openCrate: (crateId: string) -> (),
	equip: (slot: string, cosmeticId: string?) -> (),
	buyPack: (packId: string) -> (),
	buyVaultExtension: () -> (),
}

export type Screen = {
	panel: Panel.Panel,
	render: (view: Types.ProfileView) -> (),
}

local TABS = { "featured", "crates", "noyaux", "collection" }

-- Nom affiché d'un cosmétique : motif · cible.
function BazaarScreen.cosmeticName(t: Translate, cosmeticId: string): string
	local def = Config.Cosmetics.byId[cosmeticId]
	if def == nil then
		return cosmeticId
	end
	local target = if def.category == "weapon" then t("item." .. def.target) else t("cosmetic.slot." .. def.category)
	return t("skin." .. def.pattern) .. " · " .. target
end

function BazaarScreen.rarityColor(rarity: string): Color3
	return (M.rarityColors :: any)[rarity] or Theme.textDim
end

-- Aperçu 3D : le vrai modèle de l'arme (ou de la pièce d'armure) aux couleurs du skin, qui tourne.
local PREVIEW_ITEM: { [string]: string } = { backpack = "backpack_medium", helmet = "helmet", vest = "vest" }
local function preview(def: any, size: UDim2, spin: boolean): Frame
	local itemId = if def.category == "weapon" then def.target else PREVIEW_ITEM[def.category] or def.target
	return ItemIcon.create(itemId, size, nil, def, spin)
end

-- Ce que le skin habille : l'arme ciblée, ou le sac / le casque / le gilet.
function BazaarScreen.targetName(t: Translate, cosmeticId: string): string
	local def = Config.Cosmetics.byId[cosmeticId]
	if def == nil then
		return ""
	end
	return if def.category == "weapon" then t("item." .. def.target) else t("cosmetic.slot." .. def.category)
end

-- Famille du skin pour les textes : « weapon » ou « gear ».
function BazaarScreen.skinFamily(cosmeticId: string): string
	local def = Config.Cosmetics.byId[cosmeticId]
	return if def and def.category == "weapon" then "weapon" else "gear"
end

-- Le joueur a-t-il l'objet que ce skin habille (porté, au coffre, aucun) ?
function BazaarScreen.skinStatus(view: Types.ProfileView, cosmeticId: string): Shop.SkinStatus?
	local items = {}
	for _, item in view.vault do
		table.insert(items, item)
	end
	for _, item in view.bag do
		table.insert(items, item)
	end
	return Shop.skinStatus(cosmeticId, view.loadout :: any, items)
end

-- Objet qui porte un cosmétique (l'arme ciblée, ou un sac / casque / gilet type).
function BazaarScreen.previewItem(def: any): string
	return if def.category == "weapon" then def.target else PREVIEW_ITEM[def.category] or def.target
end

local function formatPercent(hundredths: number): string
	return string.format("%d,%02d %%", math.floor(hundredths / 100), hundredths % 100)
end

function BazaarScreen.create(parent: Instance, t: Translate, hooks: Hooks): Screen
	local panel = Panel.create("BazaarScreen", parent, Theme.magenta)
	local tab = "featured"
	local expanded: { [string]: boolean } = {}

	local tabs = Panel.list("Tabs")
	tabs.Size = UDim2.new(1, 0, 0, 48)
	tabs.ScrollingEnabled = false
	(tabs:FindFirstChildOfClass("UIListLayout") :: UIListLayout).FillDirection = Enum.FillDirection.Horizontal
	tabs.Parent = panel.body
	local list = Panel.list("Content")
	list.Position = UDim2.fromOffset(0, 54)
	list.Size = UDim2.new(1, 0, 1, -54)
	list.Parent = panel.body

	local noyauxLabel = Panel.label("", 16, Theme.magenta)
	noyauxLabel.Size = UDim2.fromOffset(240, 44)
	noyauxLabel.Font = Theme.fontNumbers
	noyauxLabel.Parent = panel.footer
	local countdown: TextLabel? = nil
	local render_: (view: Types.ProfileView) -> ()

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local function card(height: number, rarity: string?): Frame
		local color = if rarity then BazaarScreen.rarityColor(rarity) else Theme.magenta
		return Create("Frame", {
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, -8, 0, height),
			BackgroundColor3 = Theme.panel,
			BackgroundTransparency = 0.1,
			Parent = list,
		}, {
			Stroke = Create("UIStroke", { Color = color, Thickness = 2, Transparency = 0.2 }),
		})
	end

	local function text(parent_: Instance, value: string, position: UDim2, size: UDim2, options: { [string]: any }?)
		local label = Create("TextLabel", {
			Position = position,
			Size = size,
			BackgroundTransparency = 1,
			Font = Theme.fontText,
			TextSize = 15,
			TextColor3 = Theme.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			Text = value,
			Parent = parent_,
		})
		if options then
			for key, option in options do
				(label :: any)[key] = option
			end
		end
		return label
	end

	local function renderFeatured(view: Types.ProfileView)
		countdown = text(list, "", UDim2.new(), UDim2.new(1, -8, 0, 30), {
			LayoutOrder = nextOrder(),
			Font = Theme.fontNumbers,
			TextSize = 18,
			TextColor3 = Theme.magenta,
		})
		for _, cosmeticId in Shop.rotation(Shop.dayIndex(os.time())) do
			local def = Config.Cosmetics.byId[cosmeticId]
			local owned = view.cosmeticsOwned[cosmeticId] == true
			local price = Shop.directPrice(cosmeticId) or 0
			local frame = card(120, def.rarity)
			local viewport = preview(def, UDim2.fromOffset(108, 108), true)
			viewport.Position = UDim2.fromOffset(6, 6)
			viewport.Parent = frame
			text(frame, BazaarScreen.cosmeticName(t, cosmeticId), UDim2.fromOffset(124, 8), UDim2.new(1, -310, 0, 44), {
				Font = Theme.fontTitle,
				TextSize = 18,
			})
			text(frame, t("rarity." .. def.rarity), UDim2.fromOffset(124, 56), UDim2.new(0, 200, 0, 22), {
				TextColor3 = BazaarScreen.rarityColor(def.rarity),
				Font = Theme.fontTitle,
			})
			local button = Panel.button(
				if owned then "✔ " .. t("shop.owned") else t("shop.buyNoyaux", { noyaux = price }),
				if owned then Theme.textDim elseif view.noyaux >= price then Theme.magenta else Theme.textDim,
				180
			)
			button.AnchorPoint = Vector2.new(1, 0.5)
			button.Position = UDim2.new(1, -10, 0.5, 0)
			button.Parent = frame
			button.Activated:Connect(function()
				if not owned then
					hooks.buy(cosmeticId)
				end
			end)
		end
	end

	local function renderCrates(view: Types.ProfileView)
		if Players.LocalPlayer:GetAttribute("PaidRandomItemsRestricted") ~= false then
			text(list, t("shop.cratesRestricted"), UDim2.new(), UDim2.new(1, -8, 0, 60), {
				LayoutOrder = nextOrder(),
				TextColor3 = Theme.textDim,
			})
			return
		end
		-- Ce que contient une caisse, dit clairement avant tout achat.
		text(list, t("shop.cratesSkinsOnly"), UDim2.new(), UDim2.new(1, -8, 0, 0), {
			LayoutOrder = nextOrder(),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextColor3 = Theme.cyan,
			TextSize = 14,
		})
		local crateIds: { string } = {}
		for crateId in M.crates :: { [string]: any } do
			table.insert(crateIds, crateId)
		end
		table.sort(crateIds, function(a, b)
			return M.crates[a].price < M.crates[b].price
		end)
		for _, crateId in crateIds do
			local crate = M.crates[crateId]
			local pity = view.pity[crateId] or 0
			local odds = Shop.displayHundredths(Shop.effectiveOdds(crateId, pity))
			local frame = card(210, crate.pity.minRarity)
			text(frame, t("cosmeticCrate." .. crateId), UDim2.fromOffset(12, 8), UDim2.new(0.6, 0, 0, 28), {
				Font = Theme.fontTitle,
				TextSize = 20,
			})
			-- Probabilités réelles (somme 100 %), recalculées si la garantie s'applique.
			for index, rarity in M.rarities do
				text(
					frame,
					`{t("rarity." .. rarity)} : {formatPercent(odds[rarity])}`,
					UDim2.fromOffset(12, 36 + (index - 1) * 22),
					UDim2.new(0.5, 0, 0, 22),
					{
						TextColor3 = BazaarScreen.rarityColor(rarity),
						Font = Theme.fontNumbers,
					}
				)
			end
			local guarantee = if Shop.guaranteeNext(crateId, pity)
				then t("shop.guaranteeNext", { rarity = t("rarity." .. crate.pity.minRarity) })
				else t("shop.guaranteeIn", {
					rarity = t("rarity." .. crate.pity.minRarity),
					count = Shop.untilGuarantee(crateId, pity),
				})
			text(frame, guarantee, UDim2.fromOffset(12, 150), UDim2.new(0.6, 0, 0, 44), { TextColor3 = Theme.orange })
			text(frame, t("shop.duplicateRule"), UDim2.new(0.55, 0, 0, 40), UDim2.new(0.45, -12, 0, 60), {
				TextColor3 = Theme.textDim,
				TextSize = 13,
			})
			local open = Panel.button(
				t("shop.openCrate", { noyaux = crate.price }),
				if view.noyaux >= crate.price then Theme.magenta else Theme.textDim,
				200
			)
			open.AnchorPoint = Vector2.new(1, 0)
			open.Position = UDim2.new(1, -10, 0, 8)
			open.Parent = frame
			open.Activated:Connect(function()
				hooks.openCrate(crateId)
			end)
			local contents = Panel.button(t("shop.contents"), Theme.cyan, 200)
			contents.AnchorPoint = Vector2.new(1, 1)
			contents.Position = UDim2.new(1, -10, 1, -10)
			contents.Parent = frame
			contents.Activated:Connect(function()
				expanded[crateId] = not expanded[crateId]
				render_(view)
			end)
			if expanded[crateId] then
				for _, rarity in M.rarities do
					if crate.odds[rarity] > 0 then
						local names = {}
						for _, id in Shop.cosmeticsOfRarity(rarity) do
							table.insert(names, BazaarScreen.cosmeticName(t, id))
						end
						text(
							list,
							`{t("rarity." .. rarity)} : {table.concat(names, ", ")}`,
							UDim2.new(),
							UDim2.new(1, -8, 0, 0),
							{
								LayoutOrder = nextOrder(),
								AutomaticSize = Enum.AutomaticSize.Y,
								TextColor3 = BazaarScreen.rarityColor(rarity),
								TextSize = 13,
							}
						)
					end
				end
			end
		end
	end

	local function renderNoyaux(view: Types.ProfileView)
		local packIds: { string } = {}
		for packId in M.noyauxPacks :: { [string]: any } do
			table.insert(packIds, packId)
		end
		table.sort(packIds, function(a, b)
			return M.noyauxPacks[a].order < M.noyauxPacks[b].order
		end)
		for _, packId in packIds do
			local pack = M.noyauxPacks[packId]
			local frame = card(70)
			text(frame, t("shop.pack", { noyaux = pack.noyaux }), UDim2.fromOffset(12, 0), UDim2.new(0.6, 0, 1, 0), {
				Font = Theme.fontTitle,
				TextSize = 20,
				TextColor3 = Theme.magenta,
			})
			local button = Panel.button(t("shop.robux", { robux = pack.robux }), Theme.green, 160)
			button.AnchorPoint = Vector2.new(1, 0.5)
			button.Position = UDim2.new(1, -10, 0.5, 0)
			button.Parent = frame
			button.Activated:Connect(function()
				hooks.buyPack(packId)
			end)
		end
		local frame = card(70)
		text(frame, t("shop.vaultExtension"), UDim2.fromOffset(12, 0), UDim2.new(0.6, 0, 1, 0), {
			Font = Theme.fontTitle,
			TextSize = 18,
		})
		local owned = view.hasVaultExtension
		local button = Panel.button(
			if owned then "✔ " .. t("shop.owned") else t("shop.robux", { robux = M.vaultExtension.robux }),
			if owned then Theme.textDim else Theme.green,
			160
		)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -10, 0.5, 0)
		button.Parent = frame
		button.Activated:Connect(function()
			if not owned then
				hooks.buyVaultExtension()
			end
		end)
		text(list, t("shop.noyauxRule"), UDim2.new(), UDim2.new(1, -8, 0, 40), {
			LayoutOrder = nextOrder(),
			TextColor3 = Theme.textDim,
			TextSize = 13,
		})
	end

	local function renderCollection(view: Types.ProfileView)
		local owned = {}
		for _, id in Config.Cosmetics.list do
			if view.cosmeticsOwned[id] then
				table.insert(owned, id)
			end
		end
		if #owned == 0 then
			text(list, t("shop.collectionEmpty"), UDim2.new(), UDim2.new(1, -8, 0, 40), {
				LayoutOrder = nextOrder(),
				TextColor3 = Theme.textDim,
			})
			return
		end
		for _, cosmeticId in owned do
			local def = Config.Cosmetics.byId[cosmeticId]
			local slot = Shop.slotOf(cosmeticId) :: string
			local equipped = view.cosmeticsEquipped[slot] == cosmeticId
			local frame = card(70, def.rarity)
			local viewport = preview(def, UDim2.fromOffset(60, 60), false)
			viewport.Position = UDim2.fromOffset(5, 5)
			viewport.Parent = frame
			text(frame, BazaarScreen.cosmeticName(t, cosmeticId), UDim2.fromOffset(74, 6), UDim2.new(1, -260, 0, 30), {
				Font = Theme.fontTitle,
			})
			text(frame, t("rarity." .. def.rarity), UDim2.fromOffset(74, 38), UDim2.new(0, 110, 0, 22), {
				TextColor3 = BazaarScreen.rarityColor(def.rarity),
			})
			-- Le skin ne se voit que sur l'objet qu'il habille : le rappeler.
			local status = BazaarScreen.skinStatus(view, cosmeticId)
			if status then
				text(frame, t("shop.status." .. status), UDim2.fromOffset(188, 38), UDim2.new(1, -370, 0, 22), {
					TextColor3 = if status == "missing" then Theme.orange else Theme.textDim,
					TextSize = 13,
				})
			end
			local button = Panel.button(
				if equipped then t("shop.unequip") else t("shop.equip"),
				if equipped then Theme.green else Theme.cyan,
				160
			)
			button.AnchorPoint = Vector2.new(1, 0.5)
			button.Position = UDim2.new(1, -10, 0.5, 0)
			button.Parent = frame
			button.Activated:Connect(function()
				hooks.equip(slot, if equipped then nil else cosmeticId)
			end)
		end
	end

	function render_(view: Types.ProfileView)
		panel.title.Text = t("station.bazaar")
		noyauxLabel.Text = t("topbar.noyaux", { noyaux = view.noyaux })
		Panel.clear(tabs)
		Panel.clear(list)
		order = 0
		countdown = nil
		for index, key in TABS do
			local button = Panel.button(t("shop.tab." .. key), if tab == key then Theme.magenta else Theme.textDim, 170)
			button.LayoutOrder = index
			button.Parent = tabs
			button.Activated:Connect(function()
				tab = key
				render_(view)
			end)
		end
		if tab == "featured" then
			renderFeatured(view)
		elseif tab == "crates" then
			renderCrates(view)
		elseif tab == "noyaux" then
			renderNoyaux(view)
		else
			renderCollection(view)
		end
	end

	-- Vrai compte à rebours jusqu'au renouvellement (00:00 UTC).
	RunService.Heartbeat:Connect(function()
		local label = countdown
		if label == nil or not panel:isOpen() then
			return
		end
		local remaining = math.max(0, Shop.nextRotationAt(os.time()) - os.time())
		label.Text = t("shop.rotation", {
			time = string.format(
				"%02d:%02d:%02d",
				math.floor(remaining / 3600),
				math.floor(remaining / 60) % 60,
				remaining % 60
			),
		})
	end)

	return { panel = panel, render = render_ }
end

return BazaarScreen
