--!strict
--[[
	Postures des armes tenues : prise en main, recul des tirs, coups de mêlée,
	recharge, sprint et garde (calcul : Shared/Visuals/WeaponPose ; application
	à chaque image : Client/Controllers/WeaponPoseController).

	Repère « visée » (toutes les positions ci-dessous), en studs, pour un
	avatar R15 standard (haut du torse de 1,6 de haut ; mis à l'échelle de
	l'avatar) : origine au centre du haut du torse, +X à droite, +Y en haut,
	-Z devant. La rotation du buste (`twist`) n'y figure pas : elle est
	compensée pour que l'arme vise toujours droit devant.

	Une « prise » (`Frame`) :
	- `hand` : position de la main droite (sur la poignée) ;
	- `tip` : direction de la bouche (ou de la tête de l'arme de mêlée) ;
	- `up` : dessus de l'arme (facultatif, par défaut vers le haut) ;
	- `left` : position de la main gauche quand elle ne tient pas l'arme
	  (poing de garde du Gantelet, main qui va chercher une cellule).

	Coup de mêlée : prise de départ → `windup` (armé) → `strike` (fin du coup)
	→ retour, aux instants `swingTiming` (fractions de la durée du coup). Deux
	coups alternés (`swings[1]`, `swings[2]`) pour ne pas répéter le même geste.
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

export type Frame = {
	hand: Vector3,
	tip: Vector3?,
	up: Vector3?,
	left: Vector3?,
}

export type Style = {
	-- Buste tourné vers la droite (degrés) : l'épaule gauche avance et la main
	-- gauche atteint le garde-main. Nul couché.
	twist: number,
	sprintTwist: number, -- idem en sprint
	-- Point autour duquel l'arme pivote pour viser en haut / en bas.
	pivot: Vector3,
	-- Part de l'inclinaison de la visée suivie par l'arme (mêlée : partielle).
	pitchFactor: number,
	-- Main gauche : "support" = sur l'arme (point `support` de chaque arme),
	-- "fist" = poing de garde (`left` des prises), nil = libre (animation de marche).
	left: ("support" | "fist")?,
	-- Direction vers laquelle pointent les coudes (droit, gauche).
	rightPole: Vector3,
	leftPole: Vector3,
	ready: Frame,
	sprint: Frame,
	reload: Frame?,
	parry: Frame?,
	swings: { { windup: Frame, strike: Frame } }?,
}

export type Recoil = {
	back: number, -- recul vers l'arrière (studs)
	angle: number, -- relèvement du canon (degrés)
	roll: number, -- bascule de côté aléatoire (degrés)
	recover: number, -- vitesse de retour (par seconde ; plus haut = plus sec)
}

local v = Vector3.new

local styles: { [string]: Style } = {
	-- Pistolets : tenus à deux mains, bras tendus à hauteur des yeux.
	pistol = {
		twist = 10,
		sprintTwist = 10,
		pivot = v(0.25, 0.55, 0),
		pitchFactor = 1,
		left = "support",
		rightPole = v(1, -1, 0.4),
		leftPole = v(-1, -1, 0.4),
		ready = { hand = v(0.3, 0.4, -1.3), tip = v(0, 0, -1) },
		sprint = { hand = v(0.15, -0.25, -0.8), tip = v(0, -0.6, -0.8) },
		reload = {
			hand = v(0.25, 0.05, -0.95),
			tip = v(0.1, 0.35, -1),
			up = v(-0.6, 0.8, 0),
			left = v(-0.25, -0.7, -0.4),
		},
	},
	-- Fusils, mitraillettes, fusil à pompe, Lance-clous, Aiguille, Court-Circuit :
	-- épaulés, crosse contre l'épaule droite, main gauche sur le garde-main.
	rifle = {
		twist = 35,
		sprintTwist = 35,
		pivot = v(0.3, 0.6, 0),
		pitchFactor = 1,
		left = "support",
		rightPole = v(1.2, -1, 0.5),
		leftPole = v(-0.3, -1, 0),
		ready = { hand = v(0.25, 0.4, -0.35), tip = v(0, 0, -1) },
		-- En courant : arme en travers de la poitrine, canon vers le haut à gauche.
		sprint = { hand = v(0.4, -0.2, -0.5), tip = v(-0.5, 0.6, -0.6) },
		-- Recharge : arme basculée sur le côté, la main gauche va chercher une cellule.
		reload = {
			hand = v(0.25, 0.05, -0.55),
			tip = v(0.05, 0.25, -1),
			up = v(-0.6, 0.8, 0),
			left = v(-0.2, -0.75, -0.35),
		},
	},
	-- Armes lourdes (Mitrailleuse de Bastion, Canon à rayons X) : à la hanche.
	heavy = {
		twist = 40,
		sprintTwist = 40,
		pivot = v(0.4, 0, 0),
		pitchFactor = 1,
		left = "support",
		rightPole = v(1, -1, 0.5),
		leftPole = v(-0.6, -1, 0.2),
		ready = { hand = v(0.45, -0.35, -0.4), tip = v(0, 0.05, -1) },
		sprint = { hand = v(0.4, -0.4, -0.3), tip = v(0, -0.3, -0.95) },
		reload = { hand = v(0.4, -0.4, -0.4), tip = v(0, 0.3, -1), left = v(-0.2, -0.8, -0.3) },
	},
	-- Mêlée à une main (Barre à mine, Sabre laser, Lame vibrante) : arme levée
	-- devant soi ; coups en diagonale, revers au coup suivant.
	oneHand = {
		twist = 0,
		sprintTwist = 0,
		pivot = v(0.5, 0.3, 0),
		pitchFactor = 0.4,
		left = nil,
		rightPole = v(1, -1, 0.3),
		leftPole = v(-1, -1, 0.3),
		ready = { hand = v(0.75, -0.2, -0.7), tip = v(0.1, 0.8, -0.6) },
		sprint = { hand = v(0.85, -0.45, -0.35), tip = v(0.15, -0.4, 0.9) },
		parry = { hand = v(0.55, 0.55, -0.95), tip = v(-0.95, 0.3, -0.1) },
		swings = {
			{
				windup = { hand = v(0.9, 1.0, -0.6), tip = v(0.3, 0.55, 0.75) },
				strike = { hand = v(0.05, -0.05, -1.0), tip = v(-0.8, -0.35, -0.5) },
			},
			{
				windup = { hand = v(-0.35, 0.6, -0.6), tip = v(-0.6, 0.65, 0.4) },
				strike = { hand = v(0.95, -0.25, -0.95), tip = v(0.8, -0.25, -0.55) },
			},
		},
	},
	-- Marteau hydraulique : à deux mains (gauche au bout du manche), tête
	-- au-dessus de l'épaule droite ; frappe par le haut, puis balayage horizontal.
	twoHand = {
		twist = 20,
		sprintTwist = 20,
		pivot = v(0.3, 0.2, 0),
		pitchFactor = 0.4,
		left = "support",
		rightPole = v(1, -1, 0.3),
		leftPole = v(-1, -0.6, 0.3),
		ready = { hand = v(0.1, -0.1, -0.75), tip = v(0.35, 0.85, 0.2) },
		sprint = { hand = v(0.2, -0.1, -0.6), tip = v(0.35, 0.6, 0.7) },
		parry = { hand = v(0, 0.4, -0.8), tip = v(0.95, 0.25, -0.1) },
		swings = {
			{
				windup = { hand = v(0.2, 0.95, -0.35), tip = v(0.1, 0.45, 0.9) },
				strike = { hand = v(0.25, 0.05, -0.85), tip = v(0, -0.7, -0.7) },
			},
			{
				windup = { hand = v(0.5, 0.35, -0.35), tip = v(0.8, 0.2, 0.55) },
				strike = { hand = v(0.05, 0.2, -0.85), tip = v(-0.85, 0, -0.5) },
			},
		},
	},
	-- Gantelet à impulsion : garde de boxeur, direct puis crochet.
	fist = {
		twist = 15,
		sprintTwist = 15,
		pivot = v(0.3, 0.5, 0),
		pitchFactor = 0.4,
		left = "fist",
		rightPole = v(1, -1, 0.3),
		leftPole = v(-1, -1, 0.3),
		ready = { hand = v(0.45, 0.45, -0.85), tip = v(0, 0, -1), left = v(-0.4, 0.55, -0.75) },
		sprint = { hand = v(0.75, -0.2, -0.5), tip = v(0, -0.3, -1), left = v(-0.7, -0.2, -0.5) },
		parry = { hand = v(0.3, 0.8, -0.75), tip = v(0, 0.3, -1), left = v(-0.3, 0.8, -0.75) },
		swings = {
			{
				windup = { hand = v(0.6, 0.35, -0.3), tip = v(0, 0, -1), left = v(-0.4, 0.6, -0.7) },
				strike = { hand = v(0.4, 0.5, -1.25), tip = v(0, 0, -1), left = v(-0.45, 0.5, -0.5) },
			},
			{
				windup = { hand = v(0.9, 0.4, -0.5), tip = v(0.3, 0, -1), left = v(-0.4, 0.6, -0.7) },
				strike = { hand = v(0.15, 0.5, -1.1), tip = v(-0.5, 0, -0.85), left = v(-0.5, 0.5, -0.45) },
			},
		},
	},
}

-- Prise de chaque arme : style, et point où se pose la main gauche (repère de
-- l'arme : centre du cœur, -Z vers la bouche, voir Config/Visuals et
-- Shared/Visuals/ItemModels).
local weapons: { [string]: { style: string, support: Vector3? } } = {
	scrap_laser_pistol = { style = "pistol", support = v(-0.2, -0.35, 0.35) },
	vigil_pistol = { style = "pistol", support = v(-0.2, -0.35, 0.4) },
	crackler = { style = "rifle", support = v(0, -0.45, -0.25) },
	sentinel_rifle = { style = "rifle", support = v(0, -0.3, -0.2) },
	hullbreaker = { style = "rifle", support = v(0, -0.4, -0.35) },
	mag_nailer = { style = "rifle", support = v(0, -0.15, -0.3) },
	needle = { style = "rifle", support = v(0, -0.3, 0.25) },
	bastion_minigun = { style = "heavy", support = v(-0.25, -0.3, 0.3) },
	xray_cannon = { style = "heavy", support = v(-0.3, -0.3, 0.2) },
	short_circuit = { style = "rifle", support = v(0, -0.35, -0.25) },
	shock_crowbar = { style = "oneHand" },
	laser_saber = { style = "oneHand" },
	vibro_blade = { style = "oneHand" },
	hydraulic_hammer = { style = "twoHand", support = v(0, 0, 1.7) },
	pulse_gauntlet = { style = "fist" },
}

-- Recul par famille d'arme (`class` dans Config/Weapons).
local recoil: { [string]: Recoil } = {
	pistol = { back = 0.2, angle = 9, roll = 2, recover = 12 },
	smg = { back = 0.08, angle = 3, roll = 1.5, recover = 18 },
	rifle = { back = 0.12, angle = 4, roll = 1, recover = 16 },
	shotgun = { back = 0.4, angle = 16, roll = 3, recover = 8 },
	nailer = { back = 0.15, angle = 6, roll = 1, recover = 12 },
	railgun = { back = 0.45, angle = 14, roll = 1, recover = 6 },
	heavy = { back = 0.05, angle = 1.5, roll = 2.5, recover = 20 },
	beam = { back = 0.03, angle = 0.6, roll = 1.5, recover = 20 },
	launcher = { back = 0.35, angle = 12, roll = 2, recover = 7 },
}

return Freeze.deep({
	styles = styles,
	weapons = weapons,
	recoil = recoil,

	-- Haut du torse d'un avatar R15 standard (échelle 1 des positions ci-dessus).
	referenceTorsoHeight = 1.6,

	pitch = {
		max = 70, -- visée en haut / en bas au-delà : bloquée (degrés)
		waistShare = 0.35, -- part de la visée prise par le buste qui se penche
		headShare = 0.8, -- la tête suit le reste de la visée
	},

	-- Couché (torse à l'horizontale) : arme ramenée vers le centre et les épaules
	-- (repère visée, avant le quart de tour), tête relevée pour regarder devant.
	prone = {
		shift = Vector3.new(-0.25, 0, 0.5),
		head = 70, -- degrés
	},

	-- Coup de mêlée : durée = `swingScale` / coups par seconde, bornée.
	swingScale = 0.75,
	swingMin = 0.3,
	swingMax = 0.65,
	swingTiming = { windup = 0.25, strike = 0.5 },

	-- Transitions (par seconde) entre prises : sprint, garde, visée des autres joueurs.
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
