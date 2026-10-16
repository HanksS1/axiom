--!strict
--[[
	FfaService : tableau des scores de l'Arène FFA (Shared/Match/FfaBoard).

	- Présence : l'attribut « Zone » du joueur (posé par HubService) passe à
	  « arena » → il rejoint le tableau ; il en sort → son score disparaît.
	- Éliminations : CombatService.FighterDied (victime, tueur), joueurs dans
	  l'arène seulement.
	- Diffusion : regroupée, au plus une fois par
	  `Config.Arena.scoreboard.broadcastInterval`, et seulement aux joueurs
	  de l'arène, quand quelque chose a changé.

	AUCUNE écriture de profil : ce service n'utilise pas DataService (vérifié
	par un test). Les statistiques permanentes ne viennent que des parties.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local FfaBoard = require(Shared.Match.FfaBoard)

local PlaceRole = require(script.Parent.Parent.Matchmaking.PlaceRole)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local CombatService = require(script.Parent.CombatService)

local S = Config.Arena.scoreboard

local FfaService = {}

local board = FfaBoard.new()
local members: { [Player]: boolean } = {}
local dirty = false

local function updatePresence(player: Player)
	local inArena = player.Parent == Players and player:GetAttribute("Zone") == "arena"
	if inArena and not members[player] then
		members[player] = true
		FfaBoard.join(board, player.UserId, player.DisplayName)
		dirty = true
	elseif not inArena and members[player] then
		members[player] = nil
		FfaBoard.leave(board, player.UserId)
		dirty = true
		-- Hors de l'arène : le tableau se vide côté client (il est aussi masqué).
		if player.Parent == Players then
			ServerNet.fire("FfaBoard", player, nil)
		end
	end
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("Zone"):Connect(function()
		updatePresence(player)
	end)
	updatePresence(player)
end

local function broadcast()
	for player in members do
		ServerNet.fire("FfaBoard", player, FfaBoard.view(board, player.UserId, S.top))
	end
end

function FfaService.init() end

function FfaService.start()
	if PlaceRole.isMatchServer() then
		return -- pas d'arène sur un serveur de partie dédié
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		if members[player] then
			members[player] = nil
			FfaBoard.leave(board, player.UserId)
			dirty = true
		end
	end)

	CombatService.FighterDied:Connect(function(victim, killer)
		local victimPlayer = victim.player
		local killerPlayer = if killer then killer.player else nil
		if victimPlayer == nil or killerPlayer == nil or not members[victimPlayer] or not members[killerPlayer] then
			return
		end
		if FfaBoard.recordKill(board, killerPlayer.UserId, victimPlayer.UserId) then
			dirty = true
		end
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < S.broadcastInterval or not dirty then
			return
		end
		elapsed = 0
		dirty = false
		broadcast()
	end)
end

return FfaService
