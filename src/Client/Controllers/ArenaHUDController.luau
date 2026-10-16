--!strict
--[[
	ArenaHUDController : HUD de l'Arène FFA.

	- Tableau des scores (côté droit, compact, translucide) : vos éliminations
	  et le top 5 de l'arène (FfaService, envoi regroupé). Visible seulement
	  dans l'arène. Afficher / masquer : action « scoreboard » (L, R3 à la
	  manette, remappable) ou toucher l'en-tête (tactile). Masqué, il laisse un
	  petit onglet « FFA ▸ ».
	- Bouclier de réapparition : « PROTÉGÉ … s » au-dessus du réticule tant
	  que la protection dure (attribut SpawnShieldUntil du personnage).
	Aucun panneau modal : le combat n'est jamais bloqué (pas de PanelState).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
local Theme = require(script.Parent.Parent.UI.Theme)
local HUDController = require(script.Parent.HUDController)
local InputController = require(script.Parent.InputController)
local ProfileController = require(script.Parent.ProfileController)

local ArenaHUDController = {}

local player = Players.LocalPlayer
local t = ProfileController.t

local WIDTH = 220
local ROW_HEIGHT = 20
local GOLD = Color3.fromRGB(255, 196, 64)

type View = { kills: number, top: { { name: string, kills: number, me: boolean } }, players: number }

local view: View? = nil
local expanded = true
local panel: Frame
local header: TextButton
local mine: TextLabel
local rows: { TextLabel } = {}
local empty: TextLabel
local tab: TextButton
local shieldLabel: TextLabel

local function inArena(): boolean
	return player:GetAttribute("Zone") == "arena"
end

local function render()
	local visible = inArena() and view ~= nil
	panel.Visible = visible and expanded
	tab.Visible = visible and not expanded
	if not visible then
		return
	end
	local current = view :: View
	header.Text = t("ffa.title")
	tab.Text = t("ffa.hidden")
	mine.Text = t("ffa.myKills", { kills = current.kills })
	for index, label in rows do
		local row = current.top[index]
		label.Visible = row ~= nil
		if row then
			label.Text = `{t("ffa.row", { rank = index, name = row.name })}  <font color="#EBF0F5">{row.kills}</font>`
			label.TextColor3 = if row.me then GOLD else Theme.textDim
		end
	end
	empty.Visible = current.players <= 1
	empty.Text = t("ffa.empty")
end

local function toggle()
	if inArena() then
		expanded = not expanded
		render()
	end
end

local function build()
	local root = HUDController.root()
	panel = Create("Frame", {
		Name = "FfaBoard",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.42, 0),
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = 0.45,
		Visible = false,
		Parent = root,
	}, {
		Corner = Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Padding = Create("UIPadding", {
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
		}),
		Layout = Create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	-- L'en-tête est un bouton : un appui le masque (tactile).
	header = Create("TextButton", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Font = Theme.fontTitle,
		TextSize = 14,
		TextColor3 = Theme.cyan,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutoButtonColor = false,
		Text = "",
		Parent = panel,
	})
	header.Activated:Connect(toggle)
	mine = Create("TextLabel", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT + 2),
		BackgroundTransparency = 1,
		Font = Theme.fontText,
		TextSize = 14,
		TextColor3 = Theme.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Parent = panel,
	})
	for index = 1, Config.Arena.scoreboard.top do
		rows[index] = Create("TextLabel", {
			LayoutOrder = 2 + index,
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
			BackgroundTransparency = 1,
			Font = Theme.fontNumbers,
			TextSize = 13,
			RichText = true,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
			Visible = false,
			Parent = panel,
		})
	end
	empty = Create("TextLabel", {
		LayoutOrder = 100,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		BackgroundTransparency = 1,
		Font = Theme.fontText,
		TextSize = 12,
		TextColor3 = Theme.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Visible = false,
		Parent = panel,
	})
	-- Onglet du tableau masqué (taille tactile minimale).
	tab = Create("TextButton", {
		Name = "FfaTab",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.42, 0),
		Size = UDim2.fromOffset(64, Theme.minButtonSize),
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = 0.45,
		Font = Theme.fontTitle,
		TextSize = 13,
		TextColor3 = Theme.cyan,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		Parent = root,
	}, {
		Corner = Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
	})
	tab.Activated:Connect(toggle)

	shieldLabel = Create("TextLabel", {
		Name = "SpawnShield",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.5, -48),
		Size = UDim2.fromOffset(420, 26),
		BackgroundTransparency = 1,
		Font = Theme.fontTitle,
		TextSize = 16,
		TextColor3 = Theme.cyan,
		TextStrokeTransparency = 0.5,
		Text = "",
		Visible = false,
		Parent = root,
	})
end

-- Protection en cours (heure serveur) : compte à rebours au-dessus du réticule.
local function updateShield()
	local character = player.Character
	local untilTime = if character then character:GetAttribute("SpawnShieldUntil") else nil
	local remaining = if type(untilTime) == "number" then untilTime - Workspace:GetServerTimeNow() else 0
	shieldLabel.Visible = remaining > 0
	if remaining > 0 then
		shieldLabel.Text = t("ffa.shield", { seconds = string.format("%.1f", remaining) })
	end
end

function ArenaHUDController.init() end

function ArenaHUDController.start()
	build()
	ClientNet.on("FfaBoard", function(payload: any)
		view = if type(payload) == "table" then payload :: View else nil
		render()
	end)
	player:GetAttributeChangedSignal("Zone"):Connect(render)
	InputController.Tapped:Connect(function(action)
		if action == "scoreboard" then
			toggle()
		end
	end)
	-- Le texte de protection change chaque image seulement quand il est affiché.
	RunService.RenderStepped:Connect(function()
		if shieldLabel.Visible or player.Character ~= nil and player.Character:GetAttribute("SpawnShieldUntil") then
			updateShield()
		end
	end)
end

return ArenaHUDController
