--!strict
--[[
	Freeze : gel récursif des tables de configuration.

	Les modules de config sont partagés entre tous les scripts d'un même
	environnement (serveur ou client). Les geler empêche qu'un script les
	modifie par erreur à l'exécution (et donc qu'une valeur de gameplay
	change silencieusement pour tout le serveur).
]]

local Freeze = {}

function Freeze.deep<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local t = value :: any
	if table.isfrozen(t) then
		return value
	end
	for _, child in t do
		if type(child) == "table" then
			Freeze.deep(child)
		end
	end
	table.freeze(t)
	return value
end

-- Copie profonde (les copies ne sont jamais gelées).
function Freeze.copy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in value :: any do
		result[Freeze.copy(key)] = Freeze.copy(child)
	end
	return (result :: any) :: T
end

return Freeze
