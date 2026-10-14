--!strict
--[[
	PingService : pings contextuels d'équipe (section 16.5).
	« Ennemi ici », « Loot ici », « Je vais là », « Danger », « Besoin de soins ».
	Visibles par l'équipe uniquement (le joueur seul en solo). Un joueur en
	orbe peut encore pinger (vue spectateur).

	Repère de carte : posé depuis la carte (touche « carte »), n'importe où
	sur la carte de la partie. Le client le garde affiché plus longtemps,
	avec sa distance, pour s'orienter.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MapPlan = require(Shared.Match.MapPlan)
local Guard = require(Shared.Util.Guard)

local ServerNet = require(script.Parent.Parent.Net.ServerNet)

local PingService = {}

PingService.KINDS = table.freeze({ "enemy", "loot", "go", "danger", "heal" })

local function referencePosition(player: Player): Vector3?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root.Position
	end
	-- En orbe : la caméra suit le coéquipier ; on accepte sa position.
	local team = player:GetAttribute("TeamId")
	for _, other in Players:GetPlayers() do
		if other ~= player and team ~= nil and other:GetAttribute("TeamId") == team and other.Character then
			local otherRoot = other.Character:FindFirstChild("HumanoidRootPart")
			if otherRoot and otherRoot:IsA("BasePart") then
				return otherRoot.Position
			end
		end
	end
	return nil
end

function PingService.init()
	ServerNet.onEvent(
		"Ping",
		Guard.tuple(
			Guard.vector3(100_000),
			Guard.enum(PingService.KINDS :: { string }),
			Guard.optional(Guard.boolean())
		),
		function(player, position: Vector3, kind: string, fromMap: boolean?)
			local from = referencePosition(player)
			if from == nil then
				return
			end
			local waypoint = fromMap == true
			if waypoint then
				-- Repère de carte : partout sur la carte de la partie, pas au-delà.
				local _, _, inside = MapPlan.toPlan(position, Config.Maps.origin, Config.Maps.size)
				local state = ReplicatedStorage:FindFirstChild("MatchState")
				if not inside or state == nil or state:GetAttribute("Running") ~= true then
					return
				end
			elseif (position - from).Magnitude > Config.Match.ping.maxDistance then
				return
			end
			local team = player:GetAttribute("TeamId")
			for _, other in Players:GetPlayers() do
				if other == player or (team ~= nil and other:GetAttribute("TeamId") == team) then
					ServerNet.fire("PingShown", other, player.UserId, player.DisplayName, position, kind, waypoint)
				end
			end
		end
	)
end

function PingService.start() end

return PingService
