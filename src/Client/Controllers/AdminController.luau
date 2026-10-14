--!strict
--[[
	AdminController : panneau d'administration (administrateurs seulement).

	Le bouton « ADMIN » n'apparaît que si le serveur a marqué le joueur comme
	administrateur (attribut IsAdmin). Le serveur revérifie chaque demande :
	ce panneau n'est qu'une commodité d'affichage.

	Deux onglets, pour un joueur présent sur le serveur :
	- Caisses : type (gratuite, Rouille, Néon, Prototype) et quantité. Le joueur
	  les ouvre gratuitement au Holo-Bazar (ou au bouton de la caisse gratuite) ;
	- Crédits : montant (raccourcis et pas de ±100).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
local Panel = require(script.Parent.Parent.UI.Panel)
local Theme = require(script.Parent.Parent.UI.Theme)
local HUDController = require(script.Parent.HUDController)
local ProfileController = require(script.Parent.ProfileController)

local AdminController = {}

local player = Players.LocalPlayer
local t = ProfileController.t
local A = Config.Admin

local panel: Panel.Panel? = nil
local toggle: TextButton? = nil
local selectedUserId: number? = nil
local selectedCrate = A.giftCrates[1]
local amount = 1
local tab: "crates" | "credits" = "crates"
local credits = A.creditPresets[1]

local function crateName(kind: string): string
	return if kind == "free" then t("freecrate.title") else t("cosmeticCrate." .. kind)
end

local function render()
	local current = panel
	if current == nil then
		return
	end
	current.title.Text = t("admin.title")
	local body = current.body
	Panel.clear(body)

	local content = Panel.list("Content")
	content.Size = UDim2.fromScale(1, 1)
	content.Parent = body
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local function section(key: string)
		local label = Panel.label(t(key), 15, Theme.cyan)
		label.LayoutOrder = nextOrder()
		label.Parent = content
	end
	local function row(): Frame
		return Create("Frame", {
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, -8, 0, Theme.minButtonSize),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = content,
		}, {
			Layout = Create("UIGridLayout", {
				CellSize = UDim2.fromOffset(170, Theme.minButtonSize),
				CellPadding = UDim2.fromOffset(6, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
	end

	-- Onglets : caisses ou crédits.
	local tabs = row()
	for index, key in { "crates", "credits" } do
		local active = tab == key
		local button = Panel.button(t("admin.tab." .. key), if active then Theme.magenta else Theme.textDim, 170)
		button.LayoutOrder = index
		button.Parent = tabs
		button.Activated:Connect(function()
			tab = key :: any
			render()
		end)
	end

	-- Joueur (présent sur ce serveur).
	section("admin.player")
	local players = row()
	local others = Players:GetPlayers()
	table.sort(others, function(a, b)
		return a.DisplayName < b.DisplayName
	end)
	if selectedUserId and Players:GetPlayerByUserId(selectedUserId) == nil then
		selectedUserId = nil
	end
	for index, other in others do
		local selected = other.UserId == selectedUserId
		local button = Panel.button(
			(if selected then "✔ " else "") .. other.DisplayName,
			if selected then Theme.green else Theme.text,
			170
		)
		button.LayoutOrder = index
		button.TextTruncate = Enum.TextTruncate.AtEnd
		button.Parent = players
		button.Activated:Connect(function()
			selectedUserId = other.UserId
			render()
		end)
	end

	local target = if selectedUserId then Players:GetPlayerByUserId(selectedUserId) else nil

	if tab == "credits" then
		-- Montant : raccourcis, puis ajustement par pas.
		section("admin.creditsAmount")
		local presets = row()
		for index, value in A.creditPresets do
			local button = Panel.button(
				(if value == credits then "✔ " else "") .. tostring(value),
				if value == credits then Theme.green else Theme.text,
				170
			)
			button.LayoutOrder = index
			button.Parent = presets
			button.Activated:Connect(function()
				credits = value
				render()
			end)
		end
		local adjust = row()
		local less = Panel.button(`− {A.creditStep}`, Theme.text, 170)
		less.LayoutOrder = 1
		less.Parent = adjust
		local shown = Panel.button(t("admin.creditsValue", { credits = credits }), Theme.cyan, 170)
		shown.LayoutOrder = 2
		shown.AutoButtonColor = false
		shown.Parent = adjust
		local more = Panel.button(`+ {A.creditStep}`, Theme.text, 170)
		more.LayoutOrder = 3
		more.Parent = adjust
		less.Activated:Connect(function()
			credits = math.max(A.creditStep, credits - A.creditStep)
			render()
		end)
		more.Activated:Connect(function()
			credits = math.min(A.maxCreditsPerGift, credits + A.creditStep)
			render()
		end)
		local giveCredits = Panel.button(
			if target
				then t("admin.giveCredits", { credits = credits, name = target.DisplayName })
				else t("admin.choosePlayer"),
			if target then Theme.green else Theme.textDim,
			520
		)
		giveCredits.LayoutOrder = nextOrder()
		giveCredits.Parent = content
		giveCredits.Activated:Connect(function()
			if selectedUserId then
				ClientNet.fire("AdminGiftCredits", selectedUserId, credits)
			end
		end)
		local creditsNote = Panel.label(t("admin.creditsNote"), 13, Theme.textDim)
		creditsNote.LayoutOrder = nextOrder()
		creditsNote.TextWrapped = true
		creditsNote.Size = UDim2.new(1, -8, 0, 40)
		creditsNote.Parent = content
		return
	end

	-- Type de caisse.
	section("admin.crate")
	local crates = row()
	for index, kind in A.giftCrates do
		local selected = kind == selectedCrate
		local button = Panel.button(
			(if selected then "✔ " else "") .. crateName(kind),
			if selected then Theme.magenta else Theme.text,
			170
		)
		button.LayoutOrder = index
		button.Parent = crates
		button.Activated:Connect(function()
			selectedCrate = kind
			render()
		end)
	end

	-- Quantité.
	section("admin.amount")
	local quantity = row()
	local minus = Panel.button("−", Theme.text, 170)
	minus.LayoutOrder = 1
	minus.Parent = quantity
	local value = Panel.button(tostring(amount), Theme.cyan, 170)
	value.LayoutOrder = 2
	value.AutoButtonColor = false
	value.Parent = quantity
	local plus = Panel.button("+", Theme.text, 170)
	plus.LayoutOrder = 3
	plus.Parent = quantity
	minus.Activated:Connect(function()
		amount = math.max(1, amount - 1)
		render()
	end)
	plus.Activated:Connect(function()
		amount = math.min(A.maxPerGift, amount + 1)
		render()
	end)

	-- Offrir.
	local give = Panel.button(
		if target
			then t("admin.give", { count = amount, crate = crateName(selectedCrate), name = target.DisplayName })
			else t("admin.choosePlayer"),
		if target then Theme.green else Theme.textDim,
		520
	)
	give.LayoutOrder = nextOrder()
	give.Parent = content
	give.Activated:Connect(function()
		if selectedUserId then
			ClientNet.fire("AdminGiftCrates", selectedUserId, selectedCrate, amount)
		end
	end)
	local note = Panel.label(t("admin.note"), 13, Theme.textDim)
	note.LayoutOrder = nextOrder()
	note.TextWrapped = true
	note.Size = UDim2.new(1, -8, 0, 40)
	note.Parent = content
end

-- Construit le panneau et son bouton, une fois le joueur reconnu administrateur.
local function enable()
	if panel ~= nil then
		return
	end
	local root = HUDController.root()
	local created = Panel.create("AdminPanel", root, Theme.magenta)
	panel = created
	local button = Create("TextButton", {
		Name = "AdminToggle",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0.32, 0),
		Size = UDim2.fromOffset(90, 32),
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = 0.15,
		Font = Theme.fontTitle,
		TextSize = 14,
		TextColor3 = Theme.magenta,
		Text = t("admin.button"),
		Parent = root,
	}, { Stroke = Create("UIStroke", { Color = Theme.magenta, Transparency = 0.3 }) })
	toggle = button
	button.Activated:Connect(function()
		if created:isOpen() then
			created:close()
		else
			render()
			created:open()
		end
	end)
	-- La liste des joueurs suit les arrivées et départs.
	local function refresh()
		if created:isOpen() then
			render()
		end
	end
	Players.PlayerAdded:Connect(refresh)
	Players.PlayerRemoving:Connect(function()
		task.defer(refresh)
	end)
end

local function onAdminChanged()
	if player:GetAttribute("IsAdmin") == true then
		enable()
		if toggle then
			toggle.Visible = true
		end
	else
		if toggle then
			toggle.Visible = false
		end
		if panel and panel:isOpen() then
			panel:close()
		end
	end
end

function AdminController.init() end

function AdminController.start()
	player:GetAttributeChangedSignal("IsAdmin"):Connect(onAdminChanged)
	onAdminChanged()
end

return AdminController
