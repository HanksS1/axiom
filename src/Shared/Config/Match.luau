--!strict
--[[
	Format et déroulé d'une partie (sections 4, 6.10, 9.3, 13, 16.5).
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

return Freeze.deep({
	playersPerMatch = 16,
	duosPerMatch = 8,

	duration = 15 * 60, -- Protocole de Purge
	alertAt = 12 * 60, -- alerte d'AXIOM, ouverture du 3e point d'extraction
	finalCountdownAt = 14 * 60, -- le chrono clignote en rouge

	extraction = {
		points = 3,
		openAtStart = 2,
		holdTime = 30,
		-- Rayon du cercle lumineux au sol (non précisé par le document).
		radius = 10,
		verticalTolerance = 12,
		updateInterval = 0.2,
	},

	-- Renforts de 12:00 (document : 6 à 10), réduits avec la densité des robots.
	alertWave = {
		minRobots = 5,
		maxRobots = 8,
	},

	pickup = {
		-- Maintien pour ramasser au sol ou rouvrir un conteneur (9.3).
		holdTime = 0.3,
		maxDistance = 10,
		-- Dans un conteneur ouvert, un clic suffit (le maintien rendait la
		-- fouille trop longue dans les zones à risque). Seul un intervalle
		-- minimal entre deux prises est imposé par le serveur.
		takeInterval = 0.08,
	},

	-- Après la mort (désintégration), délai avant l'écran de fin (solo).
	deathScreenDelay = 1.5,
	-- Fin de partie : délai avant le retour (Terminus ; arène de test en Studio).
	returnDelay = 20,

	-- Orbe et Accélérateur (duo, section 6.10).
	revive = {
		orbPickupHold = 0.3,
		orbPickupDistance = 8,
		acceleratorDistance = 10,
	},

	-- Pings (section 16.5).
	ping = {
		lifetime = 8,
		maxDistance = 500,
		-- Repère posé depuis la carte : visible plus longtemps, avec sa distance,
		-- et retiré quand on l'atteint. Un seul par joueur.
		waypointLifetime = 180,
		waypointReach = 10,
		longPressThreshold = 0.35,
		lowHealthForHealPing = 35,
	},

	-- Gadgets : PV des objets destructibles (non précisés par le document).
	gadgets = {
		droneHealth = 30,
		droneHoverHeight = 12,
		wallDistance = 5,
		grappleSpeed = 80,
		grappleMaxTime = 1.2,
	},
})
