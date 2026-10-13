--!strict
--[[
	DevPanelController : panneau de test (Studio uniquement) pour valider
	la phase P0 : profil créé, modifié, sauvegardé et rechargé sans perte.
	Sera remplacé par l'interface définitive (phase P8).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemRules = require(Shared.Items.ItemRules)
local Types = require(Shared.Types)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local CameraController = require(script.Parent.CameraController)
local ProfileController = require(script.Parent.ProfileController)

local DevPanelController = {}

local CYAN = Color3.fromRGB(0, 229, 255)
local PANEL = Color3.fromRGB(18, 22, 30)

local labels: { [string]: TextLabel } = {}
local buttonKeys: { [TextButton]: string } = {}

local function makeLabel(parent: Instance, name: string, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, 20)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = 14
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Text = ""
	label.Parent = parent
	labels[name] = label
	return label
end

local function makeButton(parent: Instance, textKey: string, order: number, onClick: () -> ())
	local button = Instance.new("TextButton")
	button.LayoutOrder = order
	button.BackgroundColor3 = Color3.fromRGB(30, 38, 52)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.Code
	button.TextSize = 14
	button.TextColor3 = CYAN
	button.Text = ProfileController.t(textKey)
	button.Parent = parent
	buttonKeys[button] = textKey
	button.Activated:Connect(onClick)
end

local function render(view: Types.ProfileView)
	local t = ProfileController.t
	labels.Title.Text = t("dev.panelTitle")
	labels.Profile.Text = t("dev.profileState", {
		level = view.level,
		xp = view.xp,
		credits = view.credits,
		noyaux = view.noyaux,
	})
	labels.Vault.Text = t("dev.vaultState", {
		used = ItemRules.totalUp(view.vault),
		capacity = view.vaultCapacity,
		count = #view.vault,
	})
	labels.Hint.Text = t("dev.mouseHint")
	labels.Loadout.Text = t("dev.loadoutState", {
		score = ItemRules.equipmentScore(view.loadout, view.bag),
	})
	for button, key in buttonKeys do
		button.Text = t(key)
	end
end

function DevPanelController.init() end

function DevPanelController.start()
	if not RunService:IsStudio() then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "DevPanel"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -8, 0, 8)
	frame.Size = UDim2.fromOffset(320, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = CYAN
	stroke.Transparency = 0.4
	stroke.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = frame

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 4)
	list.Parent = frame

	makeLabel(frame, "Title", 1).TextColor3 = CYAN
	makeLabel(frame, "Profile", 2)
	makeLabel(frame, "Vault", 3)
	makeLabel(frame, "Loadout", 4)
	makeLabel(frame, "Hint", 6).TextColor3 = Color3.fromRGB(150, 158, 170)

	local buttons = Instance.new("Frame")
	buttons.LayoutOrder = 5
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, 0, 0, 0)
	buttons.AutomaticSize = Enum.AutomaticSize.Y
	buttons.Parent = frame
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -4, 0, 44) -- 44 px minimum (mobile)
	grid.CellPadding = UDim2.fromOffset(8, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = buttons

	makeButton(buttons, "dev.addCredits", 1, function()
		ClientNet.fire("DevCommand", "addCredits", 100)
	end)
	makeButton(buttons, "dev.addXp", 2, function()
		ClientNet.fire("DevCommand", "addXp", 500)
	end)
	makeButton(buttons, "dev.giveKit", 3, function()
		ClientNet.fire("DevCommand", "giveKit")
	end)
	makeButton(buttons, "dev.giveRandom", 4, function()
		ClientNet.fire("DevCommand", "giveRandom")
	end)
	makeButton(buttons, "dev.clearVault", 5, function()
		ClientNet.fire("DevCommand", "clearVault")
	end)
	makeButton(buttons, "dev.saveNow", 6, function()
		ClientNet.fire("DevCommand", "saveNow")
	end)
	makeButton(buttons, "dev.equipRifle", 8, function()
		ClientNet.fire("DevCommand", "equipRifle")
	end)
	makeButton(buttons, "dev.equipPistol", 9, function()
		ClientNet.fire("DevCommand", "equipPistol")
	end)
	makeButton(buttons, "dev.equipSpecial", 9, function()
		ClientNet.fire("DevCommand", "equipSpecial")
	end)
	makeButton(buttons, "dev.equipArmor", 10, function()
		ClientNet.fire("DevCommand", "equipArmor", 4)
	end)
	makeButton(buttons, "dev.respawn", 11, function()
		ClientNet.fire("DevCommand", "respawn")
	end)
	makeButton(buttons, "dev.startSolo", 12, function()
		ClientNet.fire("DevCommand", "startSolo", 1)
	end)
	makeButton(buttons, "dev.startDuo", 13, function()
		ClientNet.fire("DevCommand", "startDuo", 1)
	end)
	makeButton(buttons, "dev.skipTime", 14, function()
		ClientNet.fire("DevCommand", "skipTime", 120)
	end)
	makeButton(buttons, "dev.endMatch", 15, function()
		ClientNet.fire("DevCommand", "endMatch")
	end)
	makeButton(buttons, "dev.spawnRobots", 16, function()
		ClientNet.fire("DevCommand", "spawnRobots")
	end)
	makeButton(buttons, "dev.clearRobots", 17, function()
		ClientNet.fire("DevCommand", "clearRobots")
	end)
	makeButton(buttons, "dev.nextMap", 18, function()
		ClientNet.fire("DevCommand", "nextMap")
	end)
	makeButton(buttons, "dev.finishTutorial", 19, function()
		ClientNet.fire("DevCommand", "finishTutorial")
	end)
	makeButton(buttons, "dev.toggleLanguage", 7, function()
		local nextLanguage = if ProfileController.language() == "fr" then "en" else "fr"
		ProfileController.setSetting("language", nextLanguage)
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- [M] libère / reverrouille la souris pour cliquer sur le panneau.
	local mouseFree = false
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.KeyCode == Enum.KeyCode.M then
			mouseFree = not mouseFree
			CameraController.setMouseFree(mouseFree)
		end
	end)

	ProfileController.Changed:Connect(render)
	local view = ProfileController.get()
	if view then
		render(view)
	end
end

return DevPanelController
