--!strict
--[[
	Try : appel protégé qui retourne toujours (succès, message d'erreur?).
	Évite les ambiguïtés de typage de `pcall` sur les fonctions sans retour.
]]

local function try(callback: (...any) -> ...any, ...: any): (boolean, string?)
	local results = table.pack(pcall(callback, ...))
	if results[1] then
		return true, nil
	end
	return false, tostring(results[2])
end

return try
