--!strict
--[[
	LeaderboardService : saisons, classements et Mur des Légendes (15.4, 16.4).

	- Saison : à chaque chargement de profil, le profil passe à la saison en
	  cours (rang final archivé, top 10 remis à zéro).
	- Classements (OrderedDataStore, un par saison) : mondial (somme du top 10),
	  par mode (meilleur score de partie de la saison), défi quotidien du stand
	  de tir. « Amis » = scores des amis Roblox lus un par un (nombre limité,
	  mis en cache, et seulement si le budget DataStore le permet).
	- Légende d'AXIOM : top 500 mondial de la saison (seuil relu toutes les
	  10 min) avec un score minimum ; acquis pour la saison une fois atteint.
	- Attributs publics `Level` et `Rank` sur chaque joueur (affichés
	  au-dessus des têtes dans le hub).
	- Mur des Légendes (hub) : le top 10 en hologrammes au-dessus du tableau.

	Sécurité : le client ne fait que DEMANDER un classement (limité en
	fréquence) ; il n'envoie jamais de score. Les scores viennent du profil
	tenu par le serveur.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Guard = require(Shared.Util.Guard)
local MatchRules = require(Shared.Match.MatchRules)
local Types = require(Shared.Types)

local PlaceRole = require(script.Parent.Parent.Matchmaking.PlaceRole)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local Boards = require(script.Parent.Parent.Progression.Boards)
local DataService = require(script.Parent.DataService)
local MatchService = require(script.Parent.MatchService)

local Season = Config.Progression.season
local L = Config.Progression.leaderboards

local LeaderboardService = {}

local KINDS = { "season", "friends", "mode", "range" }
local READ_RESERVE = 60
local FRIENDS_RESULT_SECONDS = 30
local DAY = 24 * 60 * 60
local HOLO_COLOR = Color3.fromRGB(0, 229, 255)
local CHAMPION_COLOR = Color3.fromRGB(255, 196, 64)

local useMemory = false
local boards: { [string]: Boards.Board } = {}
local names: { [number]: { name: string, at: number } } = {}
local friendsCache: { [Player]: { at: number, ids: { number } } } = {}
-- Classement « amis » : une seule demande en cours par joueur, résultat gardé 30 s.
local friendsResults: { [Player]: { at: number, result: { [string]: any }? } } = {}
local friendsPending: { [Player]: boolean } = {}
local legendFetchedAt = -math.huge
local legendThreshold: number? = nil

local function currentSeason(): number
	return MatchRules.seasonAt(os.time())
end

function LeaderboardService.today(): number
	return math.floor(os.time() / DAY)
end

local function board(name: string): Boards.Board
	local existing = boards[name]
	if existing then
		return existing
	end
	local store: Boards.StoreLike
	if useMemory then
		store = Boards.memoryStore()
	else
		store = DataStoreService:GetOrderedDataStore(L.storeName, name) :: any
	end
	-- Les classements d'autres saisons ou d'autres jours ne servent plus : on les oublie.
	local season = currentSeason()
	local today = LeaderboardService.today()
	for key in boards do
		local day = tonumber(string.match(key, "^range_(%d+)$"))
		local boardSeason = tonumber(string.match(key, "^s(%d+)"))
		if (day and day < today - 1) or (boardSeason and boardSeason ~= season) then
			boards[key] = nil
		end
	end
	local created = Boards.new(store, {
		clock = os.clock,
		topCacheSeconds = L.cacheSeconds,
		scoreCacheSeconds = L.friendScoreCacheSeconds,
		wait = task.wait,
	})
	boards[name] = created
	return created
end

-- Pour « range », `season` est le numéro du jour (UTC).
local function boardName(kind: string, season: number, modeId: string?): string
	if kind == "mode" and modeId then
		return `s{season}_{modeId}`
	elseif kind == "range" then
		return `range_{season}`
	end
	return `s{season}`
end

-- Budget de lecture DataStore restant (les amis se lisent un par un).
local function canRead(): boolean
	if useMemory then
		return true
	end
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)
	end)
	-- Réserve généreuse : les sauvegardes de profils puisent dans le même budget.
	return ok and budget > READ_RESERVE
end

-- Noms affichés (mis en cache ; les joueurs présents sont lus directement).
local function resolveNames(ids: { number })
	local now = os.clock()
	local missing = {}
	for _, userId in ids do
		local present = Players:GetPlayerByUserId(userId)
		if present then
			names[userId] = { name = present.DisplayName, at = now }
		else
			local known = names[userId]
			if (known == nil or now - known.at > L.nameCacheSeconds) and userId > 0 then
				table.insert(missing, userId)
			end
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	if ok and type(infos) == "table" then
		for _, info in infos :: { any } do
			if type(info.Id) == "number" and type(info.DisplayName) == "string" then
				names[info.Id] = { name = info.DisplayName, at = now }
			end
		end
	end
