--!strict
--[[
	PlaceRole : rôle du serveur (section 16.1).

	- « match » : serveur réservé d'une partie (place de partie).
	- « hub »   : Terminus. Si les places ne sont pas configurées (ou en
	  Studio), les parties se lancent sur ce même serveur (« parties locales »).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local PlaceRole = {}

function PlaceRole.isMatchServer(): boolean
	local places = Config.Matchmaking.places
	return not RunService:IsStudio() and places.match ~= 0 and game.PlaceId == places.match
end

-- Téléportations hub ↔ partie possibles (places configurées, hors Studio).
function PlaceRole.teleportsEnabled(): boolean
	local places = Config.Matchmaking.places
	return not RunService:IsStudio() and places.hub ~= 0 and places.match ~= 0
end

return PlaceRole
