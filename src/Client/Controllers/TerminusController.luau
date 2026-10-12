--!strict
--[[
	TerminusController : le hub (section 17.3, écrans 3 à 9).

	- Barre du haut : pseudo, niveau, rang, crédits, Noyaux (+ vers la boutique),
	  caisse gratuite (minuteur et badge « 1 » / « 2 »).
	- Stations (invites avec l'attribut Station) → écrans : Coffre, Marchand,
	  Armurier, Assureur. Holo-Bazar (P9), Porte de déploiement (P6), Stand de
	  tir et Mur des Légendes (P10) arrivent dans leurs phases.
	- Menu rapide (mobile, manette) : accès à tous les lieux sans se déplacer.
	- L'écran de tri s'ouvre automatiquement quand du loot attend d'être trié.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
local Panel = require(script.Parent.Parent.UI.Panel)
local Theme = require(script.Parent.Parent.UI.Theme)
local ArmorerScreen = require(script.Parent.Parent.Screens.ArmorerScreen)
local InsurerScreen = require(script.Parent.Parent.Screens.InsurerScreen)
local MerchantScreen = require(script.Parent.Parent.Screens.MerchantScreen)
local SortScreen = require(script.Parent.Parent.Screens.SortScreen)
local VaultScreen = require(script.Parent.Parent.Screens.VaultScreen)
local HUDController = require(script.Parent.HUDController)
local MatchHUDController = require(script.Parent.MatchHUDController)
local NotificationController = require(script.Parent.NotificationController)
local ProfileController = require(script.Parent.ProfileController)

local TerminusController = {}

-- (station) : une station sans écran propre a été ouverte (Porte de déploiement…).
TerminusController.StationOpened = Signal.new() :: Signal.Signal<string>

local player = Players.LocalPlayer
local t = ProfileController.t

type Screen = { panel: Panel.Panel, render: (view: Types.ProfileView) -> () }
local screens: { [string]: Screen } = {}
local topBar: Frame
local labels: { [string]: TextLabel } = {}
local crateButton: TextButton
local quickMenu: Panel.Panel
local sortDismissed = false

local function inMatch(): boolean
	local status = MatchHUDController.status()
	return status == "alive" or status == "orb"
end

function TerminusController.open(station: string)
	if inMatch() then
		return
	end
	local screen = screens[station]
	local view = ProfileController.get()
	if screen and view then
		for key, other in screens do
			if key ~= station then
				other.panel:close()
			end
		end
		screen.render(view)
		screen.panel:open()
	else
		TerminusController.StationOpened:Fire(station)
		NotificationController.show(t("station.soon"), Theme.textDim)
	end
end

local function renderOpen(view: Types.ProfileView)
	for _, screen in screens do
		if screen.panel:isOpen() then
			screen.render(view)
		end
	end
end

local function renderTopBar(view: Types.ProfileView)
	labels.name.Text = player.DisplayName
	labels.level.Text = t("common.level", { level = view.level })
	labels.rank.Text = t("rank." .. view.rank)
	labels.credits.Text = t("topbar.credits", { credits = view.credits })
	labels.noyaux.Text = t("topbar.noyaux", { noyaux = view.noyaux })
end

-- Minuteur de la caisse gratuite (mis à jour chaque image).
local function renderCrate()
	local view = ProfileController.get()
	if view == nil then
		return
	end
	local stored = view.freeCrate.stored
	local nextGrant = view.freeCrate.nextGrantUnix
	local text: string
	if stored > 0 then
		text = t("freecrate.ready", { count = stored })
	elseif nextGrant then
		local remaining = math.max(0, nextGrant - os.time())
		local minutes = math.floor(remaining / 60)
		text = t("freecrate.timer", { time = string.format("%02d:%02d", minutes, remaining % 60) })
	else
		text = t("freecrate.title")
	end
	crateButton.Text = text
	crateButton.TextColor3 = if stored > 0 then Theme.green else Theme.textDim
end

local function showCrateResult(reward: { [string]: any })
	local text: string
	if reward.kind == "credits" then
		text = t("freecrate.credits", { credits = reward.amount })
	elseif reward.kind == "item" and type(reward.item) == "table" then
		text = t("freecrate.item", { item = t("item." .. tostring(reward.item.itemId)) })
	else
		return
	end
	NotificationController.show(text, Theme.green)
end

local function buildTopBar(root: Instance)
	local function label(name: string, order: number, color: Color3, font: EnumItem?): TextLabel
		local l = Create("TextLabel", {
			LayoutOrder = order,
			Size = UDim2.fromOffset(0, 36),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Font = font or Theme.fontText,
			TextSize = 16,
			TextColor3 = color,
			Text = "",
		}, {
			Padding = Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
		})
		labels[name] = l
		return l
	end
	topBar = Create("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = Theme.panelTransparency,
		Parent = root,
	}, {
		Layout = Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Stroke = Create("UIStroke", { Color = Theme.cyan, Transparency = 0.6 }),
	})
	label("name", 1, Theme.text, Theme.fontTitle).Parent = topBar
	label("level", 2, Theme.cyan).Parent = topBar
	label("rank", 3, Theme.orange).Parent = topBar
	label("credits", 4, Theme.text, Theme.fontNumbers).Parent = topBar
	label("noyaux", 5, Theme.magenta, Theme.fontNumbers).Parent = topBar
	-- « + » vers la boutique (Holo-Bazar).
	local plus = Panel.button("+", Theme.magenta, 44)
	plus.LayoutOrder = 6
	plus.Parent = topBar
	plus.Activated:Connect(function()
		TerminusController.open("bazaar")
	end)
	crateButton = Panel.button("", Theme.green, 170)
	crateButton.LayoutOrder = 7
	crateButton.Parent = topBar
	crateButton.Activated:Connect(function()
		ClientNet.fire("OpenFreeCrate")
	end)
	local menu = Panel.button("☰", Theme.cyan, 44)
	menu.LayoutOrder = 8
	menu.Parent = topBar
	menu.Activated:Connect(function()
		if quickMenu:isOpen() then
			quickMenu:close()
		else
			quickMenu:open()
		end
	end)
end

local QUICK_STATIONS = { "vault", "merchant", "armorer", "insurer", "bazaar", "deploy", "range", "legends" }

local function buildQuickMenu(root: Instance)
	quickMenu = Panel.create("QuickMenu", root, Theme.cyan)
	quickMenu.frame.Size = UDim2.fromScale(0.5, 0.7)
	local grid = Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = quickMenu.body,
	}, {
		Grid = Create("UIGridLayout", {
			CellSize = UDim2.new(0.5, -6, 0, 52),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for index, station in QUICK_STATIONS do
		local button = Panel.button("", Theme.cyan)
		button.Name = station
		button.LayoutOrder = index
		button.Parent = grid
		button.Activated:Connect(function()
			quickMenu:close()
			TerminusController.open(station)
		end)
	end
	quickMenu.onClosed = nil
	local function relabel()
		quickMenu.title.Text = t("quickmenu.title")
		for _, child in grid:GetChildren() do
			if child:IsA("TextButton") then
				child.Text = t("station." .. child.Name)
			end
		end
	end
	relabel()
	ProfileController.Changed:Connect(relabel)
end

function TerminusController.init() end

function TerminusController.start()
	local root = HUDController.root()
	buildTopBar(root)
	buildQuickMenu(root)
	screens.vault = VaultScreen.create(root, t)
	screens.merchant = MerchantScreen.create(root, t)
	screens.armorer = ArmorerScreen.create(root, t)
	screens.insurer = InsurerScreen.create(root, t)
	screens.sort = SortScreen.create(root, t)
	screens.sort.panel.onClosed = function()
		sortDismissed = true
	end

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local station = prompt:GetAttribute("Station")
		if type(station) == "string" and station ~= "training" and station ~= "hub" then
			TerminusController.open(station)
		end
	end)

	ProfileController.Changed:Connect(function(view)
		renderTopBar(view)
		renderOpen(view)
		-- Loot à trier : écran de tri automatique au retour au Terminus.
		if #view.pendingLoot > 0 and not inMatch() and not screens.sort.panel:isOpen() and not sortDismissed then
			TerminusController.open("sort")
		elseif #view.pendingLoot == 0 then
			sortDismissed = false
			screens.sort.panel:close()
		end
	end)
	ClientNet.on("FreeCrateResult", showCrateResult)

	MatchHUDController.StatusChanged:Connect(function(status)
		topBar.Visible = not (status == "alive" or status == "orb")
		if status == "alive" then
			for _, screen in screens do
				screen.panel:close()
			end
			quickMenu:close()
		end
		sortDismissed = false
	end)

	local view = ProfileController.get()
	if view then
		renderTopBar(view)
	end
	RunService.RenderStepped:Connect(renderCrate)
end

-- Ajoute l'écran d'une station (Porte de déploiement en P6, Holo-Bazar en P9…).
function TerminusController.register(station: string, screen: Screen)
	screens[station] = screen
end

return TerminusController
