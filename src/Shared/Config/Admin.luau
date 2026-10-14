--!strict
--[[
	Administration : qui est administrateur, et ce qu'il peut offrir.

	⚠ À RENSEIGNER par l'auteur : son identifiant Roblox (UserId) dans
	`userIds`. On le trouve dans l'adresse de son profil Roblox :
	https://www.roblox.com/users/<UserId>/profile
	Optionnel : un groupe Roblox (`groupId`) dont les membres de rang
	`minGroupRank` ou plus sont administrateurs (255 = propriétaire du groupe).

	Le serveur seul décide qui est administrateur : le client ne fait
	qu'afficher le panneau, chaque demande est revérifiée côté serveur.
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

return Freeze.deep({
	-- Identifiants Roblox des administrateurs (nombres), par exemple { 123456789 }.
	userIds = {} :: { number },
	-- Groupe Roblox (0 = aucun) et rang minimal pour être administrateur.
	groupId = 0,
	minGroupRank = 255,
	-- Dans Roblox Studio seulement : tout joueur est administrateur (pour tester).
	-- Sans effet sur les serveurs en ligne.
	everyoneInStudio = true,

	-- Caisses qui peuvent être offertes : la caisse gratuite et les caisses du Holo-Bazar.
	giftCrates = { "free", "rust", "neon", "prototype" },
	-- Au plus `maxPerGift` caisses par envoi, et `maxStock` caisses offertes en attente
	-- d'un même type sur un profil (garde-fou contre une erreur de saisie).
	maxPerGift = 20,
	maxStock = 999,
})
