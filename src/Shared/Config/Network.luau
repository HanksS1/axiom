--!strict
--[[
	Limites de fréquence des remotes (section 19.4).
	`rate` = requêtes par seconde en régime continu, `burst` = pic toléré.
	Toute remote doit avoir une entrée ici (vérifié au démarrage du serveur).
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

export type Limit = { rate: number, burst: number }

return Freeze.deep({
	-- Au-delà de ce nombre de requêtes rejetées par minute, le joueur est
	-- expulsé (comportement de client modifié).
	kickAfterRejectionsPerMinute = 120,

	limits = {
		-- Profil / paramètres
		RequestProfile = { rate = 0.5, burst = 3 },
		UpdateSetting = { rate = 4, burst = 10 },
		GuideSeen = { rate = 1, burst = 3 },
		-- Outils de développement (Studio uniquement)
		DevCommand = { rate = 2, burst = 5 },
		-- Combat
		FireWeapon = { rate = 16, burst = 20 }, -- cadence max : 14 tirs/s
		ReloadWeapon = { rate = 2, burst = 4 },
		SwitchWeapon = { rate = 4, burst = 6 },
		MeleeAttack = { rate = 4, burst = 6 },
		SetParry = { rate = 6, burst = 10 },
		SetMovement = { rate = 10, burst = 15 },
		SetAim = { rate = 8, burst = 12 }, -- au plus ~7/s (Config.WeaponPoses.aimSendInterval)
		-- Loot et inventaire
		TakeItem = { rate = 8, burst = 12 },
		TakeAll = { rate = 1, burst = 3 },
		CloseContainer = { rate = 4, burst = 8 },
		EquipItem = { rate = 4, burst = 8 },
		UnequipItem = { rate = 4, burst = 8 },
		DropItem = { rate = 4, burst = 8 },
		UseConsumable = { rate = 2, burst = 4 },
		-- Partie
		Ping = { rate = 2, burst = 4 },
		UseGadget = { rate = 2, burst = 4 },
		-- Terminus et économie
		VaultAction = { rate = 6, burst = 12 },
		MerchantSell = { rate = 2, burst = 4 },
		MerchantBuy = { rate = 3, burst = 6 },
		Repair = { rate = 2, burst = 4 },
		SetInsurance = { rate = 2, burst = 4 },
		OpenFreeCrate = { rate = 1, burst = 2 },
		-- Holo-Bazar
		BazaarBuy = { rate = 1, burst = 3 },
		CosmeticCrateOpen = { rate = 0.5, burst = 2 },
		EquipCosmetic = { rate = 2, burst = 6 },
		AdminGiftCrates = { rate = 1, burst = 4 },
		AdminGiftCredits = { rate = 1, burst = 4 },
		-- Matchmaking
		SetPlatform = { rate = 1, burst = 4 },
		PartyInvite = { rate = 0.5, burst = 3 },
		PartyRespond = { rate = 1, burst = 3 },
		PartyLeave = { rate = 1, burst = 2 },
		QueueJoin = { rate = 0.5, burst = 3 },
		QueueLeave = { rate = 1, burst = 3 },
		QueueMapCounts = { rate = 1, burst = 3 },
		ReturnToHub = { rate = 0.5, burst = 2 },
		-- Progression (P10)
		LeaderboardRequest = { rate = 0.5, burst = 4 },
		RangeAction = { rate = 1, burst = 3 },
		TutorialAction = { rate = 0.2, burst = 2 },
	} :: { [string]: Limit },
})
