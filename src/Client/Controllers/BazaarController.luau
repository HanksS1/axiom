--!strict
--[[
	BazaarController : Holo-Bazar (station « bazaar », bouton « + » des Noyaux)
	et ouverture des caisses cosmétiques (section 14.10).

	Ouverture d'une caisse (UI/CrateScene, en 3D) : des lasers assemblent la
	caisse en pixels de plus en plus fins, un scanner la balaie, elle s'ouvre
	et l'objet obtenu en sort pour flotter au-dessus, la caisse restant
	visible. Le bouton « Passer » est TOUJOURS disponible, et le paramètre
	« ouverture rapide » montre directement la caisse ouverte.

	Ce que contient une caisse : un SKIN (une apparence), jamais une arme. Il
	rejoint la Collection du joueur (onglet Collection), ne prend aucune
	place dans le coffre, et peut être équipé tout de suite.

	Les achats en Robux passent uniquement par MarketplaceService (fenêtre
	officielle de Roblox, ouverte seulement à la demande du joueur).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Shop = require(Shared.Monetization.Shop)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
local CrateScene = require(script.Parent.Parent.UI.CrateScene)
local Panel = require(script.Parent.Parent.UI.Panel)
local PanelState = require(script.Parent.Parent.UI.PanelState)
local Theme = require(script.Parent.Parent.UI.Theme)
local BazaarScreen = require(script.Parent.Parent.Screens.BazaarScreen)
local HUDController = require(script.Parent.HUDController)
local NotificationController = require(script.Parent.NotificationController)
local ProfileController = require(script.Parent.ProfileController)
local TerminusController = require(script.Parent.TerminusController)

local BazaarController = {}

local player = Players.LocalPlayer
local t = ProfileController.t
local M = Config.Monetization

local screen: BazaarScreen.Screen
local overlay: Frame
local stage: Frame
local flash: Frame
local resultName: TextLabel
local resultRarity: TextLabel
local resultExtra: TextLabel
local skipButton: TextButton
local equipButton: TextButton
local closeButton: TextButton
local scene: CrateScene.Scene? = nil
local current: { [string]: any }? = nil -- résultat de la caisse affichée

local function clearScene()
	if scene then
		scene.destroy()
		scene = nil
	end
end

local function close()
	clearScene()
	current = nil
	overlay.Visible = false
	PanelState.set("crateOpening", false)
end

local function buildOverlay(root: Instance)
	-- Scène 3D : carrée, au-dessus des textes, quelle que soit la forme de l'écran.
	stage = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.33),
		Size = UDim2.fromScale(0.56, 0.56),
		BackgroundTransparency = 1,
		ZIndex = 1,
	}, {
		Ratio = Create("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }),
		Limit = Create("UISizeConstraint", { MaxSize = Vector2.new(560, 560) }),
	})
	flash = Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
	})
	local function label(y: number, size: number): TextLabel
		return Create("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.62, y),
			Size = UDim2.new(0.9, 0, 0, size + 8),
			BackgroundTransparency = 1,
			Font = Theme.fontTitle,
			TextSize = size,
			TextColor3 = Theme.text,
			TextWrapped = true,
			Text = "",
			ZIndex = 3,
		})
	end
	resultName = label(0, 26)
	resultRarity = label(38, 20)
	resultExtra = label(68, 15)
	resultExtra.Font = Theme.fontText
	resultExtra.TextColor3 = Theme.textDim
	resultExtra.Size = UDim2.new(0.9, 0, 0, 44)
	skipButton = Panel.button("", Theme.textDim, 140)
	skipButton.AnchorPoint = Vector2.new(1, 1)
	skipButton.Position = UDim2.new(1, -16, 1, -16)
	skipButton.ZIndex = 4
	equipButton = Panel.button("", Theme.magenta, 200)
	equipButton.AnchorPoint = Vector2.new(1, 1)
	equipButton.Position = UDim2.new(0.5, -8, 1, -16)
	equipButton.ZIndex = 4
	closeButton = Panel.button("", Theme.green, 200)
	closeButton.AnchorPoint = Vector2.new(0, 1)
	closeButton.Position = UDim2.new(0.5, 8, 1, -16)
	closeButton.ZIndex = 4
	overlay = Create("Frame", {
		Name = "CrateOpening",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(4, 5, 8),
		BackgroundTransparency = 0.12,
		Visible = false,
		ZIndex = 60,
		Parent = root,
	}, {
		Stage = stage,
		Flash = flash,
		Name_ = resultName,
		Rarity = resultRarity,
		Extra = resultExtra,
		Skip = skipButton,
		Equip = equipButton,
		Close = closeButton,
	})
	closeButton.Activated:Connect(close)
	skipButton.Activated:Connect(function()
		if scene then
			scene.skip()
		end
	end)
	-- Équiper tout de suite le skin obtenu.
	equipButton.Activated:Connect(function()
		local result = current
		local slot = if result then Shop.slotOf(result.cosmeticId) else nil
		if result == nil or slot == nil then
			return
		end
		ClientNet.fire("EquipCosmetic", slot, result.cosmeticId)
		equipButton.Text = "✔ " .. t("shop.equippedNow")
		equipButton.Active = false
		equipButton.AutoButtonColor = false
	end)
