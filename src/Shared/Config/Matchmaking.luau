--!strict
--[[
	Places, matchmaking et crossplay (section 16).

	⚠ Les identifiants de places sont à renseigner après création des places
	dans l'expérience Roblox (Hub = place de départ). Tant que `hub` ou
	`match` vaut 0, les parties se lancent sur le serveur lui-même (Studio,
	ou test sur une place publiée seule).
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

return Freeze.deep({
	places = {
		hub = 0,
		match = 0,
	},

	matchSize = 16, -- 16 solos ou 8 duos

	queue = {
		fillTimeout = 90, -- après 90 s : lancement avec complément de mercenaires IA
		minPlayersToStart = 1,
		crossplaySuggestAfter = 60, -- hors crossplay : proposition de basculer
		pollInterval = 2, -- secondes : affectations et compteurs de la file
		matchmakerInterval = 3, -- secondes entre deux passes du matchmaker
		lockDuration = 10, -- secondes : un seul hub fait le matchmaking d'une file
		ticketExpiry = 120, -- un ticket non rafraîchi disparaît (hub planté)
		ticketRefresh = 30,
		assignmentExpiry = 120,
		readBatch = 100, -- tickets lus par passe
	},

	-- Parties locales (Studio, ou places non configurées) : attente raccourcie.
	localFillTimeout = 8,

	teleport = {
		retries = 3,
		retryDelay = 2,
	},

	matchServer = {
		configExpiry = 60 * 60, -- durée de vie de la description de partie
		configReadAttempts = 5,
		joinTimeout = 40, -- attente maximale des joueurs attendus
		startDelay = 3, -- délai après l'arrivée du dernier joueur attendu
	},

	party = {
		maxSize = 2,
		inviteTimeout = 30,
	},

	-- Le niveau minimum (2) est atteint par le tutoriel obligatoire (P10).
	levelGateEnabled = true,

	platforms = { "touch", "keyboard", "gamepad" },
})
