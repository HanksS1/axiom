--!strict
--[[
	MatchServerService : serveur réservé d'une partie (sections 16.1 et 16.3).

	- La description de la partie (mode, format, équipes, mercenaires) est
	  lue dans MatchStore à partir de l'identifiant du serveur privé : elle ne
	  transite jamais par le client.
	- Seuls les joueurs attendus sont admis ; les autres repartent au Terminus.
	- La partie démarre quand tous les joueurs attendus sont là (ou après un
	  délai maximal) ; les places vides sont complétées par des mercenaires IA.
	- Le SE est revérifié à l'arrivée (profil chargé sur CE serveur).
	- Un joueur qui a fini (extrait ou mort) repart au Terminus après le
	  délai de retour, ou tout de suite avec le bouton « Retour au Terminus ».

	Hors serveur de partie (Studio, parties locales), le bouton « Retour au
	Terminus » fait simplement réapparaître le joueur au Terminus.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Guard = require(Shared.Util.Guard)
local Matchmaking = require(Shared.Match.Matchmaking)

local MatchStore = require(script.Parent.Parent.Matchmaking.MatchStore)
local PlaceRole = require(script.Parent.Parent.Matchmaking.PlaceRole)
local Teleporter = require(script.Parent.Parent.Matchmaking.Teleporter)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local DataService = require(script.Parent.DataService)
local MatchService = require(script.Parent.MatchService)

local MM = Config.Matchmaking

local MatchServerService = {}

local returning: { [Player]: boolean } = {}

local function kickToHub(player: Player)
	ServerNet.kick(player, "kick.teleportFailed")
end

-- Renvoie un joueur au Terminus (une seule fois).
local function sendToHub(player: Player)
	if returning[player] or player.Parent ~= Players then
		return
	end
	returning[player] = true
	Teleporter.toHub(player, kickToHub)
end

local function readConfig(): MatchStore.MatchConfig?
	local serverId = game.PrivateServerId
	if serverId == "" then
		return nil
	end
	for attempt = 1, MM.matchServer.configReadAttempts do
		local config = MatchStore.readMatch(serverId)
		if config then
			return config
		end
		if attempt < MM.matchServer.configReadAttempts then
			task.wait(2)
		end
	end
	return nil
end

local function run()
	Players.CharacterAutoLoads = false
	local config = readConfig()
	if config == nil then
		warn("[MatchServerService] description de partie introuvable : retour au Terminus")
		Players.PlayerAdded:Connect(sendToHub)
		for _, player in Players:GetPlayers() do
			sendToHub(player)
		end
		return
	end

	local expected: { [number]: boolean } = {}
	local expectedCount = 0
	for _, team in config.teams do
		for _, userId in team do
			if type(userId) == "number" and not expected[userId] then
				expected[userId] = true
				expectedCount += 1
			end
		end
	end
	local started = false
	local function admit(player: Player)
		if not expected[player.UserId] or started then
			-- Joueur inattendu, ou arrivé après le départ : retour au Terminus.
			sendToHub(player)
		end
	end
	Players.PlayerAdded:Connect(admit)
	for _, player in Players:GetPlayers() do
		admit(player)
	end

	-- Attente des joueurs attendus (profils chargés), au plus joinTimeout.
	local deadline = os.clock() + MM.matchServer.joinTimeout
	while os.clock() < deadline do
		local ready = 0
		for _, player in Players:GetPlayers() do
			if expected[player.UserId] and DataService.getProfile(player) then
				ready += 1
			end
		end
		if ready >= expectedCount then
			break
		end
		task.wait(0.5)
	end
	task.wait(MM.matchServer.startDelay)

	-- Joueurs présents et toujours éligibles (SE recalculé sur ce serveur).
	local present: { [number]: Player } = {}
	for _, player in Players:GetPlayers() do
		local profile = DataService.getProfile(player)
		if expected[player.UserId] and profile then
			local refusal = Matchmaking.refusal(Matchmaking.memberOf(profile), config.modeId)
			if refusal then
				local params = table.clone(refusal.params or {})
				params.name = player.DisplayName
				ServerNet.notify(player, "deploy.refused." .. refusal.reason, params)
				sendToHub(player)
			else
				present[player.UserId] = player
			end
		end
	end
	local players: { Player } = {}
	local teams: { { Player } } = {}
	for _, team in config.teams do
		local members = {}
		for _, userId in team do
			local player = present[userId]
			if player then
				table.insert(members, player)
				table.insert(players, player)
			end
		end
		if #members > 0 then
			table.insert(teams, members)
		end
	end
	started = true
	if #players == 0 then
		warn("[MatchServerService] aucun joueur arrivé : partie annulée")
		return
	end
	MatchService.begin({
		modeId = config.modeId,
		format = config.format,
		players = players,
		teams = teams,
		mercenaries = MM.matchSize - #players,
		mapId = config.mapId,
	})
end

function MatchServerService.init()
	-- « Retour au Terminus » après sa fin de partie (extrait ou mort).
	ServerNet.onEvent("ReturnToHub", Guard.tuple(), function(player)
		local participant = MatchService.participant(player)
		if participant and not participant.finished then
			return
		end
		if PlaceRole.isMatchServer() then
			sendToHub(player)
		elseif participant and MatchService.isRunning() then
			-- Partie locale encore en cours pour les autres : réapparition au Terminus.
			task.spawn(function()
				player:LoadCharacter()
			end)
		end
	end)
end

function MatchServerService.start()
	if not PlaceRole.isMatchServer() then
		return
	end
	MatchService.setReturnHandler(sendToHub)
	MatchService.PlayerFinished:Connect(function(player)
		task.delay(Config.Match.returnDelay, function()
			sendToHub(player)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		returning[player] = nil
	end)
	task.spawn(run)
end

return MatchServerService
