--!strict
--[[
	EconomyService : actions du Terminus (sections 7.3, 8.7, 14.2 à 14.4).

	Coffre et équipement, écran de tri, Marchand, Armurier, Assureur, caisse
	gratuite. Chaque action :
	- est refusée pendant une partie (le joueur doit être au Terminus) et
	  en file d'attente (équipement verrouillé) ;
	- est atomique (DataService.update : tout ou rien) ;
	- exige une confirmation explicite au-delà de 1 000 crédits (Marchand) ;
	- est inscrite au journal des transactions (enquêtes).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Guard = require(Shared.Util.Guard)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local Pricing = require(Shared.Economy.Pricing)
local Types = require(Shared.Types)

local EconomyRules = require(script.Parent.Parent.Economy.EconomyRules)
local TransactionLog = require(script.Parent.Parent.Economy.TransactionLog)
local ItemFactory = require(script.Parent.Parent.Inventory.ItemFactory)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local CharacterService = require(script.Parent.CharacterService)
local DataService = require(script.Parent.DataService)
local MatchService = require(script.Parent.MatchService)
local QueueService = require(script.Parent.QueueService)
local RangeService = require(script.Parent.RangeService)

local EconomyService = {}

local random = Random.new()
local SLOTS = { "ranged", "melee", "gadget1", "gadget2", "helmet", "vest", "backpack" }
local INSURANCE_CHOICES = { "none" }
for tierId in Config.Economy.insurance.tiers :: { [string]: any } do
	table.insert(INSURANCE_CHOICES, tierId)
end

-- Le joueur est-il disponible pour une action de Terminus (pas en partie) ?
local function available(player: Player): boolean
	local participant = MatchService.participant(player)
	if participant and not participant.finished then
		ServerNet.notify(player, "economy.failure.in_match")
		return false
	end
	-- En file d'attente : SE et équipement verrouillés (16.3).
	if QueueService.isLocked(player) then
		ServerNet.notify(player, "economy.failure.queued")
		return false
	end
	return true
end

--[[
	Applique une règle économique dans une transaction. `rule` reçoit la copie
	de travail du profil et retourne (succès, raison, détail).
]]
local function transact(
	player: Player,
	kind: string,
	rule: (profile: Types.Profile) -> (boolean, string?, any?)
): (boolean, any?)
	if not available(player) then
		return false, nil
	end
	local success, reason, detail = false, nil :: string?, nil :: any?
	DataService.update(player, function(profile)
		success, reason, detail = rule(profile)
		-- Refus : la copie de travail est abandonnée (rien n'est modifié).
		return success
	end)
	if not success then
		ServerNet.notify(player, "economy.failure." .. tostring(reason or "unknown"))
		return false, nil
	end
	TransactionLog.record(player, kind, detail)
	-- L'équipement porté au Terminus suit le profil tout de suite (arme en main…).
	-- Une séance au stand de tir (arme prêtée) est d'abord close proprement.
	if RangeService.isInSession(player) then
		RangeService.stop(player)
	end
	CharacterService.refreshLoadout(player)
	return true, detail
end

function EconomyService.init()
	-- Coffre / équipement / sac préparé.
	ServerNet.onEvent(
		"VaultAction",
		Guard.tuple(
			Guard.enum({ "equip", "unequip", "toBag", "fromBag", "discard", "keep", "keepAll" }),
			Guard.optional(Guard.uid()),
			Guard.optional(Guard.enum(SLOTS))
		),
		function(player, action: string, uid: string?, slot: Types.SlotName?)
			transact(player, "vault." .. action, function(profile)
				if action == "equip" and uid and slot then
					return EconomyRules.equipFromVault(profile, uid, slot)
				elseif action == "unequip" and slot then
					return EconomyRules.unequipToVault(profile, slot)
				elseif action == "toBag" and uid then
					return EconomyRules.vaultToBag(profile, uid)
				elseif action == "fromBag" and uid then
					return EconomyRules.bagToVault(profile, uid)
				elseif action == "discard" and uid then
					local ok, reason = EconomyRules.discard(profile, uid)
					return ok, reason, { uid = uid }
				elseif action == "keep" and uid then
					return EconomyRules.keepPending(profile, uid)
				elseif action == "keepAll" then
					local ok, reason, kept = EconomyRules.keepAllPending(profile)
					return ok, reason, { kept = kept }
				end
				return false, "invalid"
			end)
		end
	)

	-- Marchand : vente (sélection multiple).
	ServerNet.onEvent(
		"MerchantSell",
		Guard.tuple(Guard.array(Guard.uid(), 60), Guard.boolean()),
		function(player, uids: { string }, confirmed: boolean)
			if #uids == 0 then
				return
			end
			local ok, total = transact(player, "merchant.sell", function(profile)
				local preview = 0
				for _, uid in uids do
					for _, list in { profile.vault, profile.bag, profile.pendingLoot } do
						for _, item in list do
							if item.uid == uid then
								preview += Pricing.sellPrice(item)
							end
						end
					end
				end
				if preview > Config.Economy.merchant.confirmAbove and not confirmed then
					return false, "needs_confirm"
				end
				local success, reason, gained = EconomyRules.sell(profile, uids)
				return success, reason, { credits = gained, count = #uids }
			end)
			if ok and total then
				ServerNet.notify(player, "economy.sold", { credits = total.credits })
			end
		end
	)

	-- Marchand : achat.
	ServerNet.onEvent(
		"MerchantBuy",
		Guard.tuple(
			Guard.keyOf(ItemCatalog.all()),
			Guard.optional(Guard.integer(1, 5)),
			Guard.optional(Guard.integer(1, 30)),
			Guard.boolean()
		),
		function(player, itemId: string, condition: number?, quantity: number?, confirmed: boolean)
			local ok = transact(player, "merchant.buy", function(profile)
				local info = ItemCatalog.get(itemId)
				local price =
					Pricing.merchantPrice(itemId, if info and info.hasCondition then condition else nil, quantity)
				if price and price > Config.Economy.merchant.confirmAbove and not confirmed then
					return false, "needs_confirm"
				end
				local success, reason, item = EconomyRules.buy(profile, itemId, condition, quantity, ItemFactory.create)
				return success, reason, if item then { itemId = itemId, uid = item.uid, price = price } else nil
			end)
			if ok then
				ServerNet.notify(player, "economy.bought", { item = itemId })
			end
		end
	)

	-- Armurier : réparation d'un cran.
	ServerNet.onEvent("Repair", Guard.tuple(Guard.uid()), function(player, uid: string)
		local ok, detail = transact(player, "armorer.repair", function(profile)
			local success, reason, cost = EconomyRules.repair(profile, uid)
			return success, reason, { uid = uid, cost = cost }
		end)
		if ok and detail then
			ServerNet.notify(player, "economy.repaired", { cost = detail.cost })
		end
	end)

	-- Assureur : niveau choisi pour la prochaine partie (payé au départ).
	ServerNet.onEvent("SetInsurance", Guard.tuple(Guard.enum(INSURANCE_CHOICES)), function(player, tier: string)
		transact(player, "insurance.select", function(profile)
			profile.insuranceTier = if tier == "none" then nil else tier
			return true, nil, { tier = tier }
		end)
	end)

	-- Caisse gratuite.
	ServerNet.onEvent("OpenFreeCrate", Guard.tuple(), function(player)
		local ok, reward = transact(player, "freecrate.open", function(profile)
			return EconomyRules.openFreeCrate(profile, os.time(), random, ItemFactory.create)
		end)
		-- Refus (pas de caisse, file d'attente, partie) : réponse explicite, pour que
		-- la fenêtre d'ouverture se referme (la notification donne la raison).
		ServerNet.fire("FreeCrateResult", player, if ok and reward then reward else { kind = "refused" })
	end)
end

function EconomyService.start()
	-- Caisse gratuite : accumulation (même hors ligne), vérifiée à l'arrivée puis régulièrement.
	local function accrue(player: Player)
		local profile = DataService.getProfile(player)
		if profile == nil then
			return
		end
		local before = profile.freeCrate.stored
		local copy = { freeCrate = table.clone(profile.freeCrate) }
		EconomyRules.accrueFreeCrate(copy :: any, os.time())
		if copy.freeCrate.stored ~= before then
			DataService.update(player, function(current)
				EconomyRules.accrueFreeCrate(current, os.time())
			end)
		end
	end
	DataService.ProfileLoaded:Connect(function(player)
		accrue(player)
	end)
	task.spawn(function()
		while true do
			task.wait(Config.Economy.freeCrate.checkInterval)
			for _, player in Players:GetPlayers() do
				accrue(player)
			end
		end
	end)
end

return EconomyService
