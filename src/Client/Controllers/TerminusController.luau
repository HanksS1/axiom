--!strict
--[[
	TerminusController : le hub (section 17.3, écrans 3 à 9).

	- Barre du haut : pseudo, niveau, rang, crédits, Noyaux (+ vers la boutique),
	  caisse gratuite (minuteur et badge « 1 » / « 2 »).
	- Stations (invites avec l'attribut Station) → écrans : Coffre, Marchand,
	  Armurier, Assureur, Holo-Bazar (P9), Porte de déploiement (P6), Stand de
	  tir (P10). Le Mur des Légendes ouvre les classements du profil.
	- Menu rapide (mobile, manette) : accès à tous les lieux sans se déplacer.
	- L'écran de tri s'ouvre automatiquement quand du loot attend d'être trié.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
local ItemIcon = require(script.Parent.Parent.UI.ItemIcon)
local Panel = require(script.Parent.Parent.UI.Panel)
local PanelState = require(script.Parent.Parent.UI.PanelState)
local Theme = require(script.Parent.Parent.UI.Theme)
local ArmorerScreen = require(script.Parent.Parent.Screens.ArmorerScreen)
local InsurerScreen = require(script.Parent.Parent.Screens.InsurerScreen)
local MerchantScreen = require(script.Parent.Parent.Screens.MerchantScreen)
local ProfileScreen = require(script.Parent.Parent.Screens.ProfileScreen)
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
local sortButton: TextButton -- « Butin à trier (N) » : toujours un moyen de rouvrir le tri
local quickMenu: Panel.Panel
local sortDismissed = false
local profileScreen: ProfileScreen.Screen

local function inMatch(): boolean
	local status = MatchHUDController.status()
	return status == "alive" or status == "orb"
end

function TerminusController.open(station: string)
	if inMatch() then
		return
	end
	if station == "legends" then
		-- Le Mur des Légendes ouvre les classements du profil.
		profileScreen.showTab("leaderboards")
		station = "profile"
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

-- Ouvre les classements du profil sur un classement donné (« range », « season »…).
function TerminusController.openBoard(board: string)
	profileScreen.showTab("leaderboards", board)
	TerminusController.open("profile")
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
	-- Butin en attente : il bloque le départ en partie tant qu'il n'est pas trié.
	local pending = #view.pendingLoot
	sortButton.Visible = pending > 0
	sortButton.Text = t("topbar.sort", { count = pending })
end

-- Ouvre l'écran de tri (bouton de la barre du haut, Porte de déploiement).
function TerminusController.openSort()
	sortDismissed = false
	TerminusController.open("sort")
end

-- Minuteur de la caisse gratuite (mis à jour chaque image).
local function renderCrate()
	local view = ProfileController.get()
	if view == nil then
		return
	end
	-- Caisses accumulées + caisses gratuites offertes par un administrateur.
	local stored = view.freeCrate.stored + ((view.crateTokens or {}).free or 0)
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

-- Ouverture de la caisse gratuite (écran 9) : 2 s d'animation, puis le résultat.
local crateOverlay: Frame
local crateBox: Frame
local crateFill: Frame
local crateText: TextLabel
local crateClose: TextButton
local cratePrize: Frame? = nil -- vignette 3D de l'objet obtenu

local function clearCratePrize()
	if cratePrize then
		cratePrize:Destroy()
		cratePrize = nil
	end
end
local crateOpening = false

local function buildCrateOverlay(root: Instance)
	crateText = Panel.label("", 22, Theme.text)
	crateText.Size = UDim2.new(1, -20, 0, 70)
	crateText.Position = UDim2.fromOffset(10, 150)
	crateText.TextXAlignment = Enum.TextXAlignment.Center
	crateText.TextWrapped = true
	crateText.Font = Theme.fontTitle
	crateClose = Panel.button("", Theme.green, 160)
	crateClose.AnchorPoint = Vector2.new(0.5, 1)
	crateClose.Position = UDim2.new(0.5, 0, 1, -12)
	crateBox = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 30),
		Size = UDim2.fromOffset(90, 70),
		BackgroundColor3 = Color3.fromRGB(40, 60, 50),
	}, {
		Stroke = Create("UIStroke", { Color = Theme.green, Thickness = 2 }),
		Lid = Create("Frame", {
			Size = UDim2.new(1, 0, 0, 12),
			BackgroundColor3 = Theme.green,
			BorderSizePixel = 0,
		}),
	})
	crateFill = Create("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.green, BorderSizePixel = 0 })
	crateOverlay = Create("Frame", {
		Name = "FreeCrate",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, 290),
		BackgroundColor3 = Theme.panel,
		Visible = false,
		ZIndex = 25,
		Parent = root,
	}, {
		Stroke = Create("UIStroke", { Color = Theme.green, Transparency = 0.3, Thickness = 2 }),
		Box = crateBox,
		Bar = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 118),
			Size = UDim2.new(0.8, 0, 0, 10),
			BackgroundColor3 = Theme.background,
			BorderSizePixel = 0,
		}, { Fill = crateFill }),
		Result = crateText,
		Close = crateClose,
	})
	crateClose.Activated:Connect(function()
		clearCratePrize()
		crateBox.Visible = true
		crateOverlay.Visible = false
		PanelState.set("freeCrate", false)
	end)
