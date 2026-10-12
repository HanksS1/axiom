--!strict
--[[
	Génération d'identifiants uniques d'objets (GUID), côté serveur uniquement.
	Le client ne crée JAMAIS d'uid : tout objet naît sur le serveur.
]]

local HttpService = game:GetService("HttpService")

local Uid = {}

function Uid.new(): string
	return HttpService:GenerateGUID(false)
end

return Uid