end

local function nameOf(userId: number): string
	local known = names[userId]
	return if known then known.name else `#{userId}`
end

-- Amis Roblox (limités, mis en cache 5 min).
local function friendIds(player: Player): { number }
	local cached = friendsCache[player]
	if cached and os.clock() - cached.at < L.friendScoreCacheSeconds then
		return cached.ids
	end
	local ids: { number } = {}
	if player.UserId > 0 then
		pcall(function()
			local pages = Players:GetFriendsAsync(player.UserId)
			while #ids < L.friendsLimit do
				for _, friend in pages:GetCurrentPage() do
					table.insert(ids, friend.Id)
					if #ids >= L.friendsLimit then
						break
					end
				end
				if pages.IsFinished then
					break
				end
				pages:AdvanceToNextPageAsync()
			end
		end)
	end
	if player.Parent == Players then
		friendsCache[player] = { at = os.clock(), ids = ids }
	end
	return ids
end

-- Légende d'AXIOM -------------------------------------------------------------------

local function qualifiesLegend(score: number): boolean
	local threshold = legendThreshold
	return threshold ~= nil and score > 0 and score >= math.max(threshold, Season.legendMinScore)
end

local function refreshLegendThreshold()
	local entries = board(boardName("season", currentSeason())):top(Season.legendTopCount)
	if entries == nil then
		return
	end
	legendFetchedAt = os.clock()
	-- Moins de 500 classés : tout joueur classé (au-dessus du minimum) est dans le top 500.
	legendThreshold = if #entries >= Season.legendTopCount then entries[Season.legendTopCount].score else 0
end

-- Attributs publics et statut de Légende -------------------------------------------

local function refreshPlayer(player: Player, profile: Types.Profile)
	if player.Parent ~= Players then
		return
	end
	local score = MatchRules.rankingScore(profile.season.top10)
	if not profile.season.legend and profile.season.id == currentSeason() and qualifiesLegend(score) then
		local reached = DataService.update(player, function(current)
			if current.season.legend or current.season.id ~= currentSeason() then
				return false
			end
			current.season.legend = true
			return true
		end)
		if reached then
			ServerNet.notify(player, "legend.reached")
		end
		profile = DataService.getProfile(player) or profile
	end
	player:SetAttribute("Level", profile.level)
	player:SetAttribute("Rank", MatchRules.seasonRank(profile.season))
end

local function submitSeason(player: Player, profile: Types.Profile)
	local score = MatchRules.rankingScore(profile.season.top10)
	if score > 0 and profile.season.id == currentSeason() then
		board(boardName("season", profile.season.id)):submit(player.UserId, score)
	end
end

local function onProfileLoaded(player: Player)
	DataService.update(player, function(profile)
		return MatchRules.rollSeason(profile, os.time())
	end)
	local profile = DataService.getProfile(player)
	if profile then
		refreshPlayer(player, profile)
		-- Rattrape une soumission qui aurait échoué lors d'une partie précédente.
		task.spawn(submitSeason, player, profile)
	end
end

local function onScoreRecorded(player: Player, modeId: string, score: number)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return
	end
	board(boardName("mode", profile.season.id, modeId)):submit(player.UserId, score)
	submitSeason(player, profile)
	-- Serveur de partie : seuil de Légende relu seulement quand un score arrive (et au plus toutes les 10 min).
	if os.clock() - legendFetchedAt > L.legendRefreshSeconds then
		refreshLegendThreshold()
	end
	local current = DataService.getProfile(player)
	if current then
		refreshPlayer(player, current)
	end
end

-- Score du défi quotidien du stand de tir (appelé par le stand).
-- Le défi compte pour le jour où il a commencé (même arme, mêmes cibles).
function LeaderboardService.submitRange(player: Player, day: number, score: number)
	task.spawn(function()
		board(boardName("range", day)):submit(player.UserId, score)
	end)
end

-- Demandes du client -----------------------------------------------------------------

type Row = { position: number, userId: number, name: string, score: number }

