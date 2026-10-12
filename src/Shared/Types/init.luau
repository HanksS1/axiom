--!strict
--[[
	Types partagés (serveur, client, tests).
]]

-- Emplacements équipés (section 8.1).
export type SlotName = "ranged" | "melee" | "gadget1" | "gadget2" | "helmet" | "vest" | "backpack"

export type ItemCategory =
	"ranged"
	| "melee"
	| "gadget"
	| "helmet"
	| "vest"
	| "backpack"
	| "consumable"
	| "cell"
	| "calibration"

-- Instance d'objet possédée par un joueur (section 19.3).
export type ItemInstance = {
	uid: string, -- identifiant unique (GUID), jamais réutilisé
	itemId: string, -- référence vers la config (ex. "vigil_pistol")
	condition: number?, -- 1 à 5 ; nil pour les objets sans état (consommables, cellules…)
	stack: number?, -- pour les consommables et cellules
	isKit: boolean?, -- objet du kit de base (non vendable)
	tempGamesLeft: number?, -- objet temporaire (3 → 0)
}

export type Loadout = {
	ranged: ItemInstance?,
	melee: ItemInstance?,
	gadget1: ItemInstance?,
	gadget2: ItemInstance?,
	helmet: ItemInstance?,
	vest: ItemInstance?,
	backpack: ItemInstance?,
}

export type TopGameDetail = {
	kills: number, -- points des kills de joueurs
	bots: number, -- points des kills de mercenaires IA
	robots: number, -- points des robots détruits
	loot: number, -- points de la valeur du loot extrait
	extracted: boolean,
}

export type TopGame = {
	score: number,
	mode: string,
	date: number,
	detail: TopGameDetail?, -- détail du score (écran Profil)
}

-- Partie en cours : l'équipement emporté est retiré du profil au départ et
-- conservé ici. Si la partie ne se termine pas normalement (échec de
-- téléportation, serveur planté), il est restitué au retour au Terminus.
export type ActiveMatch = {
	id: string,
	startedAt: number,
	mode: string,
	insurance: string?,
	snapshot: { loadout: Loadout, bag: { ItemInstance } },
}

export type Profile = {
	version: number,
	createdAt: number,
	level: number,
	xp: number,
	credits: number,
	noyaux: number,
	vault: { ItemInstance }, -- coffre
	loadout: Loadout, -- emplacements équipés
	bag: { ItemInstance }, -- contenu du sac / des poches (préparé au Terminus)
	tempItem: ItemInstance?,
	hasVaultExtension: boolean,
	freeCrate: { stored: number, lastGrantUnix: number },
	pity: { [string]: number }, -- compteurs de garantie par caisse
	cosmeticsOwned: { [string]: boolean },
	cosmeticsEquipped: { [string]: string },
	pendingInsurance: { ItemInstance }?,
	pendingLoot: { ItemInstance }, -- loot extrait en attente de l'écran de tri
	activeMatch: ActiveMatch?,
	insuranceTier: string?, -- assurance choisie pour la prochaine partie (payée au départ)
	season: { id: number, top10: { TopGame } },
	seasonHistory: { { id: number, rank: string } },
	bestScoreByMode: { [string]: number },
	stats: {
		matchesPlayed: number,
		extractions: number,
		deaths: number,
		playerKills: number,
		botKills: number,
		robotKills: number,
	},
	tutorialDone: boolean,
	settings: { [string]: any },
	processedReceipts: { [string]: number }, -- PurchaseId → horodatage
	receiptOrder: { string }, -- ordre d'arrivée (pour borner la mémoire)
}

-- Vue publique du profil envoyée au client (jamais de données internes).
export type ProfileView = {
	level: number,
	xp: number,
	xpToNext: number,
	credits: number,
	noyaux: number,
	vault: { ItemInstance },
	vaultCapacity: number,
	loadout: Loadout,
	bag: { ItemInstance },
	tempItem: ItemInstance?,
	hasVaultExtension: boolean,
	freeCrate: { stored: number, nextGrantUnix: number? },
	pendingLoot: { ItemInstance },
	pendingInsuranceCount: number,
	insuranceTier: string?,
	rank: string,
	rankingScore: number,
	seasonId: number,
	top10: { TopGame },
	seasonHistory: { { id: number, rank: string } },
	bestScoreByMode: { [string]: number },
	tutorialDone: boolean,
	settings: { [string]: any },
	stats: { [string]: number },
	pity: { [string]: number },
	cosmeticsOwned: { [string]: boolean },
	cosmeticsEquipped: { [string]: string },
}

-- Groupe duo (Terminus), envoyé à ses membres.
export type PartyMemberView = {
	userId: number,
	name: string,
	platform: string?,
}

export type PartyView = {
	leaderUserId: number,
	members: { PartyMemberView },
}

-- État de la file d'attente, envoyé au joueur (et à son coéquipier).
export type QueueView = {
	status: "idle" | "queued" | "teleporting",
	modeId: string?,
	format: string?,
	group: string?,
	forcedCrossplay: boolean?,
	players: number?,
	needed: number?,
	since: number?, -- os.time() de l'entrée dans la file
	suggestCrossplay: boolean?,
}

return {}