end

-- Ce que le skin habille : l'arme ciblée, ou le sac / le casque / le gilet.
local function targetName(cosmeticId: string): string
	local def = Config.Cosmetics.byId[cosmeticId]
	if def == nil then
		return ""
	end
	return if def.category == "weapon" then t("item." .. def.target) else t("cosmetic.slot." .. def.category)
end

-- Révélation : nom, rareté, où va l'objet, boutons.
local function reveal(result: { [string]: any })
	local rarityColor = BazaarScreen.rarityColor(result.rarity)
	resultName.Text = BazaarScreen.cosmeticName(t, result.cosmeticId)
	resultRarity.Text = t("rarity." .. result.rarity)
	resultRarity.TextColor3 = rarityColor
	resultExtra.Text = if result.duplicate
		then t("shop.duplicate", { noyaux = result.refund })
		else t("shop.addedToCollection", { target = targetName(result.cosmeticId) })
	skipButton.Visible = false
	local view = ProfileController.get()
	local slot = Shop.slotOf(result.cosmeticId)
	local equipped = view ~= nil and slot ~= nil and view.cosmeticsEquipped[slot] == result.cosmeticId
	equipButton.Text = if equipped then "✔ " .. t("shop.equippedNow") else t("shop.equipNow")
	equipButton.Active = not equipped
	equipButton.AutoButtonColor = not equipped
	equipButton.Visible = slot ~= nil
	closeButton.Text = t("common.confirm")
	closeButton.Visible = true
end

-- Ouverture : la caisse se construit, est scannée, s'ouvre ; l'objet en sort.
local function play(result: { [string]: any })
	clearScene()
	current = result
	overlay.Visible = true
	PanelState.set("crateOpening", true)
	resultName.Text, resultRarity.Text, resultExtra.Text = "", "", ""
	equipButton.Visible = false
	closeButton.Visible = false
	skipButton.Text = t("shop.skip")
	skipButton.Visible = true
	flash.BackgroundTransparency = 1

	local def = Config.Cosmetics.byId[result.cosmeticId]
	local rarityColor = BazaarScreen.rarityColor(result.rarity)
	local view = ProfileController.get()
	local instant = view ~= nil and view.settings.skipCrateAnimation == true
	scene = CrateScene.play(stage, BazaarScreen.previewItem(def), def, rarityColor, {
		-- Explosion de lumière à la couleur de la rareté quand le couvercle saute.
		onOpen = function()
			if instant then
				return
			end
			flash.BackgroundColor3 = rarityColor
			flash.BackgroundTransparency = 0.25
			TweenService:Create(flash, TweenInfo.new(0.7), { BackgroundTransparency = 1 }):Play()
		end,
		onReveal = function()
			if current == result then
				reveal(result)
			end
		end,
	}, instant)
end

function BazaarController.init() end

function BazaarController.start()
	local root = HUDController.root()
	screen = BazaarScreen.create(root, t, {
		buy = function(cosmeticId)
			ClientNet.fire("BazaarBuy", cosmeticId)
		end,
		openCrate = function(crateId)
			ClientNet.fire("CosmeticCrateOpen", crateId)
		end,
		equip = function(slot, cosmeticId)
			ClientNet.fire("EquipCosmetic", slot, cosmeticId)
		end,
		buyPack = function(packId)
			local pack = M.noyauxPacks[packId]
			if pack == nil or pack.productId == 0 then
				NotificationController.show(t("shop.unavailable"), Theme.textDim)
				return
			end
			MarketplaceService:PromptProductPurchase(player, pack.productId)
		end,
		buyVaultExtension = function()
			local gamePassId = M.vaultExtension.gamePassId
			if gamePassId == 0 then
				NotificationController.show(t("shop.unavailable"), Theme.textDim)
				return
			end
			MarketplaceService:PromptGamePassPurchase(player, gamePassId)
		end,
	})
	TerminusController.register("bazaar", screen)
	buildOverlay(root)

	ClientNet.on("CosmeticCrateResult", function(result: any)
		if
			type(result) == "table"
			and type(result.cosmeticId) == "string"
			and Config.Cosmetics.byId[result.cosmeticId] ~= nil
			and type(result.rarity) == "string"
		then
			play(result)
		end
	end)
	-- Les caisses apparaissent / disparaissent selon PolicyService.
	player:GetAttributeChangedSignal("PaidRandomItemsRestricted"):Connect(function()
		local view = ProfileController.get()
		if view and screen.panel:isOpen() then
			screen.render(view)
		end
	end)
end

return BazaarController