local function requestBoard(player: Player, kind: string, modeId: string?): { [string]: any }?
	if kind == "mode" and modeId == nil then
		return nil
	end
	local season = currentSeason()
	local target = board(boardName(kind, if kind == "range" then LeaderboardService.today() else season, modeId))
	local ranked: { { position: number, userId: number, score: number } }
	if kind == "friends" then
		-- Les amis sont lus sur le classement mondial de la saison.
		local entries: { Boards.Entry } = {}
		local ids = table.clone(friendIds(player))
		table.insert(ids, 1, player.UserId)
		for _, userId in ids do
			if not canRead() then
				break
			end
			local score = target:get(userId)
			if score and score > 0 then
				table.insert(entries, { userId = userId, score = score })
			end
		end
		ranked = Boards.rank(entries)
	else
		local entries = target:top(L.entries)
		if entries == nil then
			return { kind = kind, mode = modeId, season = season, available = false, entries = {} }
		end
		ranked = Boards.rank(entries)
	end

	local ids = {}
	for _, entry in ranked do
		table.insert(ids, entry.userId)
	end
	resolveNames(ids)
	local rows: { Row } = {}
	local mine: Row? = nil
	for _, entry in ranked do
		local row =
			{ position = entry.position, userId = entry.userId, name = nameOf(entry.userId), score = entry.score }
		table.insert(rows, row)
		if entry.userId == player.UserId then
			mine = row
		end
	end
	return {
		kind = kind,
		mode = modeId,
		season = season,
		day = if kind == "range" then LeaderboardService.today() else nil,
		available = true,
		entries = rows,
		me = mine or { score = if canRead() then target:get(player.UserId) or 0 else 0 },
	}
end

local function request(player: Player, kind: string, modeId: string?): { [string]: any }?
	if kind ~= "friends" then
		return requestBoard(player, kind, modeId)
	end
	local cached = friendsResults[player]
	if friendsPending[player] or (cached and os.clock() - cached.at < FRIENDS_RESULT_SECONDS) then
		return if cached then cached.result else nil
	end
	friendsPending[player] = true
	local ok, result = pcall(requestBoard, player, kind, modeId)
	friendsPending[player] = nil
	if player.Parent == Players then
		friendsResults[player] = { at = os.clock(), result = if ok then result else nil }
	end
	return if ok then result else nil
end

-- Mur des Légendes ----------------------------------------------------------------

local wallHolograms: { [number]: { userId: number, model: Model } } = {}
local wallRows: { TextLabel } = {}

local function legendsBoard(): BasePart?
	local terminus = Workspace:FindFirstChild("Terminus")
	local found = if terminus then terminus:FindFirstChild("LegendsBoard", true) else nil
	return if found and found:IsA("BasePart") then found else nil
end

local function buildWallList(wall: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Ranking"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.2
	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromScale(0.08, 0.3)
	list.Size = UDim2.fromScale(0.84, 0.66)
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	for index = 1, L.wallSize do
		local row = Instance.new("TextLabel")
		row.LayoutOrder = index
		row.Size = UDim2.fromScale(1, 1 / L.wallSize)
		row.BackgroundTransparency = 1
		row.TextScaled = true
		row.Font = if index == 1 then Enum.Font.GothamBlack else Enum.Font.Code
		row.TextColor3 = if index == 1 then CHAMPION_COLOR else HOLO_COLOR
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Text = `#{index}   —`
		row.Parent = list
		wallRows[index] = row
	end
	gui.Parent = wall
end

-- Transforme un avatar en hologramme immobile (aucun script, aucune collision).
local function hologramize(model: Model, color: Color3)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("Clothing") or descendant:IsA("ShirtGraphic") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			descendant.Material = Enum.Material.ForceField
			descendant.Color = color
			if descendant.Name == "HumanoidRootPart" then
				descendant.Transparency = 1
			end
		elseif descendant:IsA("Decal") then
			descendant.Color3 = color
			descendant.Transparency = 0.3
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
end

local function makeAvatar(userId: number): Model?
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromUserId(userId)
	end)
	if ok and model then
		return model
	end
	-- Comptes de test de Studio (identifiants négatifs) : silhouette générique.
	local fallbackOk, fallback = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	return if fallbackOk then fallback else nil
end

-- Position du n-ième hologramme : le champion au centre, les suivants de part et d'autre.
local function wallOffset(index: number): number
	if index == 1 then
		return 0
	end
	local side = if index % 2 == 0 then -1 else 1
	return side * math.floor(index / 2) * 3.2
end

