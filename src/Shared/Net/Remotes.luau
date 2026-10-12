--!strict
--[[
	Déclaration de toutes les remotes du jeu.

	- "event"      : RemoteEvent (fiable, ordonné)
	- "unreliable" : UnreliableRemoteEvent (effets visuels fréquents : peut
	  être perdu, jamais utilisé pour une information de jeu importante)
	- "function" : RemoteFunction (client → serveur uniquement : le serveur
	  n'appelle JAMAIS InvokeClient, qui peut bloquer indéfiniment).

	`toServer = true` : le client peut l'appeler. Une limite de fréquence
	doit alors exister dans Config/Network (vérifié au démarrage).
]]

export type RemoteDef = {
	kind: "event" | "unreliable" | "function",
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

	-- Combat (intentions du client)
	FireWeapon = { kind = "event", toServer = true },
	ReloadWeapon = { kind = "event", toServer = true },
	SwitchWeapon = { kind = "event", toServer = true },
	MeleeAttack = { kind = "event", toServer = true },
	SetParry = { kind = "event", toServer = true },
	SetMovement = { kind = "event", toServer = true },
	-- Combat (serveur → client)
	CombatState = { kind = "event", toServer = false }, -- état des armes (propriétaire)
	HitConfirm = { kind = "event", toServer = false }, -- marqueur de touche (tireur)
	DamageTaken = { kind = "event", toServer = false }, -- direction des dégâts (victime)
	ParryResult = { kind = "event", toServer = false }, -- parade réussie / garde brisée
	ShotFired = { kind = "unreliable", toServer = false }, -- tracés des tirs (autres joueurs)
	MeleeSwing = { kind = "unreliable", toServer = false }, -- animation de coup (autres joueurs)

	-- Loot et inventaire
	ContainerSync = { kind = "event", toServer = false }, -- contenu d'un conteneur consulté
	LootAlarm = { kind = "unreliable", toServer = false }, -- alarme de casier d'AXIOM
	InventorySync = { kind = "event", toServer = false }, -- sac porté (propriétaire)
	TakeItem = { kind = "event", toServer = true },
	CloseContainer = { kind = "event", toServer = true },
	EquipItem = { kind = "event", toServer = true },
	UnequipItem = { kind = "event", toServer = true },
	DropItem = { kind = "event", toServer = true },
	UseConsumable = { kind = "event", toServer = true },

	-- Partie (P3)
	MatchStatus = { kind = "event", toServer = false }, -- statut du joueur (vivant, orbe, mort, extrait…)
	MatchResult = { kind = "event", toServer = false }, -- écran de fin de partie
	Announce = { kind = "event", toServer = false }, -- annonces d'AXIOM (clé)
	KillFeed = { kind = "event", toServer = false },
	Extracted = { kind = "event", toServer = false }, -- effet d'évacuation
	ExtractionState = { kind = "event", toServer = false },
	ReviveState = { kind = "event", toServer = false },
	Ping = { kind = "event", toServer = true },
	PingShown = { kind = "event", toServer = false },
	UseGadget = { kind = "event", toServer = true },
	GadgetState = { kind = "event", toServer = false },
	GadgetEffect = { kind = "event", toServer = false }, -- saut / grappin validés (propriétaire)
	GadgetVisual = { kind = "unreliable", toServer = false },
	Reveal = { kind = "event", toServer = false }, -- cibles révélées par un drone

	-- Terminus et économie (P5)
	VaultAction = { kind = "event", toServer = true },
	MerchantSell = { kind = "event", toServer = true },
	MerchantBuy = { kind = "event", toServer = true },
	Repair = { kind = "event", toServer = true },
	SetInsurance = { kind = "event", toServer = true },
	OpenFreeCrate = { kind = "event", toServer = true },
	FreeCrateResult = { kind = "event", toServer = false },

	-- Matchmaking (P6) : plateforme, groupe duo, file d'attente, retour au hub
	SetPlatform = { kind = "event", toServer = true },
	PartyInvite = { kind = "event", toServer = true },
	PartyRespond = { kind = "event", toServer = true },
	PartyLeave = { kind = "event", toServer = true },
	PartyInviteReceived = { kind = "event", toServer = false },
	PartyState = { kind = "event", toServer = false },
	QueueJoin = { kind = "event", toServer = true },
	QueueLeave = { kind = "event", toServer = true },
	QueueState = { kind = "event", toServer = false },
	ReturnToHub = { kind = "event", toServer = true },
}

return table.freeze(Remotes)
