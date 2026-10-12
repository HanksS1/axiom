--!strict
--[[
	Places, matchmaking et crossplay (section 16).

	⚠ Les identifiants de places sont à renseigner après création des places
	dans l'expérience Roblox (Hub = place de départ).
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

return Freeze.deep({
	places = {
		hub = 0,
		tutorial = 0,
		match = 0,
	},

	hubMaxPlayers = 20,

	queue = {
		fillTimeout = 90, -- après 90 s : lancement avec complément de bots
		minPlayersToStart = 1,
		crossplaySuggestAfter = 60,
		teleportRetries = 3,
	},

	platformGroups = { "crossplay", "touch", "keyboard", "gamepad" },
})
