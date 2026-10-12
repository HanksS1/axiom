--!strict
--[[
	DeployScreen : Porte de déploiement (section 17.3, écran 10).

	- Choix du mode (grisé avec la raison s'il est inaccessible : « SE trop
	  élevé : 2 450 / 2 000 max »), Solo / Duo, invitation d'un ami.
	- Option crossplay (verrouillée, avec une explication, pour un duo de
	  deux plateformes différentes).
	- Rappel de l'assurance choisie et de l'objet temporaire actif.
	- Le serveur revérifie tout (éligibilité, groupe, plateformes).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemRules = require(Shared.Items.ItemRules)
local Matchmaking = require(Shared.Match.Matchmaking)
local Pricing = require(Shared.Economy.Pricing)
local Types = require(Shared.Types)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
local Panel = require(script.Parent.Parent.UI.Panel)
local Theme = require(script.Parent.Parent.UI.Theme)

type Translate = (key: string, params: { [string]: any }?) -> string

local DeployScreen = {}

export type Screen = {
	panel: Panel.Panel,
	render: (view: Types.ProfileView) -> (),
	setParty: (party: Types.PartyView?) -> (),
	setPlatform: (platform: string) -> (),
}

local player = Players.LocalPlayer

-- Raison d'un refus pour soi-même (texte court sous la carte du mode).
local function refusalText(t: Translate, refusal: Matchmaking.Refusal): string
	local params: { [string]: any } = refusal.params or {}
	if refusal.reason == "score_too_low" then
		return t("mode.refused.score_too_low", { score = params.score, limit = params.min })
	elseif refusal.reason == "score_too_high" then
		return t("mode.refused.score_too_high", { score = params.score, limit = params.max })
	elseif refusal.reason == "level" then
		return t("mode.refused.level_too_low", { limit = params.required })
	end
	return t("deploy.reason." .. refusal.reason)
end

function DeployScreen.create(parent: Instance, t: Translate): Screen
	local panel = Panel.create("DeployScreen", parent, Theme.red)
	local content = Panel.list("Content")
	content.Size = UDim2.fromScale(1, 1)
	content.Parent = panel.body

	local deployButton = Panel.button("", Theme.red, 260)
	deployButton.Parent = panel.footer

	local selectedMode: string? = nil
	local format: Matchmaking.Format = "solo"
	local crossplay: boolean? = nil -- nil : valeur des paramètres
	local party: Types.PartyView? = nil
	local platform = "keyboard"
	local current: Types.ProfileView? = nil

	local render: (view: Types.ProfileView) -> ()

	local function rerender()
		local view = current
		if view then
			render(view)
		end
	end

	local function partyPlatforms(): { Matchmaking.Platform }
		local list: { Matchmaking.Platform } = {}
		if party then
			for _, member in party.members do
				table.insert(list, (member.platform or "keyboard") :: any)
			end
		else
			table.insert(list, platform :: any)
		end
		return list
	end

	local function isLeader(): boolean
		return party == nil or party.leaderUserId == player.UserId
	end

	local function row(order: number, height: number): Frame
		return Create("Frame", {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, height),
			BackgroundTransparency = 1,
			Parent = content,
		}, {
			Layout = Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 8),
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
	end

	local function toggle(text: string, active: boolean, color: Color3, width: number): TextButton
		local button =
			Panel.button((if active then "● " else "○ ") .. text, if active then color else Theme.textDim, width)
		return button
	end

	function render(view: Types.ProfileView)
		current = view
		panel.title.Text = t("station.deploy")
		Panel.clear(content)
		local score = Matchmaking.profileScore(view :: any)
		local member: Matchmaking.Member = { level = view.level, score = score, pendingLoot = #view.pendingLoot }
		if selectedMode and Matchmaking.refusal(member, selectedMode) then
			selectedMode = nil
		end

		local header = Panel.label(t("deploy.score", { score = score }), 18, Theme.text)
		header.LayoutOrder = 1
		header.Parent = content

		-- Modes : cartes avec plage de SE et raison éventuelle du refus.
		local modesRow = row(2, 96)
		for index, modeId in Config.Modes.list do
			local mode = Config.Modes.byId[modeId]
			local refusal = Matchmaking.refusal(member, modeId)
			if refusal == nil and selectedMode == nil then
				selectedMode = modeId
			end
			local chosen = selectedMode == modeId
			local range = if mode.maxScore
				then t("deploy.range", { min = mode.minScore, max = mode.maxScore })
				else t("deploy.rangeOpen", { min = mode.minScore })
			local card = Create("TextButton", {
				LayoutOrder = index,
				Size = UDim2.fromOffset(220, 90),
				BackgroundColor3 = Theme.panel,
				BackgroundTransparency = if chosen then 0 else 0.35,
				AutoButtonColor = refusal == nil,
				Text = "",
				Parent = modesRow,
			}, {
				Stroke = Create("UIStroke", {
					Color = if chosen then Theme.red elseif refusal then Theme.textDim else Theme.green,
					Thickness = if chosen then 2 else 1,
					Transparency = 0.2,
				}),
				Name_ = Create("TextLabel", {
					Position = UDim2.fromOffset(10, 6),
					Size = UDim2.new(1, -20, 0, 26),
					BackgroundTransparency = 1,
					Font = Theme.fontTitle,
					TextSize = 20,
					TextColor3 = if refusal then Theme.textDim else Theme.text,
					TextXAlignment = Enum.TextXAlignment.Left,
					Text = t("mode." .. modeId),
				}),
				Range = Create("TextLabel", {
					Position = UDim2.fromOffset(10, 34),
					Size = UDim2.new(1, -20, 0, 20),
					BackgroundTransparency = 1,
					Font = Theme.fontNumbers,
					TextSize = 14,
					TextColor3 = Theme.textDim,
					TextXAlignment = Enum.TextXAlignment.Left,
					Text = range,
				}),
				Reason = Create("TextLabel", {
					Position = UDim2.fromOffset(10, 58),
					Size = UDim2.new(1, -20, 0, 24),
					BackgroundTransparency = 1,
					Font = Theme.fontText,
					TextSize = 14,
					TextWrapped = true,
					TextColor3 = if refusal then Theme.orange else Theme.green,
					TextXAlignment = Enum.TextXAlignment.Left,
					Text = if refusal then refusalText(t, refusal) else t("deploy.accessible"),
				}),
			})
			card.Activated:Connect(function()
				if refusal == nil then
					selectedMode = modeId
					rerender()
				end
			end)
		end

		-- Format, groupe et invitation.
		local partySize = if party then #party.members else 1
		if partySize >= 2 then
			format = "duo"
		elseif format == "duo" then
			format = "solo"
		end
		local formatRow = row(3, 48)
		local solo = toggle(t("mode.format.solo"), format == "solo", Theme.cyan, 140)
		solo.LayoutOrder = 1
		solo.Parent = formatRow
		local duo = toggle(t("mode.format.duo"), format == "duo", Theme.cyan, 140)
		duo.LayoutOrder = 2
		duo.Parent = formatRow
		solo.Activated:Connect(function()
			if partySize >= 2 then
				ClientNet.fire("PartyLeave")
			end
		end)
		local invite = Panel.button(t("deploy.inviteFriend"), Theme.magenta, 200)
		invite.LayoutOrder = 3
		invite.Parent = formatRow
		invite.Activated:Connect(function()
			pcall(function()
				SocialService:PromptGameInvite(player)
			end)
		end)
		if party then
			local leave = Panel.button(t("party.leave"), Theme.textDim, 160)
			leave.LayoutOrder = 4
			leave.Parent = formatRow
			leave.Activated:Connect(function()
				ClientNet.fire("PartyLeave")
			end)
		end
		local partyText: string
		if party and #party.members >= 2 then
			local names = {}
			for _, partyMember in party.members do
				table.insert(names, partyMember.name)
			end
			partyText = t("deploy.partyWith", { names = table.concat(names, " · ") })
		else
			partyText = t("deploy.partyHint")
		end
		local partyLabel = Panel.label(partyText, 14, Theme.textDim)
		partyLabel.LayoutOrder = 4
		partyLabel.Parent = content
		duo.Activated:Connect(function()
			if partySize < 2 then
				partyLabel.Text = t("deploy.reason.need_partner")
				partyLabel.TextColor3 = Theme.orange
			end
		end)

		-- Crossplay (forcé pour un duo de deux plateformes différentes).
		local _, forced = Matchmaking.platformGroup(false, partyPlatforms())
		local wanted = if crossplay ~= nil then crossplay else view.settings.crossplay ~= false
		local effective = forced or wanted
		local crossRow = row(5, 48)
		local crossButton = toggle(t("deploy.crossplay"), effective, Theme.cyan, 220)
		crossButton.LayoutOrder = 1
		crossButton.Parent = crossRow
		crossButton.Activated:Connect(function()
			if not forced then
				crossplay = not wanted
				rerender()
			end
		end)
		local crossHint = Panel.label(
			if forced then t("deploy.crossplayForced") else t("deploy.platform." .. platform),
			14,
			Theme.textDim
		)
		crossHint.LayoutOrder = 2
		crossHint.Size = UDim2.new(1, -240, 1, 0)
		crossHint.Parent = crossRow

		-- Rappels : assurance et objet temporaire.
		local insuranceText: string
		local tier = view.insuranceTier
		if tier then
			local bag = table.clone(view.bag)
			if view.tempItem then
				table.insert(bag, view.tempItem)
			end
			local cost = Pricing.insuranceCost(tier, ItemRules.equipmentScore(view.loadout, bag)) or 0
			insuranceText = t("deploy.insurance", { tier = t("insurer.tier." .. tier), credits = cost })
		else
			insuranceText = t("deploy.noInsurance")
		end
		local insuranceLabel = Panel.label(insuranceText, 15, if tier then Theme.cyan else Theme.orange)
		insuranceLabel.LayoutOrder = 6
		insuranceLabel.Parent = content
		local temp = view.tempItem
		if temp then
			local tempLabel = Panel.label(
				t("deploy.tempItem", { item = t("item." .. temp.itemId), games = temp.tempGamesLeft or 0 }),
				15,
				Theme.green
			)
			tempLabel.LayoutOrder = 7
			tempLabel.Parent = content
		end

		-- Bouton de départ.
		local canDeploy = selectedMode ~= nil and isLeader() and (format == "solo" or partySize >= 2)
		deployButton.Text = if not isLeader() then t("deploy.waitLeader") else t("deploy.go")
		deployButton.TextColor3 = if canDeploy then Theme.red else Theme.textDim
		deployButton.AutoButtonColor = canDeploy
	end

	deployButton.Activated:Connect(function()
		local view = current
		if view == nil or selectedMode == nil or not isLeader() then
			return
		end
		local _, forced = Matchmaking.platformGroup(false, partyPlatforms())
		local wanted = if crossplay ~= nil then crossplay else view.settings.crossplay ~= false
		ClientNet.fire("QueueJoin", selectedMode, format, forced or wanted)
		panel:close()
	end)

	local function setParty(newParty: Types.PartyView?)
		party = newParty
		rerender()
	end

	local function setPlatform(newPlatform: string)
		platform = newPlatform
		rerender()
	end

	return { panel = panel, render = render, setParty = setParty, setPlatform = setPlatform }
end

return DeployScreen
