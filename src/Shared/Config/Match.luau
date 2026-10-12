--!strict
--[[
	Format et déroulé d'une partie (sections 4, 9.3, 13).
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
	},

	alertWave = {
		minRobots = 6,
		maxRobots = 10,
	},

	pickup = {
		holdTime = 0.3,
		maxDistance = 10,
	},
})
