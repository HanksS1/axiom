--!strict
--[[
	Robots d'AXIOM (section 10) : stats de base, comportement, densité et loot.
	Les multiplicateurs par mode (PV, dégâts, précision, réaction) sont dans Modes.luau.

	Les valeurs de comportement (vitesses, portées d'attaque, cadences) ne
	sont pas précisées par le document : ce sont des valeurs de départ.

	Équilibrage après les premiers tests (les robots ne doivent être ni une
	corvée ni une mort surprise) — écarts assumés avec le tableau 10.1 :
	- toute attaque lourde est ANNONCÉE (`windup`, `meleeWindup`) : le coup
	  ne part qu'à la fin de l'annonce, et rate si la cible s'est mise à
	  couvert ou hors de portée entre-temps ;
	- un Traqueur se sème en sprintant (17 < 22), sa morsure est moins forte ;
	- Bastion, Exécuteur et Gardien ont moins de PV (combats plus courts) ;
	- le Bastion tire des rafales plus courtes, avec une vraie pause ;
	- le nombre de robots qui attaquent la même cible en même temps est
	  plafonné selon le mode (Modes.robots.maxAttackers).
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

export type LootEntry = {
	itemId: string?, -- objet précis
	pool: string?, -- ou tirage dans une famille (« consumable », « equipment »…)
	chance: number, -- 0..1
	quantity: number?, -- pour les cellules : nombre de cellules
	hardModeOnly: boolean?,
}

export type RobotDef = {
	id: string,
	health: number,
	damage: number, -- dégâts de l'attaque principale (mêlée ou tir)
	rangedDamage: number?, -- Exécuteur : alterne mêlée (damage) et tir (rangedDamage)
	attack: "ranged" | "melee" | "hybrid",
	scorePoints: number,
	visionRange: number,
	flying: boolean,
	speed: number, -- studs/s
	fireInterval: number?, -- secondes entre deux tirs
	burst: number?, -- tirs par rafale (Bastion : mitrailleuse rotative)
	burstPause: number?, -- pause entre deux rafales (secondes)
	windup: number?, -- annonce (secondes) avant un tir lourd ou une rafale
	meleeWindup: number?, -- annonce (secondes) avant un coup de mêlée
	attackRange: number, -- distance d'engagement au tir
	meleeRange: number?,
	meleeInterval: number?,
	preferredDistance: number, -- distance que le robot cherche à garder
	weakSpotMultiplier: number?, -- point faible (dos) du Bastion
	alertRadius: number?, -- la Mouche alerte les robots proches
	packSize: { min: number, max: number }?,
	conditionShift: number, -- décalage d'état du loot (+1 pour les élites)
	guaranteedItems: { min: number, max: number }?,
	size: Vector3, -- encombrement du modèle provisoire
	loot: { LootEntry },
	stationary: boolean?, -- fixe (tourelle) : ne se déplace jamais
	color: Color3?, -- couleur du modèle provisoire (Gardiens propres à une carte)
	guardian: boolean?, -- mini-boss : signalé à part sur le radar, jamais limité par le plafond d'attaquants
}

local robots: { [string]: RobotDef } = {
	fly = {
		id = "fly",
		health = 30,
		damage = 5,
		attack = "ranged",
		scorePoints = 10,
		visionRange = 80,
		flying = true,
		speed = 20,
		fireInterval = 0.8,
		attackRange = 45,
		preferredDistance = 25,
		alertRadius = 40,
		conditionShift = 0,
		size = Vector3.new(1.6, 1, 1.6),
		loot = {
			{ pool = "cells", chance = 0.5, quantity = 15 },
		},
	},
	stalker = {
		id = "stalker",
		health = 80,
		damage = 12,
		attack = "melee",
		scorePoints = 20,
		visionRange = 60,
		flying = false,
		speed = 17,
		attackRange = 4,
		meleeRange = 4.5,
		meleeInterval = 1.1,
		meleeWindup = 0.3,
		preferredDistance = 2,
		packSize = { min = 2, max = 3 },
		conditionShift = 0,
		size = Vector3.new(2, 2, 3.4),
		loot = {
			{ pool = "cells", chance = 1, quantity = 15 },
			{ pool = "consumable", chance = 0.3 },
		},
	},
	sentinel = {
		id = "sentinel",
		health = 150,
		damage = 10,
		attack = "ranged",
		scorePoints = 30,
		visionRange = 100,
		flying = false,
		speed = 12,
		fireInterval = 0.45,
		attackRange = 70,
		preferredDistance = 30,
		conditionShift = 0,
		size = Vector3.new(2, 5, 1.2),
		loot = {
			{ itemId = "cell_standard", chance = 1, quantity = 20 },
			{ itemId = "sentinel_rifle", chance = 0.08 },
			{ pool = "consumable", chance = 0.3 },
		},
	},
	bastion = {
		id = "bastion",
		health = 480,
		damage = 8,
		attack = "ranged",
		scorePoints = 60,
		visionRange = 90,
		flying = false,
		speed = 7,
		fireInterval = 0.12,
		burst = 8,
		burstPause = 1.8,
		windup = 0.6, -- mise en rotation de la mitrailleuse
		attackRange = 60,
		preferredDistance = 25,
		weakSpotMultiplier = 2.5,
		conditionShift = 0,
		size = Vector3.new(4, 6, 3),
		loot = {
			{ itemId = "cell_heavy", chance = 1, quantity = 30 },
			{ itemId = "bastion_minigun", chance = 0.15 },
			{ itemId = "vest", chance = 0.20 },
		},
	},
	executor = {
		id = "executor",
		health = 340,
		damage = 25,
		rangedDamage = 15,
		attack = "hybrid",
		scorePoints = 80,
		visionRange = 120,
		flying = false,
		speed = 15,
		fireInterval = 0.7,
		attackRange = 50,
		meleeRange = 6,
		meleeInterval = 1.0,
		meleeWindup = 0.45,
		preferredDistance = 4,
		conditionShift = 1,
		guaranteedItems = { min = 1, max = 1 },
		size = Vector3.new(2.4, 6, 1.4),
		loot = {
			{ itemId = "vibro_blade", chance = 0.10 },
		},
	},
	-- Tourelle d'AXIOM (Terres Brûlées, base Kestrel) : fixe, destructible.
	turret = {
		id = "turret",
		health = 250,
		damage = 8,
		attack = "ranged",
		scorePoints = 30,
		visionRange = 90,
		flying = false,
		speed = 0,
		stationary = true,
		fireInterval = 0.4,
		attackRange = 85,
		preferredDistance = 0,
		conditionShift = 0,
		size = Vector3.new(3, 4, 3),
		loot = {
			{ itemId = "cell_heavy", chance = 0.6, quantity = 15 },
			{ pool = "consumable", chance = 0.25 },
		},
	},
	warden = {
		id = "warden",
		health = 1500,
		damage = 30, -- « selon la carte » : valeur par défaut, surchargée par carte
		attack = "ranged",
		guardian = true,
		scorePoints = 250,
		visionRange = 120,
		flying = false,
		speed = 8,
		fireInterval = 1.4,
		windup = 0.9, -- tir chargé : visée rouge sur la cible avant le tir
		meleeWindup = 0.8,
		attackRange = 90,
		preferredDistance = 35,
		conditionShift = 1,
		guaranteedItems = { min = 2, max = 3 },
		size = Vector3.new(6, 10, 4),
		loot = {
			{ itemId = "calibration_module", chance = 0.40, hardModeOnly = true },
		},
	},
}

return Freeze.deep({
	byId = robots,

	-- Densité réduite d'environ 20 % après les tests (document : 20 à 28 robots,
	-- vague de 6 à 10) : l'auteur préfère moins de robots et plus de fluidité.
	-- Chaque robot est un Humanoid simulé par le serveur (physique, chemins, vision).
	density = {
		minActive = 16,
		maxActive = 22,
		garrisonShare = 0.6, -- 60 % en garnison dans les zones à risque
		-- Plafond absolu pendant la vague d'alerte (22 + 8).
		hardCap = 30,
		-- Aucun robot n'apparaît à moins de cette distance d'un point de départ
		-- des joueurs (début de partie), ni d'un joueur vivant (vague d'alerte).
		spawnClearance = 40,
		waveClearance = 70,
		-- Composition des garnisons et des patrouilles (poids).
		garrison = { sentinel = 5, bastion = 2, executor = 1.5, stalker = 2 },
		patrol = { fly = 4, stalker = 3, sentinel = 2 },
		wave = { sentinel = 4, stalker = 3, executor = 1, fly = 2 },
	},

	ai = {
		visionAngle = 90,
		gunshotHearingRadius = 60, -- surchargé par l'arme (noiseRadius)
		-- Décisions de l'IA par seconde (entre 5 et 10). Le MOUVEMENT, lui, est continu :
		-- déplacement (Humanoid:MoveTo, AlignPosition) et orientation (AlignOrientation)
		-- sont des contraintes physiques résolues à chaque image et interpolées par
		-- Roblox chez les clients. Monter cette valeur rend les robots plus réactifs,
		-- pas plus fluides, et coûte du serveur (×1,25 de calcul d'IA à 10).
		updateRate = 8,
		-- Orientation lissée : vitesse de rotation maximale (radians/s) et réactivité de
		-- la contrainte (plus haut = suit le cap plus vite). Tourelles (ancrées) : même
		-- réactivité, appliquée par la boucle du serveur.
		turnRate = 7,
		turnResponsiveness = 14,
		sleepDistance = 150, -- logique lourde désactivée sans joueur à moins de 150 studs
		suspicionTime = 1.0,
		searchTime = 8,
		patrolRadius = 40,
		garrisonRadius = 14,
		pathRefresh = 1.0, -- secondes entre deux calculs de chemin
		threatMemory = 6, -- secondes pendant lesquelles l'attaquant reste prioritaire
		missSpread = 4, -- écart (studs) d'un tir manqué
		-- Précision réelle = précision du mode × portée × mouvement de la cible.
		accuracy = {
			nearRatio = 0.4, -- pleine précision jusqu'à 40 % de la portée
			farFactor = 0.6, -- à portée maximale
			sprintSpeed = 18, -- au-delà (studs/s), la cible est « en course »
			sprintFactor = 0.7,
		},
		-- Durée (secondes) pendant laquelle un robot garde son tour d'attaque
		-- sur une cible sans attaquer (voir Modes.robots.maxAttackers).
		engagementHold = 2,
		-- Après une réapparition (Gardien enfoui ou intangible) : délai sans attaque.
		reappearDelay = 1,
		-- Début de partie : les robots restent en veille quelques secondes (le temps
		-- de regarder autour de soi). Un robot touché se réveille aussitôt.
		wakeDelay = 12,
	},

	-- Détecteur du joueur (radar en haut à gauche, marqueurs de menace).
	threat = {
		radarRange = 90, -- studs couverts par le radar
		imminentRange = 28, -- un robot qui vous vise à cette distance : le radar clignote
		guardianImminentRange = 60,
		edgeRange = 160, -- au-delà du radar, un robot qui vous vise reste indiqué sur le bord
		maxBlips = 24,
		refresh = 0.1, -- secondes entre deux mises à jour du radar
		arcs = 4, -- marqueurs de direction autour du viseur (robots qui vous visent)
		arcMinAngle = 35, -- degrés : pas de marqueur pour un robot déjà dans le champ
	},
})
