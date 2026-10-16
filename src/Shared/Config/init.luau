--!strict
--[[
	Point d'entrée unique des configurations de gameplay.

	RÈGLE : aucune valeur de gameplay en dur dans le code. Tout ce qui peut
	être ajusté pendant les tests vit dans un module de ce dossier.
	Toutes les tables exportées sont gelées (lecture seule).
]]

local Config = {
	Conditions = require(script.Conditions),
	Cells = require(script.Cells),
	Weapons = require(script.Weapons),
	Equipment = require(script.Equipment),
	Combat = require(script.Combat),
	Modes = require(script.Modes),
	Match = require(script.Match),
	Robots = require(script.Robots),
	Mercenaries = require(script.Mercenaries),
	Loot = require(script.Loot),
	Economy = require(script.Economy),
	Monetization = require(script.Monetization),
	Cosmetics = require(script.Cosmetics),
	Progression = require(script.Progression),
	Range = require(script.Range),
	Zones = require(script.Zones),
	Arena = require(script.Arena),
	Matchmaking = require(script.Matchmaking),
	Maps = require(script.Maps),
	Data = require(script.Data),
	Network = require(script.Network),
	Settings = require(script.Settings),
	Hints = require(script.Hints),
	Visuals = require(script.Visuals),
	WeaponPoses = require(script.WeaponPoses),
	Audio = require(script.Audio),
	Dev = require(script.Dev),
	Admin = require(script.Admin),
}

return table.freeze(Config)
