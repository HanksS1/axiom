--!strict
--[[
	Persistance des profils (section 19.3 / 19.4).
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

return Freeze.deep({
	-- Changer le suffixe de version repart sur un stockage vierge : à ne
	-- faire qu'en développement. Les évolutions de format passent par les
	-- migrations (Server/Data/Migrations).
	storeName = "AxiomProfiles_v1",
	keyPrefix = "player_",

	autosaveInterval = 60, -- secondes
	-- Un verrou non rafraîchi depuis ce délai est considéré comme abandonné
	-- (serveur planté) et peut être repris. Doit être largement supérieur à
	-- autosaveInterval.
	lockTimeout = 10 * 60,
	-- Tentatives de chargement si le profil est verrouillé par un autre
	-- serveur (cas normal juste après une téléportation).
	loadAttempts = 8,
	loadRetryDelay = 2,
	saveAttempts = 3,
	saveRetryDelay = 1,

	-- En Studio, si les API DataStore sont inaccessibles, utiliser un
	-- stockage en mémoire (les données sont perdues à l'arrêt du test).
	allowMockInStudio = true,
})