end

local function openCrate()
	local view = ProfileController.get()
	local available = if view then view.freeCrate.stored + ((view.crateTokens or {}).free or 0) else 0
	if crateOpening or view == nil or available <= 0 then
		ClientNet.fire("OpenFreeCrate") -- le serveur explique le refus
		return
	end
	if view.settings.skipCrateAnimation == true then
		ClientNet.fire("OpenFreeCrate")
		return
	end
	crateOpening = true
	clearCratePrize()
	crateBox.Visible = true
	crateOverlay.Visible = true
	PanelState.set("freeCrate", true)
	crateText.Text = t("freecrate.opening")
	crateText.TextColor3 = Theme.text
	crateClose.Visible = false
	crateFill.Size = UDim2.fromScale(0, 1)
	local duration = Config.Economy.freeCrate.openDuration
	TweenService:Create(crateFill, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) })
		:Play()
	-- La caisse tremble de plus en plus.
	local started = os.clock()
	local shake: RBXScriptConnection
	shake = RunService.RenderStepped:Connect(function()
		local progress = math.clamp((os.clock() - started) / duration, 0, 1)
		crateBox.Rotation = math.sin(os.clock() * 40) * 6 * progress
		if progress >= 1 then
			shake:Disconnect()
			crateBox.Rotation = 0
		end
	end)
	task.delay(duration, function()
		crateOpening = false
		ClientNet.fire("OpenFreeCrate")
	end)
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
	-- Objet : on le MONTRE (vignette 3D qui tourne, liseré à la couleur de son
	-- état), même quand l'animation d'ouverture est désactivée.
	local item = if reward.kind == "item" then reward.item else nil
	if not crateOverlay.Visible and item == nil then
		NotificationController.show(text, Theme.green)
		return
	end
	clearCratePrize()
	if item then
		local icon =
			ItemIcon.create(tostring(item.itemId), UDim2.fromOffset(104, 104), tonumber(item.condition), nil, true)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 12)
		icon.ZIndex = 26
		icon.Parent = crateOverlay
		cratePrize = icon
	end
	crateBox.Visible = item == nil
	crateFill.Size = UDim2.fromScale(1, 1)
	crateText.Text = text
	crateText.TextColor3 = Theme.green
	crateClose.Text = t("common.confirm")
	crateClose.Visible = true
	if not crateOverlay.Visible then
		crateOverlay.Visible = true
		PanelState.set("freeCrate", true)
	end
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
	sortButton = Panel.button("", Theme.orange, 190)
	sortButton.LayoutOrder = 7
	sortButton.Visible = false
	sortButton.Parent = topBar
	sortButton.Activated:Connect(function()
		TerminusController.openSort()
	end)
	crateButton = Panel.button("", Theme.green, 170)
	crateButton.LayoutOrder = 8
	crateButton.Parent = topBar
	crateButton.Activated:Connect(openCrate)
	local menu = Panel.button("☰", Theme.cyan, 44)
	menu.LayoutOrder = 9
	menu.Parent = topBar
	menu.Activated:Connect(function()
		if quickMenu:isOpen() then
			quickMenu:close()
		else
			quickMenu:open()
		end
	end)
end

local QUICK_STATIONS =
	{ "vault", "merchant", "armorer", "insurer", "bazaar", "deploy", "range", "legends", "profile", "settings" }

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
	buildCrateOverlay(root)
	screens.vault = VaultScreen.create(root, t)
	screens.merchant = MerchantScreen.create(root, t)
	screens.armorer = ArmorerScreen.create(root, t)
	screens.insurer = InsurerScreen.create(root, t)
	screens.sort = SortScreen.create(root, t)
	profileScreen = ProfileScreen.create(root, t, player.DisplayName)
	screens.profile = profileScreen
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
		-- Loot à trier : écran de tri automatique au retour au Terminus, mais jamais
		-- sous le bilan de fin de partie (il attend qu'on le ferme).
		if
			#view.pendingLoot > 0
			and not inMatch()
			and not MatchHUDController.isResultOpen()
			and not screens.sort.panel:isOpen()
			and not sortDismissed
		then
			TerminusController.open("sort")
		elseif #view.pendingLoot == 0 then
			sortDismissed = false
			screens.sort.panel:close()
		end
	end)
	ClientNet.on("FreeCrateResult", showCrateResult)

	-- Bilan affiché : un écran de tri ouvert juste avant (profil arrivé en premier) s'efface.
	MatchHUDController.ResultOpened:Connect(function()
		if screens.sort.panel:isOpen() then
			screens.sort.panel:close()
		end
		sortDismissed = false
	end)
	-- Bilan fermé (« Trier le butin » ou retour) : l'écran de tri s'ouvre s'il reste du butin.
	MatchHUDController.ResultClosed:Connect(function(sort)
		local view = ProfileController.get()
		if sort then
			sortDismissed = false
		end
		if view and #view.pendingLoot > 0 and not inMatch() and not sortDismissed then
			TerminusController.open("sort")
		end
	end)

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
