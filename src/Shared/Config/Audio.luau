--!strict
--[[
	Audio (section 18) : musique dynamique à 4 couches, voix d'AXIOM (FR/EN),
	sons d'armes et d'alarmes spatialisés.

	⚠ Les identifiants de sons sont à renseigner (« rbxassetid://… ») avec
	des sons importés dans l'expérience ou libres de droits de la
	bibliothèque Roblox. Un identifiant vide = son désactivé (aucune erreur).
	Voix d'AXIOM : une piste par langue (synthétique, froide).
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

return Freeze.deep({
	music = {
		-- Une piste en boucle par moment ; fondu enchaîné entre les couches.
		layers = {
			hub = { id = "", volume = 0.45 }, -- synthwave calme et nostalgique
			exploration = { id = "", volume = 0.4 }, -- industriel sombre, sons métalliques
			combat = { id = "", volume = 0.55 }, -- électro sombre rythmée
			alert = { id = "", volume = 0.6 }, -- montée intense, sirène (12:00 → Purge)
		},
		fadeTime = 2.5, -- secondes
		combatHold = 8, -- la musique de combat redescend après 8 s sans dégâts
		-- Pendant l'alerte, le tempo accélère jusqu'à la Purge.
		alertPitchStart = 1,
		alertPitchEnd = 1.12,
	},

	-- Voix d'AXIOM par annonce (clé envoyée par le serveur) et par langue.
	voice = {
		["axiom.start"] = { fr = "", en = "" },
		["axiom.alert"] = { fr = "", en = "" },
		["axiom.purge"] = { fr = "", en = "" },
		["map.neo_lumen.rumble"] = { fr = "", en = "" },
		["map.forge_7.production"] = { fr = "", en = "" },
		["map.forge_7.panel_destroyed"] = { fr = "", en = "" },
		["map.noyau_zero.blackout"] = { fr = "", en = "" },
	},

	-- Tir de chaque arme (reconnaissable : laser sec, arc électrique, pompe plasma…).
	weapons = {
		scrap_laser_pistol = { fire = "", volume = 0.8 },
		vigil_pistol = { fire = "", volume = 0.8 },
		crackler = { fire = "", volume = 0.8 },
		sentinel_rifle = { fire = "", volume = 0.8 },
		hullbreaker = { fire = "", volume = 0.8 },
		mag_nailer = { fire = "", volume = 0.8 },
		needle = { fire = "", volume = 0.8 },
		bastion_minigun = { fire = "", volume = 0.8 },
		xray_cannon = { fire = "", volume = 0.8 },
		short_circuit = { fire = "", volume = 0.8 },
	},

	sfx = {
		lootAlarm = { id = "", volume = 0.9 },
		hitMarker = { id = "", volume = 0.35 },
		headshot = { id = "", volume = 0.45 },
		damageTaken = { id = "", volume = 0.5 },
		parry = { id = "", volume = 0.6 },
		extracted = { id = "", volume = 0.7 },
	},

	-- Sons spatialisés (informations tactiques) : portée d'écoute.
	spatial = {
		rollOffMin = 12,
		rollOffMax = 260,
		pool = 24, -- sources réutilisées (aucune création par tir)
	},
})
