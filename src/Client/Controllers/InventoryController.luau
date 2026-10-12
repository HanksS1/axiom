--!strict
--[[
	InventoryController : sac porté en partie (section 8, écran 17.3).

	- Reçoit l'état du sac (InventorySync) et l'expose au HUD.
	- Panneau du sac (Tab / Select manette / bouton sac mobile) :
	  emplacements équipés et contenu, actions Équiper / Ranger / Jeter / Utiliser.
	- Consommables rapides : 3 = soins, 4 = batterie, 5 = Surcharge
	  (manette : croix bas pour choisir, maintenir pour utiliser).
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemCatalog = require(Shared.Items.ItemCatalog)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
local ItemCard = require(script.Parent.Parent.UI.ItemCard)
local PanelState = require(script.Parent.Parent.UI.PanelState)
local Theme = require(script.Parent.Parent.UI.Theme)
local HUDController = require(script.Parent.HUDController)
local InputController = require(script.Parent.InputController)
local ProfileController = require(script.Parent.ProfileController)

export type State = {
	equipped: { [string]: Types.ItemInstance },
	bag: { Types.ItemInstance },
	capacity: number,
	used: number,
	bonusUp: number,
}

local InventoryController = {}

InventoryController.Changed = Signal.new() :: Signal.Signal<State>

-- Consommables rapides, dans l'ordre des touches 3 / 4 / 5.
InventoryController.quickItems = table.freeze({ "nanite_injector", "shield_battery", "overdrive" })

local t = ProfileController.t
local state: State = { equipped = {}, bag = {}, capacity = 0, used = 0, bonusUp = 0 }
local panel: Frame
local equippedList: ScrollingFrame
local bagList: ScrollingFrame
local upLabel: TextLabel
local selectedQuick = 1

local SLOTS = { "ranged", "melee", "gadget1", "gadget2", "helmet", "vest", "backpack" }

function InventoryController.state(): State
	return state
end

function InventoryController.count(itemId: string): number
	local total = 0
	for _, item in state.bag do
		if item.itemId == itemId then
			total += item.stack or 1
		end
	end
	return total
end

function InventoryController.selectedQuick(): number
	return selectedQuick
end

function InventoryController.useQuick(index: number)
	local itemId = InventoryController.quickItems[index]
	if itemId and InventoryController.count(itemId) > 0 then
		ClientNet.fire("UseConsumable", itemId)
	end
end

local function clear(list: Instance)
	for _, child in list:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

local function emptyLabel(parent: Instance)
	Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		Font = Theme.fontText,
		TextSize = 14,
		TextColor3 = Theme.textDim,
		Text = t("inventory.empty"),
		Parent = parent,
	})
end

local function render()
	if panel == nil or not panel.Visible then
		return
	end
	clear(equippedList)
	clear(bagList)
	upLabel.Text = t("hud.bagUp", { used = state.used, capacity = state.capacity })

	for index, slot in SLOTS do
		local item = state.equipped[slot]
		if item then
			local card = ItemCard.create(item, t, {
				{
					label = t("inventory.action.store"),
					callback = function()
						ClientNet.fire("UnequipItem", slot)
					end,
				},
				{
					label = t("inventory.action.drop"),
					color = Theme.red,
					callback = function()
						ClientNet.fire("DropItem", item.uid)
					end,
				},
			}, index)
			card.Parent = equippedList
		end
	end
	if next(state.equipped) == nil then
		emptyLabel(equippedList)
	end

	for index, item in state.bag do
		local actions: { ItemCard.Action } = {}
		local info = ItemCatalog.get(item.itemId)
		if info and info.category == "consumable" then
			table.insert(actions, {
				label = t("inventory.action.use"),
				color = Theme.green,
				callback = function()
					ClientNet.fire("UseConsumable", item.itemId)
				end,
			})
		end
		local slot: string? = nil
		for _, candidate in SLOTS do
			if info and ItemCatalog.slotCategories[candidate :: any] == info.category then
				slot = if slot == nil or (state.equipped[candidate] == nil and state.equipped[slot] ~= nil)
					then candidate
					else slot
			end
		end
		if slot then
			local targetSlot = slot
			table.insert(actions, {
				label = t("inventory.action.equip"),
				callback = function()
					ClientNet.fire("EquipItem", item.uid, targetSlot)
				end,
			})
		end
		table.insert(actions, {
			label = t("inventory.action.drop"),
			color = Theme.red,
			callback = function()
				ClientNet.fire("DropItem", item.uid)
			end,
		})
		ItemCard.create(item, t, actions, index).Parent = bagList
	end
	if #state.bag == 0 then
		emptyLabel(bagList)
	end
