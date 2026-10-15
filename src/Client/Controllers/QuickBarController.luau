--!strict
--[[
	QuickBarController : bas du HUD, au centre (section 17.3, écran 11).

	- Consommables rapides (soins, batterie, Surcharge) avec quantité et
	  touche associée ; sélection mise en évidence à la manette.
	- Barre de progression pendant l'utilisation d'un consommable.
	- Jauge d'UP du sac et temps de Surcharge restant.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ItemRules = require(ReplicatedStorage:WaitForChild("Shared").Items.ItemRules)

local Create = require(script.Parent.Parent.UI.Create)
local Theme = require(script.Parent.Parent.UI.Theme)
local HUDController = require(script.Parent.HUDController)
local InputController = require(script.Parent.InputController)
local InventoryController = require(script.Parent.InventoryController)
local ProfileController = require(script.Parent.ProfileController)
local WeaponController = require(script.Parent.WeaponController)

local QuickBarController = {}

local t = ProfileController.t
-- Actions des emplacements (icônes de touches selon le périphérique, 17.2).
local SLOT_ACTIONS: { InputController.Action } = { "heal", "battery", "boost" }

local slots: { { frame: Frame, name: TextLabel, count: TextLabel, key: TextLabel, stroke: UIStroke } } = {}
local usingBar: Frame
local usingFill: Frame
local usingLabel: TextLabel
local bagLabel: TextButton
local boostLabel: TextLabel

local function render()
	local inventory = InventoryController.state()
	local device = InputController.device()
	for index, slot in slots do
		local itemId = InventoryController.quickItems[index]
		local count = InventoryController.count(itemId)
		slot.name.Text = t("hud.quick." .. itemId)
		slot.count.Text = tostring(count)
		slot.frame.BackgroundTransparency = if count > 0 then Theme.panelTransparency else 0.7
		slot.name.TextTransparency = if count > 0 then 0 else 0.5
		local hint = InputController.hint(SLOT_ACTIONS[index])
		slot.key.Visible = device == "keyboard" and hint ~= nil
		slot.key.Text = hint or ""
		slot.stroke.Transparency = if device == "gamepad" and InventoryController.selectedQuick() == index
			then 0
			else 0.7
	end
	local bagKey = if device == "keyboard" then InputController.hint("inventory") else nil
	bagLabel.Text = t("hud.bagUp", { used = inventory.used, capacity = inventory.capacity })
		.. (if bagKey then `  [{bagKey}]` else "")
	local level = ItemRules.fillLevel(inventory.used, inventory.capacity)
	if level == "full" then
		bagLabel.Text ..= "  ·  " .. t("capacity.full")
	elseif level == "high" then
		bagLabel.Text ..= "  ·  " .. t("capacity.high")
	end
	bagLabel.TextColor3 = if level == "full" then Theme.red elseif level == "high" then Theme.orange else Theme.textDim

	local snap = WeaponController.snapshot()
	usingBar.Visible = snap.usingProgress ~= nil
	if snap.usingProgress and snap.usingItemId then
		usingFill.Size = UDim2.fromScale(snap.usingProgress, 1)
		usingLabel.Text = t("hud.using") .. " " .. t("item." .. snap.usingItemId)
	end
	boostLabel.Visible = snap.boostRemaining ~= nil
	if snap.boostRemaining then
		boostLabel.Text = t("hud.boost", { seconds = math.ceil(snap.boostRemaining) })
	end
end

function QuickBarController.init() end

function QuickBarController.start()
	local row = Create("Frame", {
		Name = "QuickBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(0, 46),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = HUDController.root(),
	}, {
		Layout = Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for index in InventoryController.quickItems do
		local stroke = Create("UIStroke", { Color = Theme.cyan, Transparency = 0.7, Thickness = 2 })
		local name = Create("TextLabel", {
			Position = UDim2.fromOffset(6, 4),
			Size = UDim2.new(1, -12, 0, 16),
			BackgroundTransparency = 1,
			Font = Theme.fontText,
			TextSize = 12,
			TextColor3 = Theme.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
		})
		local count = Create("TextLabel", {
			Position = UDim2.fromOffset(6, 20),
			Size = UDim2.new(1, -12, 0, 22),
			BackgroundTransparency = 1,
			Font = Theme.fontNumbers,
			TextSize = 20,
			TextColor3 = Theme.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "0",
		})
		local key = Create("TextLabel", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -4, 1, -2),
			Size = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1,
			Font = Theme.fontNumbers,
			TextSize = 12,
			TextColor3 = Theme.textDim,
			Text = "",
		})
		local frame = Create("Frame", {
			LayoutOrder = index,
			Size = UDim2.fromOffset(84, 46),
			BackgroundColor3 = Theme.panel,
			BackgroundTransparency = Theme.panelTransparency,
			BorderSizePixel = 0,
			Parent = row,
		}, { Stroke = stroke, ItemName = name, Count = count, Key = key })
		table.insert(slots, { frame = frame, name = name, count = count, key = key, stroke = stroke })
	end

	usingFill = Create("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.green, BorderSizePixel = 0 })
	usingLabel = Create("TextLabel", {
		Position = UDim2.fromOffset(0, -20),
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Font = Theme.fontText,
		TextSize = 14,
		TextColor3 = Theme.green,
		Text = "",
	})
	usingBar = Create("Frame", {
		Name = "UsingBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -90),
		Size = UDim2.fromOffset(220, 6),
		BackgroundColor3 = Theme.panel,
		BorderSizePixel = 0,
		Visible = false,
		Parent = HUDController.root(),
	}, { Fill = usingFill, Label = usingLabel })

	-- Jauge du sac : un clic ouvre le sac (en plus de la touche).
	bagLabel = Create("TextButton", {
		Name = "BagUp",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -66),
		Size = UDim2.fromOffset(200, 18),
		BackgroundTransparency = 1,
		Font = Theme.fontNumbers,
		TextSize = 13,
		TextColor3 = Theme.textDim,
		Text = "",
		Parent = HUDController.root(),
	})
	boostLabel = Create("TextLabel", {
		Name = "Boost",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -120),
		Size = UDim2.fromOffset(240, 20),
		BackgroundTransparency = 1,
		Font = Theme.fontTitle,
		TextSize = 15,
		TextColor3 = Theme.orange,
		Visible = false,
		Text = "",
		Parent = HUDController.root(),
	})

	bagLabel.Activated:Connect(InventoryController.toggle)

	RunService.RenderStepped:Connect(render)
end

return QuickBarController