local function placeHologram(wall: BasePart, index: number, userId: number, score: number)
	local champion = index == 1
	local model = makeAvatar(userId)
	if model == nil then
		return
	end
	model.Name = `Legend{index}`
	hologramize(model, if champion then CHAMPION_COLOR else HOLO_COLOR)
	pcall(function()
		model:ScaleTo(if champion then L.wallChampionScale else L.wallScale)
	end)
	local top = wall.CFrame * CFrame.new(wallOffset(index), wall.Size.Y / 2 + 0.3, 0)
	local facing = CFrame.lookAt(top.Position, top.Position - wall.CFrame.LookVector)
	local box, size = model:GetBoundingBox()
	local lift = model:GetPivot().Position.Y - box.Position.Y + size.Y / 2
	model:PivotTo(facing + Vector3.new(0, lift, 0))

	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local light = Instance.new("PointLight")
		light.Color = if champion then CHAMPION_COLOR else HOLO_COLOR
		light.Range = 6
		light.Brightness = 1.2
		light.Parent = head
		local plate = Instance.new("BillboardGui")
		plate.Size = UDim2.fromOffset(160, 40)
		plate.StudsOffsetWorldSpace = Vector3.new(0, 1.6, 0)
		plate.MaxDistance = 90
		plate.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = if champion then CHAMPION_COLOR else HOLO_COLOR
		label.TextStrokeTransparency = 0.4
		label.Text = `#{index} {nameOf(userId)}\n{score}`
		label.Parent = plate
		plate.Parent = head
	end
	model:SetAttribute("UserId", userId)
	model:AddTag("Hologram")
	model.Parent = wall.Parent
	wallHolograms[index] = { userId = userId, model = model }
end

local function refreshWall()
	local wall = legendsBoard()
	if wall == nil then
		return
	end
	if #wallRows == 0 then
		buildWallList(wall)
	end
	local entries = board(boardName("season", currentSeason())):top(L.wallSize)
	if entries == nil then
		return
	end
	local ranked = Boards.rank(entries)
	local ids = {}
	for _, entry in ranked do
		table.insert(ids, entry.userId)
	end
	resolveNames(ids)
	for index = 1, L.wallSize do
		local entry = ranked[index]
		local row = wallRows[index]
		if row then
			row.Text = if entry then `#{index}   {nameOf(entry.userId)}   {entry.score}` else `#{index}   —`
		end
		local current = wallHolograms[index]
		if current and (entry == nil or current.userId ~= entry.userId) then
			current.model:Destroy()
			wallHolograms[index] = nil
		end
		if entry and wallHolograms[index] == nil then
			placeHologram(wall, index, entry.userId, entry.score)
		elseif entry and current then
			local head = current.model:FindFirstChild("Head")
			local label = if head then head:FindFirstChildWhichIsA("TextLabel", true) else nil
			if label then
				label.Text = `#{index} {nameOf(entry.userId)}\n{entry.score}`
			end
		end
	end
end

function LeaderboardService.init()
	ServerNet.onRequest(
		"LeaderboardRequest",
		Guard.tuple(Guard.enum(KINDS), Guard.optional(Guard.keyOf(Config.Modes.byId))),
		request
	)
end

function LeaderboardService.start()
	useMemory = DataService.isUsingMock()

	DataService.ProfileLoaded:Connect(function(player)
		task.spawn(onProfileLoaded, player)
	end)
	for _, player in Players:GetPlayers() do
		if DataService.getProfile(player) then
			task.spawn(onProfileLoaded, player)
		end
	end
	DataService.ProfileChanged:Connect(refreshPlayer)
	MatchService.ScoreRecorded:Connect(function(player, modeId, score)
		task.spawn(onScoreRecorded, player, modeId, score)
	end)
	Players.PlayerRemoving:Connect(function(player)
		friendsCache[player] = nil
		friendsResults[player] = nil
		friendsPending[player] = nil
	end)

	if PlaceRole.isMatchServer() then
		return
	end
	-- Hub : seuil de Légende relu périodiquement ; changement de saison pour les joueurs connectés.
	task.spawn(function()
		while true do
			refreshLegendThreshold()
			for _, player in Players:GetPlayers() do
				if DataService.getProfile(player) then
					DataService.update(player, function(profile)
						return MatchRules.rollSeason(profile, os.time())
					end)
					local profile = DataService.getProfile(player)
					if profile then
						refreshPlayer(player, profile)
					end
				end
			end
			-- Noms : on oublie ceux qui ont expiré.
			local now = os.clock()
			for userId, entry in names do
				if now - entry.at > L.nameCacheSeconds then
					names[userId] = nil
				end
			end
			task.wait(L.legendRefreshSeconds)
		end
	end)
	do
		task.spawn(function()
			-- Laisse le temps au Terminus d'être construit.
			task.wait(3)
			while true do
				refreshWall()
				task.wait(L.wallRefreshSeconds)
			end
		end)
	end
end

return LeaderboardService
