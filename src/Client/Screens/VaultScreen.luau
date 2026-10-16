--!strict
--[[
	VaultScreen : coffre et équipement (section 17.3, écran 4).

	- À gauche : ce que le joueur PORTE, en zones (UI/LoadoutView, comme le
	  sac en partie) : armes, protections, gadgets, sac à dos et sa place,
	  grille du sac préparé.
	- À droite : le coffre en cartes (liste : on y choisit, trie et compare),
	  triables par type, état ou valeur. « Au sac » est grisé, avec l'espace
	  manquant, quand l'objet ne tient pas dans le sac préparé (Shared/Items/
	  SpaceCheck) ; idem pour « Ranger » vers un coffre plein.
	- En bas : jauge « Coffre : x / 30 UP » et jauge de SE avec les modes
	  accessibles (grisés avec la raison sinon).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local ItemRules = require(Shared.Items.ItemRules)
local SpaceCheck = require(Shared.Items.SpaceCheck)
local Types = require(Shared.Types)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local ConfirmDialog = require(script.Parent.Parent.UI.ConfirmDialog)
local CapacityGauge = require(script.Parent.Parent.UI.CapacityGauge)
local Create = require(script.Parent.Parent.UI.Create)
local DragDrop = require(script.Parent.Parent.UI.DragDrop)
local ItemCard = require(script.Parent.Parent.UI.ItemCard)
local LoadoutView = require(script.Parent.Parent.UI.LoadoutView)
local Panel = require(script.Parent.Parent.UI.Panel)
local Theme = require(script.Parent.Parent.UI.Theme)

type Translate = (key: string, params: { [string]: any }?) -> string

local VaultScreen = {}

local SLOTS: { Types.SlotName } = { "ranged", "melee", "gadget1", "gadget2", "helmet", "vest", "backpack" }
local CATEGORY_ORDER = {
	ranged = 1,
	melee = 2,
	gadget = 3,
	helmet = 4,
	vest = 5,
	backpack = 6,
	consumable = 7,
	cell = 8,
	calibration = 9,
}

export type Screen = {
	panel: Panel.Panel,
	render: (view: Types.ProfileView) -> (),
}

function VaultScreen.create(parent: Instance, t: Translate): Screen
	local panel = Panel.create("VaultScreen", parent, Theme.magenta)
	local sortMode = "type"
	local current: Types.ProfileView? = nil

	local left = Create("Frame", {
		Size = UDim2.new(0.42, -8, 1, -64),
		BackgroundTransparency = 1,
		Parent = panel.body,
	})
	-- Personnage en 3D (aperçu de l'avatar, qui tourne lentement).
	local viewport = Create("ViewportFrame", {
		Size = UDim2.new(1, 0, 0.3, -4),
		BackgroundColor3 = Theme.background,
		BackgroundTransparency = 0.3,
		Ambient = Color3.fromRGB(150, 160, 180),
		LightColor = Color3.fromRGB(0, 229, 255),
		Parent = left,
	})
	local viewportCamera = Instance.new("Camera")
	viewportCamera.FieldOfView = 40
	viewportCamera.Parent = viewport
	viewport.CurrentCamera = viewportCamera
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local previewOf: Model? = nil
	local previewAngle = 0
	local function refreshPreview()
		local character = Players.LocalPlayer.Character
		if character == nil or character == previewOf then
			return
		end
		previewOf = character
		world:ClearAllChildren()
		local archivable = character.Archivable
		character.Archivable = true
		local copy = character:Clone()
		character.Archivable = archivable
		if copy == nil then
			return
		end
		for _, descendant in copy:GetDescendants() do
			if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("Sound") then
				descendant:Destroy()
			elseif descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end
		copy:PivotTo(CFrame.new())
		copy.Parent = world
	end
	RunService.RenderStepped:Connect(function(dt: number)
		if not panel:isOpen() then
			return
		end
		previewAngle += dt * 0.6
		viewportCamera.CFrame = CFrame.Angles(0, previewAngle, 0) * CFrame.new(0, 0.5, 9)
		viewportCamera.CFrame = CFrame.lookAt(viewportCamera.CFrame.Position, Vector3.new(0, 0.3, 0))
	end)

	local function vaultAction(action: string, uid: string?, slot: string?)
		ClientNet.fire("VaultAction", action, uid, slot)
	end

	-- Équipement et sac préparé, en zones (actions : vers le coffre).
	local loadout = LoadoutView.create({
		t = t,
		actionsFor = function(item, where, slot)
			local view = current
			local fit = if view then SpaceCheck.keepInVault(view.vault, view.vaultCapacity, item) else nil
			return {
				{
					label = t("inventory.action.store"),
					disabled = fit ~= nil and not fit.fits,
					callback = function()
						if where == "equipped" then
							vaultAction("unequip", nil, slot)
						else
							vaultAction("fromBag", item.uid)
						end
					end,
				},
			}
		end,
		cardOptions = function(item)
			local view = current
			local fit = if view then SpaceCheck.keepInVault(view.vault, view.vaultCapacity, item) else nil
			return if fit and not fit.fits then { warning = t("fit.vault", { up = fit.missing }) } else nil
		end,
		drag = {
			payload = function(item, where, slot)
				return { from = where, uid = item.uid, slot = slot }
			end,
			slotTarget = "equipped",
			bagTarget = "bag",
		},
	})
	loadout.frame.Position = UDim2.fromScale(0, 0.3)
	loadout.frame.Size = UDim2.fromScale(1, 0.7)
	loadout.frame.Parent = left

	local right = Create("Frame", {
		Position = UDim2.new(0.42, 8, 0, 0),
		Size = UDim2.new(0.58, -8, 1, -64),
		BackgroundTransparency = 1,
		Parent = panel.body,
	})
	local sortRow = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		Parent = right,
	}, {
		Layout = Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }),
	})
	local vaultList = Panel.list("Vault")
	vaultList.Position = UDim2.fromOffset(0, 50)
	vaultList.Size = UDim2.new(1, 0, 1, -50)
	vaultList.Parent = right

	-- Jauges du bas.
	local gauges = Create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundTransparency = 1,
		Parent = panel.body,
	})
	local vaultGauge = CapacityGauge.create(t, "vault", true)
	local vaultHolder = Create("Frame", {
		Size = UDim2.new(0.35, -10, 1, 0),
		BackgroundTransparency = 1,
		Parent = gauges,
	})
	vaultGauge.frame.AnchorPoint = Vector2.new(0, 1)
	vaultGauge.frame.Position = UDim2.fromScale(0, 1)
	vaultGauge.frame.Parent = vaultHolder
	local scoreLabel = Panel.label("", 16, Theme.text)
	scoreLabel.Position = UDim2.new(0.35, 0, 0, 0)
	scoreLabel.Size = UDim2.new(0.25, 0, 0, 24)
	scoreLabel.Font = Theme.fontNumbers
	scoreLabel.Parent = gauges
	local modesRow = Create("Frame", {
		Position = UDim2.new(0.6, 0, 0, 0),
		Size = UDim2.new(0.4, 0, 1, 0),
		BackgroundTransparency = 1,
		Parent = gauges,
	}, {
		Layout = Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }),
	})

	local function sorted(items: { Types.ItemInstance }): { Types.ItemInstance }
		local list = table.clone(items)
		table.sort(list, function(a, b)
			if sortMode == "condition" then
				return (a.condition or 0) > (b.condition or 0)
			elseif sortMode == "value" then
				return ItemRules.value(a) > ItemRules.value(b)
			end
			local infoA, infoB = ItemCatalog.get(a.itemId), ItemCatalog.get(b.itemId)
			local orderA = if infoA then CATEGORY_ORDER[infoA.category] or 99 else 99
			local orderB = if infoB then CATEGORY_ORDER[infoB.category] or 99 else 99
			if orderA ~= orderB then
				return orderA < orderB
			end
			return a.itemId < b.itemId
		end)
		return list
	end

	local function slotFor(view: Types.ProfileView, itemId: string): Types.SlotName?
		local info = ItemCatalog.get(itemId)
		if info == nil then
			return nil
		end
		local fallback: any = nil
		for _, slot in SLOTS :: { any } do
			if (ItemCatalog.slotCategories :: any)[slot] == info.category then
				if (view.loadout :: any)[slot] == nil then
					return slot
				end
				fallback = fallback or slot
			end
		end
		return fallback
	end

	local function render(view: Types.ProfileView)
		current = view
		panel.title.Text = t("vault.title")
		refreshPreview()
		Panel.clear(vaultList)
		Panel.clear(sortRow)
		Panel.clear(modesRow)

		-- Ce qui est porté : zones (mise à jour ciblée, sans tout reconstruire).
		loadout.refreshTexts()
		loadout.set(
			view.loadout :: any,
			view.bag,
			ItemRules.totalUp(view.bag),
			ItemRules.bagCapacity(view.loadout.backpack)
		)

		for index, mode in { "type", "condition", "value" } do
			local button =
				Panel.button(t("vault.sort." .. mode), if sortMode == mode then Theme.magenta else Theme.textDim, 110)
			button.LayoutOrder = index
			button.Parent = sortRow
			button.Activated:Connect(function()
				sortMode = mode
				if current then
					render(current)
				end
			end)
		end

		for index, item in sorted(view.vault) do
			local actions: { ItemCard.Action } = {}
			local slot = slotFor(view, item.itemId)
			if slot then
				table.insert(actions, {
					label = t("inventory.action.equip"),
					callback = function()
						vaultAction("equip", item.uid, slot)
					end,
				})
			end
			-- Au sac : grisé, avec l'espace manquant, si l'objet ne tient pas.
			local fit = SpaceCheck.vaultToBag(view.bag, view.loadout.backpack, item)
			table.insert(actions, {
				label = t("vault.toBag"),
				color = Theme.green,
				disabled = not fit.fits,
				callback = function()
					vaultAction("toBag", item.uid)
				end,
			})
			table.insert(actions, {
				label = t("inventory.action.drop"),
				color = Theme.red,
				callback = function()
					ConfirmDialog.ask(
						parent,
						t("vault.confirmDiscard", { item = ItemCard.title(item, t) }),
						t("common.confirm"),
						t("common.cancel"),
						function()
							vaultAction("discard", item.uid)
						end
					)
				end,
			})
			local card = ItemCard.create(
				item,
				t,
				actions,
				index,
				if fit.fits then nil else { warning = t("fit.bag", { up = fit.missing }) }
			)
			card.Parent = vaultList
			DragDrop.attach(card, { from = "vault", uid = item.uid, itemId = item.itemId })
		end
		if #view.vault == 0 then
			Panel.label(t("inventory.empty"), 14, Theme.textDim).Parent = vaultList
		end

		-- Jauges : coffre (bien en vue, message quand il est plein), SE et modes accessibles.
		local used = ItemRules.totalUp(view.vault)
		vaultGauge.set(used, view.vaultCapacity)
		local score = ItemRules.equipmentScore(view.loadout, view.bag)
		scoreLabel.Text = t("vault.score", { score = score })
		for index, modeId in Config.Modes.list do
			local ok = ItemRules.modeAccess(score, modeId)
			Create("TextLabel", {
				LayoutOrder = index,
				Size = UDim2.fromOffset(100, 40),
				BackgroundColor3 = Theme.panel,
				BackgroundTransparency = if ok then 0.1 else 0.6,
				Font = Theme.fontTitle,
				TextSize = 14,
				TextColor3 = if ok then Theme.green else Theme.textDim,
				Text = t("mode." .. modeId),
				Parent = modesRow,
			}, {
				Stroke = Create("UIStroke", { Color = if ok then Theme.green else Theme.textDim, Transparency = 0.5 }),
			})
		end
	end

	-- Glisser-déposer (PC) : coffre ↔ équipement ↔ sac préparé.
	-- Les cases d'équipement et la grille du sac sont déclarées par LoadoutView.
	DragDrop.target(vaultList, "vault")
	DragDrop.Dropped:Connect(function(payload: any, target: string)
		local view = current
		if view == nil or not panel:isOpen() or type(payload) ~= "table" or payload.uid == nil then
			return
		end
		if payload.from == "vault" and target == "equipped" then
			local slot = slotFor(view, payload.itemId)
			if slot then
				vaultAction("equip", payload.uid, slot)
			end
		elseif payload.from == "vault" and target == "bag" then
			vaultAction("toBag", payload.uid)
		elseif payload.from == "bag" and target == "vault" then
			vaultAction("fromBag", payload.uid)
		elseif payload.from == "equipped" and target == "vault" then
			vaultAction("unequip", nil, payload.slot)
		end
	end)

	return { panel = panel, render = render }
end

return VaultScreen
