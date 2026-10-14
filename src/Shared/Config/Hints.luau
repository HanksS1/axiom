--!strict
--[[
	Aides contextuelles : une courte ligne qui rappelle une commande au moment
	où elle sert (soin quand les PV sont bas, parade quand la mêlée est en
	main…). Elles ne doivent JAMAIS gêner le jeu : une seule à la fois, peu
	de répétitions, jamais pendant un échange de tirs pour celles qui ne sont
	pas urgentes, et plus du tout une fois le geste accompli.

	Par aide :
	- `maxShows` : nombre d'affichages par session ;
	- `cooldown` : secondes entre deux affichages de la même aide ;
	- `urgent`   : affichée même en plein combat (soin, munitions).
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

export type HintDef = {
	maxShows: number,
	cooldown: number,
	urgent: boolean?,
}

local hints: { [string]: HintDef } = {
	-- Urgentes : l'information sert tout de suite.
	heal = { maxShows = 3, cooldown = 45, urgent = true },
	battery = { maxShows = 3, cooldown = 45, urgent = true },
	noCells = { maxShows = 2, cooldown = 60, urgent = true },
	overheat = { maxShows = 2, cooldown = 60, urgent = true },
	-- Au calme seulement.
	bagFull = { maxShows = 2, cooldown = 90 },
	melee = { maxShows = 1, cooldown = 0 },
	objective = { maxShows = 2, cooldown = 120 },
	extract = { maxShows = 1, cooldown = 0 },
	stance = { maxShows = 1, cooldown = 0 },
	ping = { maxShows = 1, cooldown = 0 },
	radar = { maxShows = 1, cooldown = 0 },
	map = { maxShows = 1, cooldown = 0 },
	hub = { maxShows = 1, cooldown = 0 },
}

return Freeze.deep({
	hints = hints,

	display = {
		duration = 5, -- secondes à l'écran
		fade = 0.25,
		gap = 6, -- secondes de silence entre deux aides
	},
	-- « Au calme » : aucun tir ni dégât depuis ce délai.
	calmDelay = 4,
	pollInterval = 0.25,

	-- Seuils des aides de survie.
	healBelow = 45, -- PV
	batteryBelow = 0.3, -- part du bouclier maximal

	-- Début de partie : rappel de l'objectif, puis quelques conseils espacés.
	objectiveDelay = 6,
	tips = { after = 25, interval = 45, maxPerMatch = 3 },

	-- Terminus : délai avant le rappel « approchez d'un comptoir ».
	hubDelay = 5,
	hubRadius = 320,
})
