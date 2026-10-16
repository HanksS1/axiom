--!strict
--[[
	Règles par zone, hors serveur de partie dédié (Studio, ou tant que les
	places de partie valent 0 : hub et parties sur le même serveur).

	La zone d'un joueur est décidée par le SERVEUR (Shared/Match/Zone,
	appliqué par HubService) :
	- match    : participant d'une partie en cours, pas encore sorti ;
	- tutorial : simulation privée du tutoriel (son propre kit) ;
	- arena    : dans l'Arène FFA ;
	- hub      : partout ailleurs (Terminus, stand de tir).
	Sur un serveur de partie dédié, tout le monde est en « match ».
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

return Freeze.deep({
	rules = {
		match = { gadgets = true, freeAmmo = false },
		-- Arène FFA : on y teste son équipement, gadgets compris (l'enceinte est
		-- fermée par le haut : ni grappin ni bottes ne permettent d'en sortir).
		-- Munitions réelles (copie du profil, rendue à chaque réapparition) : la
		-- gestion du chargeur fait partie du combat.
		arena = { gadgets = true, freeAmmo = false },
		tutorial = { gadgets = false, freeAmmo = false },
		-- Terminus : aucun gadget ; on tire librement, sans rien consommer.
		hub = { gadgets = false, freeAmmo = true },
	},
	-- Réserve affichée et utilisable quand les munitions sont prêtées (jamais
	-- décomptée, jamais conservée) : assez pour ne jamais limiter un rechargement.
	lentReserve = 999,
	-- Fréquence de publication de la zone au client (secondes) : affichage seulement,
	-- le serveur recalcule la zone à chaque action.
	publishInterval = 0.5,
})
