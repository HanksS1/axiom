--!strict
-- English strings. Every key must also exist in fr.luau (checked by tests).
-- Parameters: {name} is replaced by the matching value.

return {
	-- General
	["game.title"] = "AXIOM WAR: EXTRACTION",
	["common.credits"] = "Credits",
	["common.noyaux"] = "Cores",
	["common.level"] = "Level {level}",
	["common.up"] = "{used} / {capacity} SU",
	["common.loading"] = "Loading…",
	["common.confirm"] = "Confirm",
	["common.cancel"] = "Cancel",

	-- Profile errors (kick messages)
	["kick.profileLoadFailed"] = "Unable to load your profile. Please try again in a moment.",
	["kick.profileSessionLost"] = "Your profile was opened on another server. Please reconnect.",
	["kick.suspiciousActivity"] = "Abnormal activity detected. You have been disconnected.",
	["kick.serverShutdown"] = "The server is restarting. Your data has been saved.",

	-- Conditions (section 7.1)
	["condition.wrecked"] = "Wrecked",
	["condition.damaged"] = "Damaged",
	["condition.worn"] = "Worn",
	["condition.good"] = "Good",
	["condition.pristine"] = "Pristine",

	-- Modes
	["mode.easy"] = "Easy",
	["mode.medium"] = "Medium",
	["mode.hard"] = "Hard",
	["mode.format.solo"] = "Solo",
	["mode.format.duo"] = "Duo",
	["mode.refused.score_too_low"] = "Gear Score too low: {score} / {limit} min",
	["mode.refused.score_too_high"] = "Gear Score too high: {score} / {limit} max",
	["mode.refused.level_too_low"] = "Level {limit} required",

	-- Ranged weapons
	["item.scrap_laser_pistol"] = "Scrap Laser Pistol",
	["item.vigil_pistol"] = "Vigil Pistol",
	["item.crackler"] = "The Crackler",
	["item.sentinel_rifle"] = "Repurposed Sentinel Rifle",
	["item.hullbreaker"] = "Hullbreaker",
	["item.mag_nailer"] = "Mag-Nailer",
	["item.needle"] = "The Needle",
	["item.bastion_minigun"] = "Ripped Bastion Minigun",
	["item.xray_cannon"] = "Modified X-Ray Cannon",
	["item.short_circuit"] = "Short-Circuit",
	-- Melee weapons
	["item.shock_crowbar"] = "Shock Crowbar",
	["item.laser_saber"] = "Scrap Laser Saber",
	["item.hydraulic_hammer"] = "Hydraulic Hammer",
	["item.pulse_gauntlet"] = "Pulse Gauntlet",
	["item.vibro_blade"] = "Executor Vibro-Blade",
	-- Armor and backpacks
	["item.helmet"] = "Helmet",
	["item.vest"] = "Vest",
	["item.backpack_small"] = "Small Backpack",
	["item.backpack_medium"] = "Medium Backpack",
	["item.backpack_large"] = "Large Backpack",
	-- Gadgets
	["item.jump_boots"] = "Jump Boots",
	["item.grappling_hook"] = "Grappling Hook",
	["item.recon_drone"] = "Recon Drone",
	["item.deployable_wall"] = "Deployable Wall",
	["item.smoke_deployer"] = "Smoke Deployer",
	-- Consumables
	["item.nanite_injector"] = "Nanite Injector",
	["item.shield_battery"] = "Shield Battery",
	["item.overdrive"] = "Overdrive",
	["item.exo_harness"] = "Exo-Harness",
	-- Cells
	["item.cell_light"] = "Light Cell",
	["item.cell_standard"] = "Standard Cell",
	["item.cell_precision"] = "Precision Cell",
	["item.cell_heavy"] = "Heavy Cell",
	-- Misc
	["item.calibration_module"] = "Calibration Module",
	["item.tag.kit"] = "Kit",

	-- Robots
	["robot.fly"] = "Fly",
	["robot.stalker"] = "Stalker",
	["robot.sentinel"] = "Sentinel",
	["robot.bastion"] = "Bastion",
	["robot.executor"] = "Executor",
	["robot.warden"] = "Warden",

	-- Ranks
	["rank.scrap"] = "Scrap",
	["rank.copper"] = "Copper",
	["rank.steel"] = "Steel",
	["rank.titanium"] = "Titanium",
	["rank.plasma"] = "Plasma",
	["rank.legend"] = "AXIOM Legend",

	-- Maps
	["map.neo_lumen"] = "Neo-Lumen",
	["map.forge7"] = "Forge-7",
	["map.burnt_lands"] = "The Burnt Lands",
	["map.core_zero"] = "Core Zero",

	-- Developer tools (Studio)
	["dev.panelTitle"] = "PROFILE (DEV)",
	["dev.profileState"] = "Level {level} · {xp} XP · {credits} credits · {noyaux} Cores",
	["dev.vaultState"] = "Vault: {used} / {capacity} SU · {count} items",
	["dev.loadoutState"] = "Gear Score: {score}",
	["dev.addCredits"] = "+100 credits",
	["dev.addXp"] = "+500 XP",
	["dev.giveKit"] = "Base kit",
	["dev.giveRandom"] = "Random item",
	["dev.clearVault"] = "Empty vault",
	["dev.saveNow"] = "Save now",
	["dev.toggleLanguage"] = "Language FR / EN",

	-- HUD and touch controls
	["hud.reloading"] = "RELOADING…",
	["hud.overheated"] = "OVERHEATED",
	["hud.noCells"] = "OUT OF CELLS",
	["hud.parry"] = "GUARD",
	["hud.stunned"] = "STUNNED",
	["hud.dead"] = "DISINTEGRATED",
	["hud.respawning"] = "Respawning…",
	["hud.stance.crouch"] = "CROUCHED",
	["hud.stance.prone"] = "PRONE",
	["hud.parryPerfect"] = "PERFECT PARRY",
	["hud.parryBroken"] = "GUARD BROKEN",
	["hud.parried"] = "PARRIED!",
	["touch.fire"] = "FIRE",
	["touch.aim"] = "AIM",
	["touch.parry"] = "PARRY",
	["touch.reload"] = "RELOAD",
	["touch.switch"] = "SWAP",
	["touch.crouch"] = "CROUCH",
	["touch.sprint"] = "SPRINT",
	["dev.equipRifle"] = "Sentinel Rifle",
	["dev.equipPistol"] = "Scrap Pistol",
	["dev.equipArmor"] = "Vest + helmet",
	["dev.respawn"] = "Respawn",
	["dev.mouseHint"] = "[M] free / lock the mouse",
}
