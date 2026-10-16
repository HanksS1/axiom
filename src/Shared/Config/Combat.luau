--!strict
--[[
	Règles de combat (sections 5.2, 6.1 à 6.11).
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

return Freeze.deep({
	maxHealth = 100,

	movement = {
		walkSpeed = 14,
		sprintSpeed = 22,
		crouchSpeed = 8,
		proneSpeed = 4,
		jumpHeight = 7,
		sprintToFireDelay = 0.15,
		-- Appui de détente gardé en mémoire (semi-auto, rafale, mêlée) : seulement
		-- pendant ce délai, et seulement si le tir attend la fin de la cadence. Un
		-- clic pendant un rechargement, une surchauffe ou sans cellules est oublié.
		triggerBuffer = 0.25,
		proneTransition = 0.4,
		crouchAccuracyBonus = 0.15, -- réduit la dispersion de 15 %
		proneAccuracyBonus = 0.30,
		-- Pas de dispersion supplémentaire en visée (« ADS ») précisée par le
		-- document : valeur de départ, à ajuster pendant les tests.
		aimAccuracyBonus = 0.5,
		-- Appui long sur la touche accroupi/couché (secondes).
		proneHoldThreshold = 0.35,
		-- Dispersion supplémentaire en mouvement (× la dispersion de base).
		movingSpreadMultiplier = 1.5,
		-- En l'air (saut, chute) : les tirs partent de travers. Dispersion × multiplicateur
		-- + bonus fixe (degrés), pour que même une arme très précise devienne imprécise.
		-- Aucune posture ni visée ne compense (on ne vise pas en sautant).
		airborneSpreadMultiplier = 2.5,
		airborneSpreadBonus = 4,
		-- Vitesse pendant un étourdissement (× la vitesse de marche).
		stunMoveMultiplier = 0.2,
		-- Hauteur des hanches (HipHeight) selon la posture, en studs.
		-- Valeurs pour un avatar R15 standard (à ajuster avec les animations).
		standHipHeight = 2,
		crouchHipOffset = -1.1,
	},

	-- Visée assistée (5.4) : manette et mobile uniquement, jamais à la souris.
	-- `strength` (paramètre joueur, 0..1) module ralentissement et adhérence.
	aimAssist = {
		cone = 6, -- degrés autour du centre de l'écran
		range = 140,
		slowdown = 0.45, -- réduction maximale de la vitesse de rotation sur une cible
		pull = 7, -- degrés/s maximum d'adhérence vers la cible
		refresh = 0.05, -- secondes entre deux recherches de cible
	},

	-- Entrées : un appui tenu au-delà de ce délai (secondes) est un « appui long »
	-- (couché, ping « Danger », consommable à la manette…).
	input = {
		longPress = 0.35,
	},

	camera = {
		fieldOfView = 70,
		aimFieldOfView = 55,
		distance = 10,
		aimDistance = 6,
		shoulderOffset = Vector3.new(1.75, 0.6, 0),
		aimShoulderOffset = Vector3.new(1.4, 0.5, 0),
		crouchOffsetY = -1.1,
		proneOffsetY = -2.2,
		transitionTime = 0.15,
		-- Lunette (armes avec `scope`, l'Aiguille) : passage progressif à la première
		-- personne en visant (secondes pour basculer entièrement).
		scopeTransitionTime = 0.3,
	},

	-- Hors partie (stand de tir, arène de test) : délai avant réapparition.
	respawnTime = 3,

	-- Au-delà de la portée efficace : dégâts dégressifs.
	-- QUESTION OUVERTE : le document ne précise pas ce qui se passe au-delà
	-- de la portée efficace. Valeurs provisoires : dégâts pleins jusqu'à la
	-- portée efficace, puis baisse linéaire jusqu'à 50 % à 2× la portée
	-- efficace, et aucun dégât au-delà de 3×.
	falloff = {
		endRangeMultiplier = 2,
		minDamageMultiplier = 0.5,
		maxRangeMultiplier = 3,
	},

	overheat = {
		max = 100,
		coolPerSecond = 30,
		coolDelay = 0.4,
		lockDuration = 2.5,
	},

	parry = {
		meleeFrontalReduction = 0.60,
		frontalAngle = 120, -- angle (degrés) considéré comme « de face »
		moveSpeedMultiplier = 0.5,
		perfectWindow = 0.25,
		perfectStun = 0.8,
		failedPerfectCooldown = 0.5,
	},

	death = {
		disintegrateDuration = 1.2,
	},

	revive = {
		orbLifetime = 90,
		orbHealth = 100,
		acceleratorMinDistance = 80,
		acceleratorMaxDistance = 200,
		channelTime = 5,
		reviveHealth = 50,
	},

	-- Mêlée : tolérance de portée (latence) et angle d'attaque (cône frontal).
	melee = {
		rangeTolerance = 2.5,
		maxAngle = 75, -- demi-angle du cône devant l'attaquant (degrés)
	},

	-- Projectiles lents simulés par le serveur (Lance-clous, Court-Circuit).
	projectiles = {
		maxLifetime = 6, -- secondes de vol au maximum
		maxActive = 8, -- projectiles en vol par tireur
		splashBodyRadius = 1.5, -- rayon du corps ajouté au rayon de l'explosion
	},

	-- Repoussement (Gantelet à impulsion) : la distance vient de l'arme.
	knockback = {
		duration = 0.4, -- durée du vol plané (secondes)
	},

	-- Contrôle de mouvement côté serveur (section 19.4).
	movementGuard = {
		interval = 0.25, -- secondes entre deux contrôles
		speedTolerance = 1.3, -- × vitesse autorisée
		flatTolerance = 2, -- studs ajoutés par contrôle (latence, glissades)
		maxVerticalRise = 12, -- studs de montée par contrôle (saut, escaliers)
		strikesBeforeCorrection = 2, -- infractions consécutives avant recalage
		speedGraceTime = 0.6, -- délai pendant lequel l'ancienne vitesse reste tolérée
		-- Pic de latence : un joueur immobile vu du serveur peut ensuite rattraper
		-- jusqu'à ce temps de déplacement d'un coup (secondes) sans être recalé.
		catchUpWindow = 1.0,
	},

	-- Validation serveur des tirs (section 6.11).
	validation = {
		-- Tolérance sur la cadence (le réseau regroupe parfois les paquets).
		fireRateTolerance = 0.85,
		-- Écart maximal entre la position déclarée du tireur et sa position serveur.
		maxShooterPositionError = 12,
		-- Marge ajoutée à la portée maximale.
		rangeTolerance = 6,
		-- Écart maximal entre le point d'impact déclaré et la cible (latence).
		maxHitPositionError = 8,
		-- Âge maximal d'un tir déclaré (secondes).
		maxShotAge = 1.0,
		-- Tolérance sur le délai sprint → tir (latence).
		sprintToFireTolerance = 0.05,
		-- Direction des impacts : chacun doit rester dans le cône de dispersion
		-- maximal de l'arme (debout, en mouvement, en l'air) autour de la direction
		-- déclarée, plus cette marge (degrés : arrondis, visée assistée).
		directionTolerance = 3,
		-- En deçà (studs), l'angle n'a plus de sens (cible au contact) : pas de contrôle.
		directionMinDistance = 2,
		-- Couverts légers traversés au plus par un tir perçant (Canon à rayons X).
		-- Lu par le client (rayon affiché) ET le serveur (contrôle) : doit être égal.
		maxCoversCrossed = 4,
	},
})
