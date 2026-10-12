--!strict
--[[
	BazaarController : Holo-Bazar (station « bazaar », bouton « + » des Noyaux)
	et ouverture des caisses cosmétiques (section 14.10).

	Animation d'ouverture : dépressurisation, scan laser, explosion de
	lumière à la couleur de la rareté, puis révélation. Le bouton « Passer »
	est TOUJOURS disponible, et le paramètre « ouverture rapide » la saute.

	Les achats en Robux passent uniquement par MarketplaceService (fenêtre
	officielle de Roblox, ouverte seulement à la demande du joueur).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
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
local box: Frame
local laser: Frame
local flash: Frame
local resultName: TextLabel
local resultRarity: TextLabel
local resultExtra: TextLabel
local skipButton: TextButton
local closeButton: TextButton
local playToken = 0

local function buildOverlay(root: Instance)
	box = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(150, 120),
		BackgroundColor3 = Color3.fromRGB(30, 32, 40),
	}, {
		Stroke = Create("UIStroke", { Color = Theme.magenta, Thickness = 3 }),
	})
	laser = Create("Frame", {
		Size = UDim2.new(1.2, 0, 0, 3),
		Position = UDim2.fromScale(-0.1, 0),
		BackgroundColor3 = Theme.red,
		BorderSizePixel = 0,
		Visible = false,
		Parent = box,
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
			Position = UDim2.new(0.5, 0, 0.6, y),
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
	resultRarity = label(40, 20)
	resultExtra = label(72, 16)
	skipButton = Panel.button("", Theme.textDim, 140)
	skipButton.AnchorPoint = Vector2.new(1, 1)
	skipButton.Position = UDim2.new(1, -16, 1, -16)
	skipButton.ZIndex = 4
	closeButton = Panel.button("", Theme.green, 180)
	closeButton.AnchorPoint = Vector2.new(0.5, 1)
	closeButton.Position = UDim2.new(0.5, 0, 1, -16)
	closeButton.ZIndex = 4
	overlay = Create("Frame", {
		Name = "CrateOpening",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(4, 5, 8),
		BackgroundTransparency = 0.15,
		Visible = false,
		ZIndex = 60,
		Parent = root,
	}, {
		Box = box,
		Flash = flash,
		Name_ = resultName,
		Rarity = resultRarity,
		Extra = resultExtra,
		Skip = skipButton,
		Close = closeButton,
	})
	closeButton.Activated:Connect(function()
		playToken += 1
		overlay.Visible = false
		PanelState.set("crateOpening", false)
	end)
end

local function reveal(result: { [string]: any })
	local rarityColor = BazaarScreen.rarityColor(result.rarity)
	laser.Visible = false
	box.Rotation = 0
	box.Visible = false
	flash.BackgroundTransparency = 1
	resultName.Text = BazaarScreen.cosmeticName(t, result.cosmeticId)
	resultRarity.Text = t("rarity." .. result.rarity)
	resultRarity.TextColor3 = rarityColor
	resultExtra.Text = if result.duplicate then t("shop.duplicate", { noyaux = result.refund }) else ""
	skipButton.Visible = false
	closeButton.Text = t("common.confirm")
	closeButton.Visible = true
end

local function steam()
	for _ = 1, 12 do
		local puff = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(18, 18),
			BackgroundColor3 = Color3.fromRGB(220, 230, 240),
			BackgroundTransparency = 0.3,
			ZIndex = 1,
			Parent = box,
		}, { Corner = Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		local angle = math.random() * math.pi * 2
		local tween = TweenService:Create(puff, TweenInfo.new(0.9), {
			Position = UDim2.new(0.5, math.cos(angle) * 130, 0.5, math.sin(angle) * 90),
			Size = UDim2.fromOffset(46, 46),
			BackgroundTransparency = 1,
		})
		tween.Completed:Once(function()
			puff:Destroy()
		end)
		tween:Play()
	end
end

-- Ouverture : dépressurisation → scan laser → éclair → révélation.
local function play(result: { [string]: any })
	playToken += 1
	local token = playToken
	overlay.Visible = true
	PanelState.set("crateOpening", true)
	resultName.Text, resultRarity.Text, resultExtra.Text = "", "", ""
	closeButton.Visible = false
	box.Visible = true
	box.Rotation = 0
	skipButton.Text = t("shop.skip")
	skipButton.Visible = true
	local view = ProfileController.get()
	if view and view.settings.skipCrateAnimation == true then
		reveal(result)
		return
	end
	local function alive(): boolean
		return playToken == token
	end
	task.spawn(function()
		-- Dépressurisation.
		steam()
		local started = os.clock()
		while alive() and os.clock() - started < 0.9 do
			box.Rotation = math.sin(os.clock() * 45) * 5
			task.wait()
		end
		box.Rotation = 0
		-- Scan laser.
		laser.Visible = true
		for _ = 1, 2 do
			if not alive() then
				return
			end
			laser.Position = UDim2.fromScale(-0.1, 0)
			local tween = TweenService:Create(laser, TweenInfo.new(0.45), { Position = UDim2.fromScale(-0.1, 1) })
			tween:Play()
			tween.Completed:Wait()
		end
		laser.Visible = false
		if not alive() then
			return
		end
		-- Explosion de lumière à la couleur de la rareté.
		flash.BackgroundColor3 = BazaarScreen.rarityColor(result.rarity)
		flash.BackgroundTransparency = 0
		TweenService:Create(flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
		task.wait(0.25)
		if alive() then
			reveal(result)
		end
	end)
	local skipConnection: RBXScriptConnection
	skipConnection = skipButton.Activated:Connect(function()
		skipConnection:Disconnect()
		if alive() then
			playToken += 1
			reveal(result)
		end
	end)
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
		if type(result) == "table" and type(result.cosmeticId) == "string" and type(result.rarity) == "string" then
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
