--!strict
--[[
	DeployScreen : Porte de déploiement (section 17.3, écran 10).

	- Choix du mode (grisé avec la raison s'il est inaccessible : « SE trop
	  élevé : 2 450 / 2 000 max »), Solo / Duo, invitation d'un ami.
	- Option crossplay (verrouillée, avec une explication, pour un duo de
	  deux plateformes différentes).
	- Rappel de l'assurance choisie et de l'objet temporaire actif.
	- Cartes : on coche les cartes acceptées (au moins une) ; la partie part
	  sur l'une d'elles, tirée au sort parmi celles qui réunissent le plus de
	  joueurs. Chaque carte montre sa vignette et le nombre de joueurs en file
	  qui l'acceptent (même mode, même format) : de quoi raccourcir l'attente.
	- Le serveur revérifie tout (éligibilité, groupe, plateformes, cartes).
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
local MapThumbnail = require(script.Parent.Parent.UI.MapThumbnail)
local Panel = require(script.Parent.Parent.UI.Panel)
local Theme = require(script.Parent.Parent.UI.Theme)

type Translate = (key: string, params: { [string]: any }?) -> string

local DeployScreen = {}

export type Screen = {
	panel: Panel.Panel,
	render: (view: Types.ProfileView) -> (),
	setParty: (party: Types.PartyView?) -> (),
	setPlatform: (platform: string) -> (),
	-- Joueurs en file par carte, reçus du serveur pour un mode et un format.
	setMapCounts: (modeId: string, format: string, counts: { [string]: number }) -> (),
	-- Appelé régulièrement : redemande les compteurs pendant que l'écran est ouvert.
	tick: () -> (),
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
	-- Cartes cochées (toutes par défaut) et compteurs de la file affichée.
	local selectedMaps: { [string]: boolean } = {}
	for _, mapId in Config.Maps.list do
		selectedMaps[mapId] = true
	end
	local mapCounts: { [string]: number } = {}
	local countsKey = "" -- mode:format des compteurs affichés
	local lastRequest = 0
	local requestedKey = ""
	-- Vignettes créées une seule fois (quelques centaines de cadres chacune).
	local thumbnails: { [string]: Frame } = {}

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

	local function effectiveCrossplay(view: Types.ProfileView): boolean
		local _, forced = Matchmaking.platformGroup(false, partyPlatforms())
		local wanted = if crossplay ~= nil then crossplay else view.settings.crossplay ~= false
		return forced or wanted
	end

	-- Demande au serveur les joueurs en file par carte (au plus toutes les 3 s, ou au changement).
	local function requestCounts(force: boolean)
		local view = current
		if view == nil or selectedMode == nil or not panel:isOpen() then
			return
		end
		local key = `{selectedMode}:{format}:{effectiveCrossplay(view)}`
		if not force and key == requestedKey and os.clock() - lastRequest < 3 then
			return
		end
		requestedKey = key
		lastRequest = os.clock()
		ClientNet.fire("QueueMapCounts", selectedMode, format, effectiveCrossplay(view))
	end

	local function selectedList(): { string }
		local list = {}
		for _, mapId in Config.Maps.list do
			if selectedMaps[mapId] then
				table.insert(list, mapId)
			end
		end
		return list
	end

	-- Carte d'une carte de jeu : vignette, nom, case à cocher, joueurs en file.
	local function mapCard(grid: Instance, mapId: string, order: number)
		local def = (Config.Maps.byId :: any)[mapId]
		local accent = if def and def.card then def.card.accent else Theme.cyan
		local chosen = selectedMaps[mapId] == true
		local card = Create("TextButton", {
			LayoutOrder = order,
			BackgroundColor3 = Theme.panel,
			BackgroundTransparency = if chosen then 0 else 0.4,
			AutoButtonColor = true,
			Text = "",
			Parent = grid,
		}, {
			Stroke = Create("UIStroke", {
				Color = if chosen then accent else Theme.textDim,
				Thickness = if chosen then 2 else 1,
				Transparency = if chosen then 0 else 0.5,
			}),
		})
		local thumbnail = thumbnails[mapId]
		if thumbnail == nil then
			thumbnail = MapThumbnail.create(mapId)
			thumbnails[mapId] = thumbnail
		end
		thumbnail.Position = UDim2.fromOffset(6, 6)
		thumbnail.Size = UDim2.new(1, -12, 0, 104)
		local dim = thumbnail:FindFirstChild("Dim")
		if dim == nil then
			dim = Create("Frame", {
				Name = "Dim",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.new(0, 0, 0),
				BorderSizePixel = 0,
				ZIndex = 2,
				Parent = thumbnail,
			})
		end
		(dim :: Frame).BackgroundTransparency = if chosen then 1 else 0.55
		thumbnail.Parent = card
		Create("TextLabel", {
			Position = UDim2.fromOffset(8, 114),
			Size = UDim2.new(1, -16, 0, 22),
			BackgroundTransparency = 1,
			Font = Theme.fontTitle,
			TextSize = 16,
			TextColor3 = if chosen then Theme.text else Theme.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = (if chosen then "☑ " else "☐ ") .. t("map." .. mapId),
			Parent = card,
		})
		local count = mapCounts[mapId] or 0
		Create("TextLabel", {
			Position = UDim2.fromOffset(8, 138),
			Size = UDim2.new(1, -16, 0, 18),
			BackgroundTransparency = 1,
			Font = Theme.fontNumbers,
			TextSize = 13,
			TextColor3 = if count > 0 then Theme.green else Theme.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = if count > 0 then t("deploy.mapQueue", { count = count }) else t("deploy.mapQueueNone"),
			Parent = card,
		})
		card.Activated:Connect(function()
			-- Au moins une carte reste cochée.
			if chosen and #selectedList() <= 1 then
				return
			end
			selectedMaps[mapId] = not chosen
			rerender()
		end)
	end

	function render(view: Types.ProfileView)
		current = view
		panel.title.Text = t("station.deploy")
		-- Les vignettes sont gardées : on les détache avant de vider la liste.
		for _, thumbnail in thumbnails do
			thumbnail.Parent = nil
		end
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
			else
				format = "solo"
				rerender()
			end
		end)
		duo.Activated:Connect(function()
			format = "duo"
			rerender()
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
		elseif format == "duo" then
			partyText = t("deploy.randomDuo")
		else
			partyText = t("deploy.partyHint")
		end
		local partyLabel = Panel.label(partyText, 14, Theme.textDim)
		partyLabel.LayoutOrder = 4
		partyLabel.Parent = content

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
		-- Cartes : sélection, vignettes et joueurs en file (même mode, même format).
		local mapsTitle = Panel.label(t("deploy.maps"), 16, Theme.text)
		mapsTitle.LayoutOrder = 6
		mapsTitle.Parent = content
		local mapsGrid = Create("Frame", {
			LayoutOrder = 7,
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = content,
		}, {
			Layout = Create("UIGridLayout", {
				CellSize = UDim2.fromOffset(196, 162),
				CellPadding = UDim2.fromOffset(8, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local key = `{selectedMode}:{format}`
		if key ~= countsKey then
			mapCounts = {}
		end
		for index, mapId in Config.Maps.list do
			mapCard(mapsGrid, mapId, index)
		end
		local mapsRow = row(8, 44)
		local all = Panel.button(t("deploy.mapsAll"), Theme.cyan, 200)
		all.LayoutOrder = 1
		all.Parent = mapsRow
		all.Activated:Connect(function()
			for _, mapId in Config.Maps.list do
				selectedMaps[mapId] = true
			end
			rerender()
		end)
		local mapsHint = Panel.label(t("deploy.mapsHint"), 13, Theme.textDim)
		mapsHint.LayoutOrder = 2
		mapsHint.Size = UDim2.new(1, -220, 1, 0)
		mapsHint.TextWrapped = true
		mapsHint.Parent = mapsRow
		task.defer(requestCounts, false)

		local insuranceLabel = Panel.label(insuranceText, 15, if tier then Theme.cyan else Theme.orange)
		insuranceLabel.LayoutOrder = 9
		insuranceLabel.Parent = content
		local temp = view.tempItem
		if temp then
			local tempLabel = Panel.label(
				t("deploy.tempItem", { item = t("item." .. temp.itemId), games = temp.tempGamesLeft or 0 }),
				15,
				Theme.green
			)
			tempLabel.LayoutOrder = 10
			tempLabel.Parent = content
		end

		-- Bouton de départ.
		local canDeploy = selectedMode ~= nil and isLeader() and (format == "duo" or partySize < 2)
		deployButton.Text = if not isLeader() then t("deploy.waitLeader") else t("deploy.go")
		deployButton.TextColor3 = if canDeploy then Theme.red else Theme.textDim
		deployButton.AutoButtonColor = canDeploy
	end

	deployButton.Activated:Connect(function()
		local view = current
		if view == nil or selectedMode == nil or not isLeader() then
			return
		end
		ClientNet.fire("QueueJoin", selectedMode, format, effectiveCrossplay(view), selectedList())
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

	local function setMapCounts(modeId: string, newFormat: string, counts: { [string]: number })
		if modeId ~= selectedMode or newFormat ~= format then
			return -- réponse à une ancienne demande
		end
		countsKey = `{modeId}:{newFormat}`
		mapCounts = counts
		if panel:isOpen() then
			rerender()
		end
	end

	local function tick()
		requestCounts(false)
	end

	return {
		panel = panel,
		render = render,
		setParty = setParty,
		setPlatform = setPlatform,
		setMapCounts = setMapCounts,
		tick = tick,
	}
end

return DeployScreen
