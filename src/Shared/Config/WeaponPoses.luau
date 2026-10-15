--!strict
--[[
	Postures des armes tenues (calcul : Shared/Visuals/WeaponPose ;
	application à chaque image : Client/Controllers/WeaponPoseController).

	ARMES À DISTANCE : montées devant le torse, tenues à deux mains (prise,
	visée, recul, sprint, recharge).
	MÊLÉE : l'arme reste dans la main droite et suit les animations de marche
	(comme avant) ; seul le coup est animé (bras, poignet et buste).

	Repère des positions, en studs, pour un avatar R15 standard (haut du
	torse 2 × 1,6 × 1 ; mis à l'échelle de l'avatar) : origine au centre du
	haut du torse, +X à droite, +Y en haut, -Z devant.
	- Armes à distance : repère « visée », sans la rotation du buste (`twist`),
	  compensée pour que l'arme vise toujours droit devant.
	- Coups de mêlée : repère du torse (le buste tourne avec le geste).

	Une « prise » (`Frame`) :
	- `hand` : position de la main droite (sur la poignée) ;
	- `tip` : direction de la bouche (ou de la tête de l'arme de mêlée) ;
	- `up` : dessus de l'arme (facultatif, par défaut vers le haut) ;
	- `left` : position de la main gauche quand elle ne tient pas l'arme
	  (main qui va chercher une cellule, poing de garde du Gantelet) ;
	- `twist` (coups de mêlée) : buste tourné vers la droite (degrés, < 0 :
	  vers la gauche).

	Toutes les prises sont vérifiées hors Studio (tests/specs/weaponpose.spec.luau) :
	l'arme ne traverse ni le torse, ni la tête, ni le bassin, et les mains
	atteignent leur place. Pour en régler une : tests/tools/weapon_pose_check.luau
	(contrôle) et tests/tools/weapon_pose_tune.luau (recherche de prises valides).
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

export type Frame = {
	hand: Vector3,
	tip: Vector3?,
	up: Vector3?,
	left: Vector3?,
	twist: number?,
}

export type Style = {
	-- Buste tourné vers la droite (degrés) : l'épaule gauche avance et la main
	-- gauche atteint l'arme (bras R15 courts pour un torse large). Nul couché.
	twist: number,
	sprintTwist: number, -- idem en sprint
	-- Point autour duquel l'arme pivote pour la part de visée que le buste ne prend pas.
	pivot: Vector3,
	pitchFactor: number,
	-- Main gauche : "support" = sur l'arme (point `support` de chaque arme).
	left: "support"?,
	-- Direction vers laquelle pointent les coudes (droit, gauche).
	rightPole: Vector3,
	leftPole: Vector3,
	ready: Frame,
	sprint: Frame,
	reload: Frame,
}

-- Coup de mêlée : armé (`windup`), passage (`through`, facultatif), fin du coup (`strike`).
export type Swing = { windup: Frame, through: Frame?, strike: Frame }

export type SwingSet = {
	rightPole: Vector3,
	leftPole: Vector3,
	-- Main gauche : "support" = sur le manche (Marteau), "fist" = poing de garde
	-- (`left` des prises), nil = libre (elle garde son animation).
	left: ("support" | "fist")?,
	swings: { Swing }, -- gestes alternés d'un coup à l'autre
}

export type Recoil = {
	back: number, -- recul vers l'arrière (studs) : faible, l'épaule encaisse
	angle: number, -- relèvement du canon (degrés), autour de la crosse
	roll: number, -- bascule de côté aléatoire (degrés)
	recover: number, -- vitesse de retour (par seconde ; plus haut = plus sec)
}

local v = Vector3.new

local styles: { [string]: Style } = {
	-- Pistolets : tenus à deux mains, bras tendus à hauteur de la poitrine.
	pistol = {
		twist = 10,
		sprintTwist = 10,
		pivot = v(0.25, 0.55, 0),
		pitchFactor = 1,
		left = "support",
		rightPole = v(1, -1, 0.4),
		leftPole = v(-1, -1, 0.4),
		ready = { hand = v(0.3, 0.4, -1.3), tip = v(0, 0, -1) },
		sprint = { hand = v(0.4, -0.3, -0.9), tip = v(0, -0.6, -0.8) },
		reload = {
			hand = v(0.3, 0.1, -1.1),
			tip = v(0.1, 0.35, -1),
			up = v(-0.6, 0.8, 0),
			left = v(-0.25, -0.7, -0.4),
		},
	},
	-- Fusils, mitraillettes, fusil à pompe, Lance-clous, Aiguille, Court-Circuit :
	-- épaulés, buste de trois quarts, arme à hauteur de joue à droite de la tête.
	rifle = {
		twist = 45,
		sprintTwist = 45,
		pivot = v(0.7, 1.05, -0.3),
		pitchFactor = 1,
		left = "support",
		rightPole = v(1.2, -1, 0.5),
		leftPole = v(-0.3, -1, 0),
		ready = { hand = v(0.7, 0.8, -0.9), tip = v(0, 0, -1) },
		-- En courant : arme en travers de la poitrine, canon vers le haut à gauche.
		sprint = { hand = v(0.4, -0.1, -0.9), tip = v(-0.5, 0.6, -0.6) },
		-- Recharge : canon baissé vers la gauche, la main gauche va chercher une cellule.
		reload = { hand = v(0.9, 0.7, -0.9), tip = v(-0.2, -0.3, -1), left = v(-0.2, -0.75, -0.35) },
	},
	-- Armes lourdes (Mitrailleuse de Bastion, Canon à rayons X) : à la hanche,
	-- devant le flanc droit.
	heavy = {
		twist = 40,
		sprintTwist = 40,
		pivot = v(0.6, 0.25, -0.8),
		pitchFactor = 1,
		left = "support",
		rightPole = v(1, -1, 0.5),
		leftPole = v(-0.6, -1, 0.2),
		ready = { hand = v(0.6, 0, -0.8), tip = v(0, 0.05, -1) },
		sprint = { hand = v(0.5, 0, -0.8), tip = v(0, -0.3, -0.95) },
		reload = { hand = v(0.6, -0.1, -0.9), tip = v(0, 0.3, -1), left = v(-0.2, -0.8, -0.3) },
	},
}

-- Prise de chaque arme à distance : style, et point où se pose la main gauche
-- (repère de l'arme : centre du cœur, -Z vers la bouche, voir Config/Visuals et
-- Shared/Visuals/ItemModels). Fusils : au niveau du chargeur (le garde-main est
-- hors de portée d'un bras R15).
local weapons: { [string]: { style: string, support: Vector3 } } = {
	scrap_laser_pistol = { style = "pistol", support = v(-0.2, -0.35, 0.35) },
	vigil_pistol = { style = "pistol", support = v(-0.2, -0.35, 0.4) },
	crackler = { style = "rifle", support = v(0, -0.3, -0.15) },
	sentinel_rifle = { style = "rifle", support = v(0, -0.3, 0.35) },
	hullbreaker = { style = "rifle", support = v(0, -0.3, 0.25) },
	mag_nailer = { style = "rifle", support = v(0, -0.3, 0.2) },
	needle = { style = "rifle", support = v(0, -0.3, 0.75) },
	short_circuit = { style = "rifle", support = v(0, -0.3, 0.25) },
	bastion_minigun = { style = "heavy", support = v(0, -0.3, 0.45) },
	xray_cannon = { style = "heavy", support = v(0, -0.3, 0.35) },
}

-- Coups de mêlée (repère du torse). `through` : passage obligé de l'arme entre
-- l'armé et la frappe (devant le personnage, sans traverser la tête).
local swings: { [string]: SwingSet } = {
	-- Barre à mine, Sabre laser, Lame vibrante : coup en diagonale de haut à
	-- droite vers le bas à gauche, puis revers.
	slash = {
		rightPole = v(1, -1, 0.3),
		leftPole = v(-1, -1, 0.3),
		left = nil,
		swings = {
			{
				windup = { hand = v(1.1, 1.1, -0.7), tip = v(0.3, 0.6, 0.75), twist = 25 },
				through = { hand = v(0.75, 0.75, -1.35), tip = v(0, 0.85, -0.5), twist = 5 },
				strike = { hand = v(0.35, 0.05, -1.15), tip = v(-0.75, -0.4, -0.55), twist = -20 },
			},
			{
				windup = { hand = v(-0.1, 0.9, -1.1), tip = v(-0.7, 0.6, 0.3), twist = -20 },
				through = { hand = v(0.4, 0.6, -1.4), tip = v(0.1, 0.8, -0.6), twist = 0 },
				strike = { hand = v(1.2, -0.2, -1.1), tip = v(0.75, -0.35, -0.55), twist = 20 },
			},
		},
	},
	-- Marteau hydraulique : à deux mains (gauche au bout du manche), frappe par
	-- le haut, puis balayage horizontal.
	slam = {
		rightPole = v(1, -1, 0.3),
		leftPole = v(-1, -0.6, 0.3),
		left = "support",
		swings = {
			{
				windup = { hand = v(0.25, 1.15, -1.0), tip = v(0.5, 0.8, 0.35), twist = 15 },
				through = { hand = v(0.15, 0.9, -1.3), tip = v(0, 0.6, -0.8), twist = 5 },
				strike = { hand = v(0.3, 0, -1.2), tip = v(0, -0.75, -0.65), twist = 0 },
			},
			{
				windup = { hand = v(0.3, 0.4, -1.0), tip = v(0.8, 0.3, 0.5), twist = 30 },
				through = { hand = v(0.2, 0.45, -1.35), tip = v(0.3, 0.1, -1), twist = 0 },
				strike = { hand = v(0.05, 0.4, -1.15), tip = v(-0.85, 0, -0.5), twist = -25 },
			},
		},
	},
	-- Gantelet à impulsion : direct, puis crochet ; l'autre poing reste en garde.
	punch = {
		rightPole = v(1, -1, 0.3),
		leftPole = v(-1, -1, 0.3),
		left = "fist",
		swings = {
			{
				windup = { hand = v(1.45, 0.45, -1.35), tip = v(0, 0, -1), left = v(-0.45, 0.6, -0.9), twist = 20 },
				through = { hand = v(1.0, 0.5, -1.55), tip = v(0, 0, -1), twist = 0 },
				strike = { hand = v(0.6, 0.55, -1.55), tip = v(0, 0, -1), left = v(-0.5, 0.5, -0.75), twist = -15 },
			},
			{
				windup = { hand = v(1.7, 0.75, -1.0), tip = v(0.4, 0, -1), left = v(-0.45, 0.6, -0.9), twist = 25 },
				through = { hand = v(1.0, 0.65, -1.55), tip = v(0, 0, -1), twist = 0 },
				strike = {
					hand = v(0.35, 0.55, -1.45),
					tip = v(-0.6, 0, -0.8),
					left = v(-0.55, 0.5, -0.75),
					twist = -25,
				},
			},
		},
	},
}

-- Geste de chaque arme de mêlée (et point de la main gauche sur le manche).
local melee: { [string]: { swing: string, support: Vector3? } } = {
	shock_crowbar = { swing = "slash" },
	laser_saber = { swing = "slash" },
	vibro_blade = { swing = "slash" },
	hydraulic_hammer = { swing = "slam", support = v(0, 0, 1.7) },
	pulse_gauntlet = { swing = "punch" },
}

-- Recul par famille d'arme (`class` dans Config/Weapons).
local recoil: { [string]: Recoil } = {
	pistol = { back = 0.15, angle = 10, roll = 2, recover = 12 },
	smg = { back = 0.04, angle = 3, roll = 1.5, recover = 18 },
	rifle = { back = 0.06, angle = 4, roll = 1, recover = 16 },
	shotgun = { back = 0.1, angle = 12, roll = 3, recover = 8 },
	nailer = { back = 0.06, angle = 6, roll = 1, recover = 12 },
	railgun = { back = 0.1, angle = 10, roll = 1, recover = 6 },
	heavy = { back = 0.04, angle = 1.5, roll = 2.5, recover = 20 },
	beam = { back = 0.02, angle = 0.6, roll = 1.5, recover = 20 },
	launcher = { back = 0.1, angle = 10, roll = 2, recover = 7 },
}

return Freeze.deep({
	styles = styles,
	weapons = weapons,
	swings = swings,
	melee = melee,
	recoil = recoil,
	-- Le canon se relève autour d'un point situé à cette distance derrière la
	-- main droite (la crosse contre l'épaule) : la crosse ne plonge pas dans le corps.
	recoilPivotBack = 1.0,

	-- Haut du torse d'un avatar R15 standard (échelle 1 des positions ci-dessus).
	referenceTorsoHeight = 1.6,

	pitch = {
		max = 70, -- visée en haut / en bas au-delà : bloquée (degrés)
		-- Part de la visée prise par le buste qui se penche : l'arme reste calée
		-- contre l'épaule (sinon la crosse rentre dans le torse ou la tête).
		waistShare = 0.8,
		headShare = 0.8, -- la tête suit le reste de la visée
	},

	-- Couché (torse à l'horizontale) : arme ramenée vers le centre et les épaules
	-- (repère visée, avant le quart de tour), tête relevée pour regarder devant.
	prone = {
		shift = Vector3.new(-0.25, 0, 0.5),
		head = 70, -- degrés
	},

	-- Coup de mêlée : durée = `swingScale` / coups par seconde, bornée. Le bras
	-- quitte l'animation pendant l'armé (`windup`), frappe jusqu'à `strike`, puis
	-- y revient.
	swingScale = 0.75,
	swingMin = 0.3,
	swingMax = 0.65,
	swingTiming = { windup = 0.3, strike = 0.55 },

	-- Transitions (par seconde) entre prises : sprint, visée des autres joueurs.
	blendRate = 10,
	aimSmoothing = 12,
	-- Recharge : entrée et sortie de la prise de recharge (fraction de la durée).
	reloadEase = 0.15,

	-- Au-delà, les personnages ne sont plus posés (bras animés par défaut).
	maxDistance = 250,

	-- Visée envoyée au serveur (pour que les autres voient l'arme pointer en haut /
	-- en bas) : seulement si elle a changé d'au moins `aimSendStep` degrés, au plus
	-- toutes les `aimSendInterval` secondes.
	aimSendStep = 3,
	aimSendInterval = 0.15,
})
