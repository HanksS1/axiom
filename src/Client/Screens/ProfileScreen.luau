--!strict
--[[
	ProfileScreen : profil et classement (section 17.3, écran 16).

	- Profil : niveau et barre d'XP, rang de la saison, statistiques,
	  meilleurs scores par mode, historique des saisons.
	- Top 10 : les 10 meilleures parties de la saison, avec le détail de
	  chaque score (kills, mercenaires, robots, loot, extrait ou mort).
	- Classements (mondial, amis, par mode) : avec les saisons (P10).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Types = require(Shared.Types)

local Create = require(script.Parent.Parent.UI.Create)
local Panel = require(script.Parent.Parent.UI.Panel)
local Theme = require(script.Parent.Parent.UI.Theme)

type Translate = (key: string, params: { [string]: any }?) -> string

local ProfileScreen = {}

export type Screen = {
	panel: Panel.Panel,
	render: (view: Types.ProfileView) -> (),
}

local TABS = { "profile", "top10", "leaderboards" }
local STATS = { "matchesPlayed", "extractions", "deaths", "playerKills", "botKills", "robotKills" }

function ProfileScreen.create(parent: Instance, t: Translate, displayName: string): Screen
	local panel = Panel.create("ProfileScreen", parent, Theme.cyan)
	local tab = "profile"

	local tabs = Panel.list("Tabs")
	tabs.Size = UDim2.new(1, 0, 0, 48)
	tabs.ScrollingEnabled = false
	(tabs:FindFirstChildOfClass("UIListLayout") :: UIListLayout).FillDirection = Enum.FillDirection.Horizontal
	tabs.Parent = panel.body
	local list = Panel.list("Content")
	list.Position = UDim2.fromOffset(0, 54)
	list.Size = UDim2.new(1, 0, 1, -54)
	list.Parent = panel.body

	local order = 0
	local function line(text: string, size: number?, color: Color3?): TextLabel
		order += 1
		local label = Panel.label(text, size or 16, color or Theme.text)
		label.LayoutOrder = order
		label.Parent = list
		return label
	end

	local function renderProfile(view: Types.ProfileView)
		line(displayName, 24, Theme.cyan).Font = Theme.fontTitle
		line(t("common.level", { level = view.level }) .. "  ·  " .. t("profile.xp", {
			xp = view.xp,
			next = view.xpToNext,
		}), 16)
		order += 1
		Create("Frame", {
			LayoutOrder = order,
			Size = UDim2.new(1, -8, 0, 10),
			BackgroundColor3 = Theme.background,
			BorderSizePixel = 0,
			Parent = list,
		}, {
			Fill = Create("Frame", {
				Size = UDim2.fromScale(math.clamp(view.xp / math.max(1, view.xpToNext), 0, 1), 1),
				BackgroundColor3 = Theme.green,
				BorderSizePixel = 0,
			}),
		})
		line(t("profile.rank", { rank = t("rank." .. view.rank), score = view.rankingScore }), 18, Theme.orange)
		line(t("profile.season", { season = view.seasonId }), 14, Theme.textDim)

		line(t("profile.statsTitle"), 18, Theme.cyan).Font = Theme.fontTitle
		for _, key in STATS do
			line(t("profile.stat." .. key, { value = view.stats[key] or 0 }), 15)
		end

		line(t("profile.bestTitle"), 18, Theme.cyan).Font = Theme.fontTitle
		for _, modeId in Config.Modes.list do
			line(t("profile.best", { mode = t("mode." .. modeId), score = view.bestScoreByMode[modeId] or 0 }), 15)
		end

		line(t("profile.historyTitle"), 18, Theme.cyan).Font = Theme.fontTitle
		if #view.seasonHistory == 0 then
			line(t("profile.historyEmpty"), 14, Theme.textDim)
		end
		for _, entry in view.seasonHistory do
			line(t("profile.historyEntry", { season = entry.id, rank = t("rank." .. entry.rank) }), 15)
		end
	end

	local function renderTop10(view: Types.ProfileView)
		line(t("profile.top10Hint", { score = view.rankingScore }), 14, Theme.textDim)
		if #view.top10 == 0 then
			line(t("profile.top10Empty"), 15, Theme.textDim)
			return
		end
		for index, game in view.top10 do
			order += 1
			local detail = game.detail
			local detailText = if detail
				then t("profile.detail", {
					kills = detail.kills,
					bots = detail.bots,
					robots = detail.robots,
					loot = detail.loot,
					outcome = t(if detail.extracted then "result.extracted" else "result.dead"),
				})
				else ""
			Create("Frame", {
				LayoutOrder = order,
				Size = UDim2.new(1, -8, 0, 54),
				BackgroundColor3 = Theme.panel,
				BackgroundTransparency = 0.2,
				Parent = list,
			}, {
				Stroke = Create(
					"UIStroke",
					{ Color = if index == 1 then Theme.orange else Theme.textDim, Transparency = 0.5 }
				),
				Rank = Create("TextLabel", {
					Position = UDim2.fromOffset(8, 0),
					Size = UDim2.new(0, 40, 1, 0),
					BackgroundTransparency = 1,
					Font = Theme.fontNumbers,
					TextSize = 22,
					TextColor3 = if index == 1 then Theme.orange else Theme.text,
					Text = "#" .. index,
				}),
				Score = Create("TextLabel", {
					Position = UDim2.fromOffset(56, 4),
					Size = UDim2.new(0.4, 0, 0, 24),
					BackgroundTransparency = 1,
					Font = Theme.fontNumbers,
					TextSize = 20,
					TextColor3 = Theme.cyan,
					TextXAlignment = Enum.TextXAlignment.Left,
					Text = t("profile.score", { score = game.score }),
				}),
				Mode = Create("TextLabel", {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -8, 0, 4),
					Size = UDim2.new(0.4, 0, 0, 24),
					BackgroundTransparency = 1,
					Font = Theme.fontText,
					TextSize = 14,
					TextColor3 = Theme.textDim,
					TextXAlignment = Enum.TextXAlignment.Right,
					Text = t("mode." .. game.mode) .. "  ·  " .. os.date("%d/%m", game.date),
				}),
				Detail = Create("TextLabel", {
					Position = UDim2.fromOffset(56, 28),
					Size = UDim2.new(1, -64, 0, 22),
					BackgroundTransparency = 1,
					Font = Theme.fontText,
					TextSize = 13,
					TextColor3 = Theme.textDim,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Text = detailText,
				}),
			})
		end
	end

	local function render(view: Types.ProfileView)
		panel.title.Text = t("station.profile")
		Panel.clear(tabs)
		Panel.clear(list)
		order = 0
		for index, key in TABS do
			local button = Panel.button(t("profile.tab." .. key), if tab == key then Theme.cyan else Theme.textDim, 170)
			button.LayoutOrder = index
			button.Parent = tabs
			button.Activated:Connect(function()
				tab = key
				render(view)
			end)
		end
		if tab == "profile" then
			renderProfile(view)
		elseif tab == "top10" then
			renderTop10(view)
		else
			line(t("profile.leaderboardsSoon"), 16, Theme.textDim)
		end
	end

	return { panel = panel, render = render }
end

return ProfileScreen
