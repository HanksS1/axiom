--!strict
--[[
	Déclaration de toutes les remotes du jeu.

	- "event"    : RemoteEvent (fire-and-forget)
	- "function" : RemoteFunction (client → serveur uniquement : le serveur
	  n'appelle JAMAIS InvokeClient, qui peut bloquer indéfiniment).

	`toServer = true` : le client peut l'appeler. Une limite de fréquence
	doit alors exister dans Config/Network (vérifié au démarrage).
]]

export type RemoteDef = {
	kind: "event" | "function",
	toServer: boolean,
}

local Remotes: { [string]: RemoteDef } = {
	-- Profil
	ProfileSync = { kind = "event", toServer = false },
	RequestProfile = { kind = "function", toServer = true },
	UpdateSetting = { kind = "event", toServer = true },
	-- Notifications localisées (clé + paramètres)
	Notify = { kind = "event", toServer = false },
	-- Outils de développement (Studio uniquement, ignorés en production)
	DevCommand = { kind = "event", toServer = true },
}

return table.freeze(Remotes)
