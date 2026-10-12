--!strict
--[[
	RangeScreen : le Stand de tir (section 16.4).

	- Défi du jour : arme imposée (identique pour tous), durée, remise à zéro,
	  bouton de lancement et accès au classement quotidien.
	- Essai : les armes à distance du joueur (coffre, équipement, sac), à
	  tester sur les cibles mobiles avec une copie prêtée.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local RangeRules = require(Shared.Progression.RangeRules)
local Types = require(Shared.Types)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Panel = require(script.Parent.Parent.UI.Panel)
local Theme = require(script.Parent.Parent.UI.Theme)

type Translate = (key: string, params: { [string]: any }?) -> string

local RangeScreen = {}

export type Screen = {
	panel: Panel.Panel,
	render: (view: Types.ProfileView) -> (),
	setSession: (mode: string?) -> (),
	onLeaderboard: (() -> ())?,
}

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

function RangeScreen.create(parent: Instance, t: Translate): Screen
	local panel = Panel.create("RangeScreen", parent, Theme.orange)
	local content = Panel.list("Content")
	content.Size = UDim2.fromScale(1, 1)
	content.Parent = panel.body
	local session: string? = nil
	local lastView: Types.ProfileView? = nil
	local screen: Screen

	local order = 0
	local function add(instance: GuiObject)
		order += 1
		instance.LayoutOrder = order
		instance.Parent = content
	end
	local function line(text: string, size: number?, color: Color3?): TextLabel
		local label = Panel.label(text, size or 15, color or Theme.text)
		add(label)
		return label
	end

	-- Armes à distance possédées (sans doublon d'uid).
	local function ownedWeapons(view: Types.ProfileView): { Types.ItemInstance }
		local list: { Types.ItemInstance } = {}
		local seen: { [string]: boolean } = {}
		local function consider(item: Types.ItemInstance?)
			if item and not seen[item.uid] then
				local info = ItemCatalog.get(item.itemId)
				if info and info.category == "ranged" then
					seen[item.uid] = true
					table.insert(list, item)
				end
			end
		end
		consider(view.loadout.ranged)
		for _, item in view.bag do
			consider(item)
		end
		for _, item in view.vault do
			consider(item)
		end
		return list
	end

	local function render(view: Types.ProfileView)
		lastView = view
		panel.title.Text = t("station.range")
		Panel.clear(content)
		order = 0

		local now = os.time()
		local day = RangeRules.day(now)
		local weapon = RangeRules.weaponOfDay(day)
		line(t("range.challengeTitle"), 20, Theme.orange).Font = Theme.fontTitle
		line(t("range.challengeWeapon", { weapon = t("item." .. weapon) }), 17, Theme.cyan)
		line(t("range.challengeRules", { seconds = Config.Range.challenge.duration }), 14, Theme.textDim)
		line(t("range.reset", { time = clock(RangeRules.nextResetAt(now) - now) }), 14, Theme.textDim)
		if session == "challenge" then
			line(t("range.challengeRunning"), 15, Theme.orange)
		else
			local start = Panel.button(t("range.start"), Theme.orange, 260)
			add(start)
			start.Activated:Connect(function()
				ClientNet.fire("RangeAction", "challenge")
				panel:close()
			end)
		end
		local board = Panel.button(t("range.leaderboard"), Theme.cyan, 260)
		add(board)
		board.Activated:Connect(function()
			local callback = screen.onLeaderboard
			if callback then
				callback()
			end
		end)

		line(t("range.testTitle"), 20, Theme.cyan).Font = Theme.fontTitle
		line(t("range.testHint"), 14, Theme.textDim)
		if session ~= nil then
			local stop = Panel.button(t("range.stop"), Theme.red, 260)
			add(stop)
			stop.Activated:Connect(function()
				ClientNet.fire("RangeAction", "stop")
			end)
		end
		local weapons = ownedWeapons(view)
		if #weapons == 0 then
			line(t("range.noWeapon"), 14, Theme.textDim)
		end
		for _, item in weapons do
			local condition = Config.Conditions.list[item.condition or 1]
			local label = t("item." .. item.itemId)
				.. (if condition then "  ·  " .. t("condition." .. condition.key) else "")
			local button = Panel.button(t("range.try", { weapon = label }), Theme.text, 420)
			add(button)
			button.Activated:Connect(function()
				ClientNet.fire("RangeAction", "test", item.uid)
				panel:close()
			end)
		end
	end

	local function setSession(mode: string?)
		session = mode
		local view = lastView
		if view and panel:isOpen() then
			render(view)
		end
	end

	screen = { panel = panel, render = render, setSession = setSession, onLeaderboard = nil }
	return screen
end

return RangeScreen