end

local function list(name: string, order: number): ScrollingFrame
	return Create("ScrollingFrame", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0.45, -20),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, {
		Layout = Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
end

local function header(text: string, order: number): TextLabel
	return Create("TextLabel", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Font = Theme.fontTitle,
		TextSize = 14,
		TextColor3 = Theme.cyan,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
	})
end

function InventoryController.setOpen(open: boolean)
	panel.Visible = open
	PanelState.set("inventory", open)
	if open then
		-- Les en-têtes suivent la langue courante.
		(panel:FindFirstChild("Title") :: TextLabel).Text = t("inventory.title")
		local body = panel:FindFirstChild("Body") :: Frame
		(body:FindFirstChild("EquippedHeader") :: TextLabel).Text = t("inventory.equipped");
		(body:FindFirstChild("BagHeader") :: TextLabel).Text = t("inventory.bag")
		render()
		if InputController.device() == "gamepad" then
			GuiService.SelectedObject = panel:FindFirstChildWhichIsA("TextButton", true)
		end
	end
end

function InventoryController.toggle()
	InventoryController.setOpen(not panel.Visible)
end

function InventoryController.init() end

function InventoryController.start()
	local body = Create("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(12, 44),
		Size = UDim2.new(1, -24, 1, -56),
		BackgroundTransparency = 1,
	}, {
		Layout = Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	equippedList = list("Equipped", 2)
	bagList = list("Bag", 4)
	local equippedHeader = header(t("inventory.equipped"), 1)
	equippedHeader.Name = "EquippedHeader"
	equippedHeader.Parent = body
	equippedList.Parent = body
	local bagHeader = header(t("inventory.bag"), 3)
	bagHeader.Name = "BagHeader"
	bagHeader.Parent = body
	bagList.Parent = body

	upLabel = Create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -60, 0, 10),
		Size = UDim2.fromOffset(160, 24),
		BackgroundTransparency = 1,
		Font = Theme.fontNumbers,
		TextSize = 16,
		TextColor3 = Theme.text,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
	})

	panel = Create("Frame", {
		Name = "InventoryPanel",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.new(0.46, 0, 0.8, 0),
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = 0.1,
		Visible = false,
		ZIndex = 5,
		Parent = HUDController.root(),
	}, {
		Stroke = Create("UIStroke", { Color = Theme.cyan, Transparency = 0.5 }),
		SizeLimit = Create("UISizeConstraint", { MinSize = Vector2.new(320, 240), MaxSize = Vector2.new(620, 900) }),
		Title = Create("TextLabel", {
			Position = UDim2.fromOffset(12, 8),
			Size = UDim2.new(1, -24, 0, 28),
			BackgroundTransparency = 1,
			Font = Theme.fontTitle,
			TextSize = 22,
			TextColor3 = Theme.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = t("inventory.title"),
		}),
		Up = upLabel,
		Close = Create("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 6),
			Size = UDim2.fromOffset(Theme.minButtonSize, Theme.minButtonSize - 10),
			BackgroundTransparency = 1,
			Font = Theme.fontTitle,
			TextSize = 22,
			TextColor3 = Theme.textDim,
			Text = "✕",
		}),
		Body = body,
	})(panel:FindFirstChild("Close") :: TextButton).Activated:Connect(function()
		InventoryController.setOpen(false)
	end)

	ClientNet.on("InventorySync", function(snapshot: State)
		if type(snapshot) ~= "table" then
			return
		end
		state = snapshot
		InventoryController.Changed:Fire(state)
		render()
	end)

	InputController.ActionBegan:Connect(function(action)
		if action == "inventory" then
			InventoryController.toggle()
		elseif action == "heal" then
			InventoryController.useQuick(1)
		elseif action == "battery" then
			InventoryController.useQuick(2)
		elseif action == "boost" then
			InventoryController.useQuick(3)
		end
	end)
	-- Manette : appui court sur la croix bas = consommable suivant.
	InputController.Tapped:Connect(function(action)
		if action == "quickCycle" then
			selectedQuick = selectedQuick % #InventoryController.quickItems + 1
			InventoryController.Changed:Fire(state)
		end
	end)
	InputController.HeldLong:Connect(function(action)
		if action == "quickCycle" then
			InventoryController.useQuick(selectedQuick)
		end
	end)

	Players.LocalPlayer.CharacterAdded:Connect(function()
		InventoryController.setOpen(false)
	end)
	ProfileController.Changed:Connect(render)
end

return InventoryController
