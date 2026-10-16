--!strict
--[[
	InventoryController : sac porté en partie (section 8, écran 17.3).

	- Reçoit l'état du sac (InventorySync) et l'expose au HUD.
	- Panneau du sac (B / Select manette / bouton sac mobile / clic sur la jauge du sac) :
	  zones (UI/LoadoutView) : armes, protections, gadgets, sac à dos et sa
	  place, grille du contenu ; la case choisie montre sa carte et ses
	  actions Équiper / Ranger / Jeter / Utiliser / Détails. Souris : glisser
	  une case du sac sur un emplacement (équiper) ou l'inverse (ranger).
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
local ClickShield = require(script.Parent.Parent.UI.ClickShield)
local Create = require(script.Parent.Parent.UI.Create)
local DragDrop = require(script.Parent.Parent.UI.DragDrop)
local ItemCard = require(script.Parent.Parent.UI.ItemCard)
local LoadoutView = require(script.Parent.Parent.UI.LoadoutView)
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

-- Consommables rapides, dans l'ordre des touches 3 / 4 / 5 / 6.
InventoryController.quickItems = table.freeze({ "nanite_injector", "shield_battery", "overdrive", "exo_harness" })

local t = ProfileController.t
local state: State = { equipped = {}, bag = {}, capacity = 0, used = 0, bonusUp = 0 }
local panel: Frame
local view: LoadoutView.View
local selectedQuick = 1

-- Glisser-déposer (souris) : noms des zones de dépôt de ce panneau.
local DRAG_SLOT = "inventorySlot"
local DRAG_BAG = "inventoryBag"

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

-- Emplacement où équiper un objet du sac : un emplacement libre de sa catégorie, sinon le premier.
local function slotForBagItem(item: Types.ItemInstance): string?
	local info = ItemCatalog.get(item.itemId)
	local slot: string? = nil
	for _, candidate in SLOTS do
		if info and ItemCatalog.slotCategories[candidate :: any] == info.category then
			slot = if slot == nil or (state.equipped[candidate] == nil and state.equipped[slot] ~= nil)
				then candidate
				else slot
		end
	end
	return slot
end

local function actionsFor(item: Types.ItemInstance, where: LoadoutView.Where, slot: string?): { ItemCard.Action }
	local drop: ItemCard.Action = {
		label = t("inventory.action.drop"),
		color = Theme.red,
		callback = function()
			ClientNet.fire("DropItem", item.uid)
		end,
	}
	if where == "equipped" then
		return {
			{
				label = t("inventory.action.store"),
				callback = function()
					ClientNet.fire("UnequipItem", slot)
				end,
			},
			drop,
		}
	end
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
	local target = slotForBagItem(item)
	if target then
		table.insert(actions, {
			label = t("inventory.action.equip"),
			callback = function()
				ClientNet.fire("EquipItem", item.uid, target)
			end,
		})
	end
	table.insert(actions, drop)
	return actions
end

local function render()
	if panel == nil or not panel.Visible then
		return
	end
	view.set(state.equipped, state.bag, state.used, state.capacity)
end

function InventoryController.setOpen(open: boolean)
	panel.Visible = open
	PanelState.set("inventory", open)
	if open then
		-- Les en-têtes suivent la langue courante.
		(panel:FindFirstChild("Title") :: TextLabel).Text = t("inventory.title")
		view.refreshTexts()
		render()
		-- Manette : la sélection part de l'arme principale, puis de case en case.
		local first = view.selectFirst()
		if InputController.device() == "gamepad" and first then
			GuiService.SelectedObject = first
		end
	end
end

function InventoryController.toggle()
	InventoryController.setOpen(not panel.Visible)
end

function InventoryController.init() end

function InventoryController.start()
	view = LoadoutView.create({
		t = t,
		actionsFor = actionsFor,
		drag = {
			payload = function(item, where, slot)
				return { from = "inventory", where = where, uid = item.uid, slot = slot }
			end,
			slotTarget = DRAG_SLOT,
			bagTarget = DRAG_BAG,
		},
	})
	local body = view.frame
	body.Name = "Body"
	body.Position = UDim2.fromOffset(12, 42)
	body.Size = UDim2.new(1, -24, 1, -54)

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
	})
	-- Sac ouvert : rien n'est cliquable à travers (le conteneur, au même niveau, reste utilisable).
	ClickShield.attach(panel, 1)
	local close = panel:FindFirstChild("Close") :: TextButton
	close.Activated:Connect(function()
		InventoryController.setOpen(false)
	end)

	-- Souris : case du sac → emplacement (équiper), emplacement → grille du sac (ranger).
	DragDrop.Dropped:Connect(function(payload: any, target: string)
		if not panel.Visible or type(payload) ~= "table" or payload.from ~= "inventory" or payload.uid == nil then
			return
		end
		if payload.where == "bag" and target == DRAG_SLOT then
			local item = nil
			for _, candidate in state.bag do
				if candidate.uid == payload.uid then
					item = candidate
				end
			end
			local slot = if item then slotForBagItem(item) else nil
			if slot then
				ClientNet.fire("EquipItem", payload.uid, slot)
			end
		elseif payload.where == "equipped" and target == DRAG_BAG and payload.slot then
			ClientNet.fire("UnequipItem", payload.slot)
		end
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
		elseif action == "exo" then
			InventoryController.useQuick(4)
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
