--!strict
--[[
	Outils de test (Studio uniquement).
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

return Freeze.deep({
	-- Construit une arène de test (greybox) si la place n'a pas de carte.
	testArenaInStudio = true,
	-- En ligne : arène et Terminus greybox tant que les vraies cartes (P7) et
	-- le vrai Terminus ne sont pas modélisés.
	greyboxOnline = true,
	arenaSize = 180,
	-- Mannequins d'entraînement (cibles immobiles) dans l'arène.
	dummies = {
		{ position = Vector3.new(0, 3, -30), vestCondition = 0, helmetCondition = 0 },
		{ position = Vector3.new(12, 3, -30), vestCondition = 4, helmetCondition = 0 },
		{ position = Vector3.new(-12, 3, -30), vestCondition = 5, helmetCondition = 5 },
	},
	dummyRespawnDelay = 4,
	-- Robots dans l'arène (petite carte) : partie et bac à sable.
	arenaRobots = 8,
	-- Mercenaires IA dans l'arène (le complément à 16 serait trop dense).
	arenaMercenaries = 5,
})
