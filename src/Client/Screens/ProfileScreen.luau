--!strict
--[[
	ProfileScreen : profil et classement (section 17.3, écran 16).

	- Profil : niveau et barre d'XP, rang de la saison, statistiques,
	  meilleurs scores par mode, historique des saisons.
	- Top 10 : les 10 meilleures parties de la saison, avec le détail de
	  chaque score (kills, mercenaires, robots, loot, extrait ou mort).
	- Classements (P10) : mondial, amis, par mode et défi quotidien du stand
	  de tir, demandés au serveur (mis en cache 30 s côté client).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Types = require(Shared.Types)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
local Panel = require(script.Parent.Parent.UI.Panel)
local Theme = require(script.Parent.Parent.UI.Theme)

type Translate = (key: string, params: { [string]: any }?) -> string

local ProfileScreen = {}

export type Screen = {
	panel: Panel.Panel,
	render: (view: Types.ProfileView) -> (),
	showTab: (tab: string, board: string?) -> (),
}

local TABS = { "profile", "top10", "leaderboards" }
local STATS = { "matchesPlayed", "extractions", "deaths", "playerKills", "botKills", "robotKills" }
-- Classements : mondial, amis, un par mode, défi quotidien du stand de tir.
local BOARDS = { "season", "friends", "mode:easy", "mode:medium", "mode:hard", "range" }
local BOARD_CACHE_SECONDS = 30

type BoardResult = { [string]: any }
local boardCache: { [string]: { at: number, result: BoardResult? } } = {}
local boardLoading: { [string]: boolean } = {}

function ProfileScreen.create(parent: Instance, t: Translate, displayName: string): Screen
	local panel = Panel.create("ProfileScreen", parent, Theme.cyan)
	local tab = "profile"
	local boardKey = "season"
	local lastView: Types.ProfileView? = nil
	local render: (view: Types.ProfileView) -> ()

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

	-- Demande un classement au serveur (une seule demande en cours par classement).
	local function fetchBoard(key: string)
		if boardLoading[key] then
			return
		end
		boardLoading[key] = true
		task.spawn(function()
			local kind, modeId = string.match(key, "^(%w+):?(%w*)$")
			local ok, result = pcall(ClientNet.invoke, "LeaderboardRequest", kind, if modeId ~= "" then modeId else nil)
			boardCache[key] = { at = os.clock(), result = if ok and type(result) == "table" then result else nil }
			boardLoading[key] = nil
			local view = lastView
			if view and tab == "leaderboards" and boardKey == key and panel:isOpen() then
				render(view)
			end
		end)
	end

	local function boardLabel(key: string): string
		local kind, modeId = string.match(key, "^(%w+):?(%w*)$")
		if kind == "mode" and modeId then
			return t("mode." .. modeId)
		end
		return t("board.kind." .. (kind or "season"))
	end

	local function boardRow(row: { [string]: any }, mine: boolean)
		order += 1
		local podium = row.position <= 3
		Create("Frame", {
			LayoutOrder = order,
			Size = UDim2.new(1, -8, 0, 34),
			BackgroundColor3 = if mine then Theme.background else Theme.panel,
			BackgroundTransparency = 0.2,
			Parent = list,
		}, {
			Stroke = Create("UIStroke", {
				Color = if mine then Theme.cyan elseif podium then Theme.orange else Theme.textDim,
				Transparency = if mine or podium then 0.2 else 0.7,
			}),
			Position = Create("TextLabel", {
				Position = UDim2.fromOffset(8, 0),
				Size = UDim2.new(0, 56, 1, 0),
				BackgroundTransparency = 1,
				Font = Theme.fontNumbers,
				TextSize = 18,
				TextColor3 = if podium then Theme.orange else Theme.text,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "#" .. tostring(row.position),
			}),
			Name = Create("TextLabel", {
				Position = UDim2.fromOffset(68, 0),
				Size = UDim2.new(1, -200, 1, 0),
				BackgroundTransparency = 1,
				Font = Theme.fontText,
				TextSize = 16,
				TextColor3 = if mine then Theme.cyan else Theme.text,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = tostring(row.name),
			}),
			Score = Create("TextLabel", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -8, 0, 0),
				Size = UDim2.new(0, 120, 1, 0),
				BackgroundTransparency = 1,
				Font = Theme.fontNumbers,
				TextSize = 18,
				TextColor3 = Theme.cyan,
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = tostring(row.score),
			}),
		})
	end

	local function renderLeaderboards()
		order += 1
		local picker = Create("Frame", {
			LayoutOrder = order,
			Size = UDim2.new(1, -8, 0, 40),
			BackgroundTransparency = 1,
			Parent = list,
		}, {
			Layout = Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		for index, key in BOARDS do
			local button = Panel.button(boardLabel(key), if boardKey == key then Theme.cyan else Theme.textDim, 104)
			button.LayoutOrder = index
			button.TextSize = 14
			button.Parent = picker
			button.Activated:Connect(function()
				boardKey = key
				local view = lastView
				if view then
					render(view)
				end
			end)
		end

		local cached = boardCache[boardKey]
		if cached == nil or os.clock() - cached.at > BOARD_CACHE_SECONDS then
			fetchBoard(boardKey)
		end
		if cached == nil then
			line(t("board.loading"), 15, Theme.textDim)
			return
		end
		local result = cached.result
		if result == nil or not result.available then
			line(t("board.unavailable"), 15, Theme.orange)
			return
		end
		if result.kind == "range" then
			line(t("board.rangeHint"), 14, Theme.textDim)
		elseif result.season and result.season > 0 then
			line(t("profile.season", { season = result.season }), 14, Theme.textDim)
		else
			line(t("board.preseason"), 14, Theme.textDim)
		end
		local entries = result.entries :: { { [string]: any } }
		if #entries == 0 then
			line(t("board.empty"), 15, Theme.textDim)
		end
		local me = Players.LocalPlayer.UserId
		local listed = false
		for _, row in entries do
			local mine = row.userId == me
			listed = listed or mine
			boardRow(row, mine)
		end
		if not listed and type(result.me) == "table" then
			line(t("board.me", { score = result.me.score or 0 }), 15, Theme.cyan)
		end
	end

	render = function(view: Types.ProfileView)
		lastView = view
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
			renderLeaderboards()
		end
	end

	local function showTab(key: string, board: string?)
		tab = key
		if board and table.find(BOARDS, board) then
			boardKey = board
		end
	end

	return { panel = panel, render = render, showTab = showTab }
end

return ProfileScreen
