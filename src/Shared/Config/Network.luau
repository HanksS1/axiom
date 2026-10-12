--!strict
--[[
	Limites de fréquence des remotes (section 19.4).
	`rate` = requêtes par seconde en régime continu, `burst` = pic toléré.
	Toute remote doit avoir une entrée ici (vérifié au démarrage du serveur).
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

export type Limit = { rate: number, burst: number }

return Freeze.deep({
	-- Au-delà de ce nombre de requêtes rejetées par minute, le joueur est
	-- expulsé (comportement de client modifié).
	kickAfterRejectionsPerMinute = 120,

	limits = {
		-- Profil / paramètres
		RequestProfile = { rate = 0.5, burst = 3 },
		UpdateSetting = { rate = 4, burst = 10 },
		-- Outils de développement (Studio uniquement)
		DevCommand = { rate = 2, burst = 5 },
	} :: { [string]: Limit },
})
