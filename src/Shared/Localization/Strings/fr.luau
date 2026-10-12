--!strict
-- Textes en français. Chaque clé doit exister aussi dans en.luau (vérifié par les tests).
-- Paramètres : {nom} est remplacé par la valeur correspondante.

return {
	-- Général
	["game.title"] = "AXIOM WAR : EXTRACTION",
	["common.credits"] = "Crédits",
	["common.noyaux"] = "Noyaux",
	["common.level"] = "Niveau {level}",
	["common.up"] = "{used} / {capacity} UP",
	["common.loading"] = "Chargement…",
	["common.confirm"] = "Confirmer",
	["common.cancel"] = "Annuler",

	-- Erreurs de profil (messages d'expulsion)
	["kick.profileLoadFailed"] = "Impossible de charger votre profil. Réessayez dans quelques instants.",
	["kick.profileSessionLost"] = "Votre profil a été ouvert sur un autre serveur. Reconnectez-vous.",
	["kick.suspiciousActivity"] = "Activité anormale détectée. Vous avez été déconnecté.",
	["kick.serverShutdown"] = "Le serveur redémarre. Vos données ont été sauvegardées.",

	-- États (section 7.1)
	["condition.wrecked"] = "Très abîmé",
	["condition.damaged"] = "Abîmé",
	["condition.worn"] = "Dégradé",
	["condition.good"] = "Bon état",
	["condition.pristine"] = "Neuf",

	-- Modes
	["mode.easy"] = "Facile",
	["mode.medium"] = "Moyen",
	["mode.hard"] = "Difficile",
	["mode.format.solo"] = "Solo",
	["mode.format.duo"] = "Duo",
	["mode.refused.score_too_low"] = "SE trop faible : {score} / {limit} min",
	["mode.refused.score_too_high"] = "SE trop élevé : {score} / {limit} max",
	["mode.refused.level_too_low"] = "Niveau {limit} requis",

	-- Armes à distance
	["item.scrap_laser_pistol"] = "Pistolet laser fait maison",
	["item.vigil_pistol"] = "Pistolet « Vigil »",
	["item.crackler"] = "La Grésilleuse",
	["item.sentinel_rifle"] = "Fusil de Sentinelle reconverti",
	["item.hullbreaker"] = "Brise-Carcasse",
	["item.mag_nailer"] = "Lance-clous magnétique",
	["item.needle"] = "L'Aiguille",
	["item.bastion_minigun"] = "Mitrailleuse de Bastion arrachée",
	["item.xray_cannon"] = "Canon à rayons X modifié",
	["item.short_circuit"] = "Court-Circuit",
	-- Armes de mêlée
	["item.shock_crowbar"] = "Barre à mine électrifiée",
	["item.laser_saber"] = "Sabre laser de fortune",
	["item.hydraulic_hammer"] = "Marteau hydraulique",
	["item.pulse_gauntlet"] = "Gantelet à impulsion",
	["item.vibro_blade"] = "Lame vibrante d'Exécuteur",
	-- Protections et sacs
	["item.helmet"] = "Casque",
	["item.vest"] = "Gilet",
	["item.backpack_small"] = "Petit sac",
	["item.backpack_medium"] = "Sac moyen",
	["item.backpack_large"] = "Grand sac",
	-- Gadgets
	["item.jump_boots"] = "Bottes de saut",
	["item.grappling_hook"] = "Grappin",
	["item.recon_drone"] = "Drone de reconnaissance",
	["item.deployable_wall"] = "Mur déployable",
	["item.smoke_deployer"] = "Fumigène déployable",
	-- Consommables
	["item.nanite_injector"] = "Injecteur de nanites",
	["item.shield_battery"] = "Batterie de bouclier",
	["item.overdrive"] = "Surcharge",
	["item.exo_harness"] = "Exo-harnais",
	-- Cellules
	["item.cell_light"] = "Cellule légère",
	["item.cell_standard"] = "Cellule standard",
	["item.cell_precision"] = "Cellule de précision",
	["item.cell_heavy"] = "Cellule lourde",
	-- Divers
	["item.calibration_module"] = "Module de calibration",
	["item.tag.kit"] = "Kit",

	-- Robots
	["robot.fly"] = "Mouche",
	["robot.stalker"] = "Traqueur",
	["robot.sentinel"] = "Sentinelle",
	["robot.bastion"] = "Bastion",
	["robot.executor"] = "Exécuteur",
	["robot.warden"] = "Gardien",

	-- Rangs
	["rank.scrap"] = "Ferraille",
	["rank.copper"] = "Cuivre",
	["rank.steel"] = "Acier",
	["rank.titanium"] = "Titane",
	["rank.plasma"] = "Plasma",
	["rank.legend"] = "Légende d'AXIOM",

	-- Cartes
	["map.neo_lumen"] = "Néo-Lumen",
	["map.forge7"] = "Forge-7",
	["map.burnt_lands"] = "Les Terres Brûlées",
	["map.core_zero"] = "Noyau Zéro",

	-- Outils de développement (Studio)
	["dev.panelTitle"] = "PROFIL (DEV)",
	["dev.profileState"] = "Niveau {level} · {xp} XP · {credits} crédits · {noyaux} Noyaux",
	["dev.vaultState"] = "Coffre : {used} / {capacity} UP · {count} objets",
	["dev.loadoutState"] = "SE : {score}",
	["dev.addCredits"] = "+100 crédits",
	["dev.addXp"] = "+500 XP",
	["dev.giveKit"] = "Kit de base",
	["dev.giveRandom"] = "Objet aléatoire",
	["dev.clearVault"] = "Vider le coffre",
	["dev.saveNow"] = "Sauvegarder",
	["dev.toggleLanguage"] = "Langue FR / EN",
}
