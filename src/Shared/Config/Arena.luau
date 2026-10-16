--!strict
--[[
	Arène FFA (l'ancienne arène d'entraînement, au voisinage du Terminus) :
	décor, éclairage, bouclier de réapparition, tableau des scores.
	Taille, mannequins et délai de réapparition : Config.Dev (arenaSize…).
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

return Freeze.deep({
	-- Graine du décor (même arène dans Studio et dans les tests).
	seed = 4417,
	-- Enceinte : murs visibles, puis barrière invisible jusqu'au plafond (ni
	-- grappin ni bottes de saut ne permettent d'en sortir : la barrière ne bloque
	-- pas les rayons, le grappin ne peut donc pas s'y accrocher).
	wallHeight = 16,
	ceiling = 52,

	-- Éclairage appliqué par le CLIENT du joueur dont la caméra est dans l'arène
	-- (le Terminus voisin garde le sien) : la lisibilité prime sur l'ambiance.
	-- Mêmes champs que Config.Maps.byId.<carte>.lighting.
	lighting = {
		ambient = Color3.fromRGB(150, 156, 168), -- ombres très débouchées
		outdoorAmbient = Color3.fromRGB(170, 176, 188),
		brightness = 3,
		clockTime = 13.5, -- soleil haut : peu d'ombres longues
		fogColor = Color3.fromRGB(120, 130, 145),
		fogEnd = 2500, -- pas de brouillard à l'échelle de l'arène (180 studs)
		exposure = 0.25,
	},
	-- Effets d'ambiance d'une carte de partie (brume, halo, étalonnage) : neutralisés
	-- dans l'arène pendant une partie sur le même serveur.
	neutralizeMood = true,

	-- Bouclier de réapparition : intouchable pendant ce délai (secondes) après
	-- une apparition dans l'arène. Tombe dès que le joueur tire, frappe ou lance
	-- un gadget : il protège l'arrivée, il ne doit pas servir à attaquer.
	spawnShield = 1.5,

	-- Tableau des scores FFA (éphémère, jamais écrit dans le profil).
	scoreboard = {
		top = 5,
		-- Envoi regroupé aux joueurs de l'arène : au plus une fois par intervalle.
		broadcastInterval = 1,
	},
})
