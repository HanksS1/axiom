--!strict
--[[
	PartyService : groupes duo au Terminus (sections 16.2 et 16.5).

	- Invitation d'un joueur du même serveur (en l'approchant, ou un ami
	  rejoint via l'invitation Roblox). Elle expire après 30 s.
	- Un groupe compte 2 joueurs au plus ; quitter le dissout.
	- Plateforme de chaque joueur (périphérique d'entrée principal, déclaré
	  par le client) : sert au choix de la file (crossplay forcé si les deux
	  membres ont des plateformes différentes).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Guard = require(Shared.Util.Guard)
local Matchmaking = require(Shared.Match.Matchmaking)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)

local PlaceRole = require(script.Parent.Parent.Matchmaking.PlaceRole)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local Uid = require(script.Parent.Parent.Util.Uid)
local MatchService = require(script.Parent.MatchService)

local PartyService = {}

export type Party = {
	id: string,
	leader: Player,
	members: { Player },
}

-- Le groupe a changé (membre parti, dissolution) : la file doit être annulée.
PartyService.Changed = Signal.new() :: Signal.Signal<{ Player }>

local parties: { [Player]: Party } = {}
local platforms: { [Player]: Matchmaking.Platform } = {}
-- Invitations en attente : invité → (inviteur → expiration).
local invites: { [Player]: { [Player]: number } } = {}

-- Vérifie qu'un joueur est libre pour un groupe (sinon : clé de refus).
local busyCheck: ((player: Player) -> string?)? = nil

function PartyService.setBusyCheck(check: (player: Player) -> string?)
	busyCheck = check
end

function PartyService.partyOf(player: Player): Party?
	return parties[player]
end

function PartyService.platformOf(player: Player): Matchmaking.Platform
	return platforms[player] or "keyboard"
end

local function view(party: Party): Types.PartyView
	local members = {}
	for _, member in party.members do
		table.insert(members, {
			userId = member.UserId,
			name = member.DisplayName,
			platform = PartyService.platformOf(member),
		})
	end
	return { leaderUserId = party.leader.UserId, members = members }
end

local function sync(party: Party)
	local payload = view(party)
	for _, member in party.members do
		if member.Parent == Players then
			ServerNet.fire("PartyState", member, payload)
		end
	end
end

local function dissolve(party: Party, reasonKey: string?)
	local members = party.members
	for _, member in members do
		if parties[member] == party then
			parties[member] = nil
			if member.Parent == Players then
				ServerNet.fire("PartyState", member, nil)
				if reasonKey then
					ServerNet.notify(member, reasonKey)
				end
			end
		end
	end
	PartyService.Changed:Fire(members)
end

local function refusal(player: Player): string?
	if PlaceRole.isMatchServer() or MatchService.participant(player) then
		return "party.refused.in_match"
	end
	local check = busyCheck
	if check then
		return check(player)
	end
	return nil
end

local function invite(player: Player, targetUserId: number)
	local target = Players:GetPlayerByUserId(targetUserId)
	if target == nil or target == player then
		ServerNet.notify(player, "party.refused.not_found")
		return
	end
	local party = parties[player]
	if party and #party.members >= Config.Matchmaking.party.maxSize then
		ServerNet.notify(player, "party.refused.full")
		return
	end
	if parties[target] then
		ServerNet.notify(player, "party.refused.target_busy", { name = target.DisplayName })
		return
	end
	local reason = refusal(player) or refusal(target)
	if reason then
		ServerNet.notify(player, reason)
		return
	end
	local pending = invites[target]
	if pending == nil then
		pending = {}
		invites[target] = pending
	end
	pending[player] = os.clock() + Config.Matchmaking.party.inviteTimeout
	ServerNet.fire("PartyInviteReceived", target, player.UserId, player.DisplayName)
	ServerNet.notify(player, "party.invite_sent", { name = target.DisplayName })
end

local function respond(player: Player, inviterUserId: number, accept: boolean)
	local inviter = Players:GetPlayerByUserId(inviterUserId)
	local pending = invites[player]
	local expires = if pending and inviter then pending[inviter] else nil
	if pending and inviter then
		pending[inviter] = nil
	end
	if inviter == nil or expires == nil or os.clock() > expires then
		ServerNet.notify(player, "party.refused.expired")
		return
	end
	if not accept then
		ServerNet.notify(inviter, "party.declined", { name = player.DisplayName })
		return
	end
	if parties[player] then
		ServerNet.notify(player, "party.refused.already")
		return
	end
	local reason = refusal(player) or refusal(inviter)
	if reason then
		ServerNet.notify(player, reason)
		return
	end
	local party = parties[inviter]
	if party == nil then
		party = { id = Uid.new(), leader = inviter, members = { inviter } }
		parties[inviter] = party
	end
	if #party.members >= Config.Matchmaking.party.maxSize then
		ServerNet.notify(player, "party.refused.full")
		return
	end
	table.insert(party.members, player)
	parties[player] = party
	invites[player] = nil
	sync(party)
	PartyService.Changed:Fire(party.members)
end

function PartyService.leave(player: Player, reasonKey: string?)
	local party = parties[player]
	if party then
		-- Un groupe de deux ne survit pas au départ d'un membre.
		dissolve(party, reasonKey)
	end
end

function PartyService.init()
	ServerNet.onEvent(
		"SetPlatform",
		Guard.tuple(Guard.enum(Config.Matchmaking.platforms)),
		function(player, platform: Matchmaking.Platform)
			if platforms[player] == platform then
				return
			end
			platforms[player] = platform
			local party = parties[player]
			if party then
				sync(party)
				PartyService.Changed:Fire(party.members)
			end
		end
	)
	ServerNet.onEvent("PartyInvite", Guard.tuple(Guard.integer(1, 2 ^ 53)), invite)
	ServerNet.onEvent("PartyRespond", Guard.tuple(Guard.integer(1, 2 ^ 53), Guard.boolean()), respond)
	ServerNet.onEvent("PartyLeave", Guard.tuple(), function(player)
		PartyService.leave(player, "party.left")
	end)
end

function PartyService.start()
	Players.PlayerRemoving:Connect(function(player)
		PartyService.leave(player, "party.partner_left")
		platforms[player] = nil
		invites[player] = nil
		for _, pending in invites do
			pending[player] = nil
		end
	end)
end

return PartyService
