--!strict
--[[
	EconomyRules : opérations économiques sur un profil (sections 7.3, 8.7,
	14.2 à 14.4). Fonctions PURES qui modifient le profil passé en
	paramètre (toujours une copie de travail fournie par DataService.update)
	et retournent (succès, raison, résultat).

	Règles d'intégrité :
	- le coffre ne dépasse JAMAIS sa capacité ;
	- le sac préparé ne dépasse jamais la capacité du sac équipé ;
	- les crédits ne deviennent jamais négatifs ;
	- tout objet créé reçoit un nouvel uid (fabrique injectée).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local ItemRules = require(Shared.Items.ItemRules)
local Pricing = require(Shared.Economy.Pricing)
local Types = require(Shared.Types)

local CrateGifts = require(script.Parent.CrateGifts)

type Profile = Types.Profile
type ItemInstance = Types.ItemInstance

export type Create = (itemId: string, options: any?) -> ItemInstance
export type Rng = {
	NextNumber: (self: any, min: number?, max: number?) -> number,
	NextInteger: (self: any, min: number, max: number) -> number,
}

local EconomyRules = {}

local function vaultCapacity(profile: Profile): number
	return ItemRules.vaultCapacity(profile.hasVaultExtension)
end

function EconomyRules.vaultUsed(profile: Profile): number
	return ItemRules.totalUp(profile.vault)
end

function EconomyRules.vaultFree(profile: Profile): number
	return vaultCapacity(profile) - EconomyRules.vaultUsed(profile)
end

local function bagCapacity(profile: Profile): number
	return ItemRules.bagCapacity(profile.loadout.backpack)
end

local function indexOf(list: { ItemInstance }, uid: string): number?
	for index, item in list do
		if item.uid == uid then
			return index
		end
	end
	return nil
end

local function addCredits(profile: Profile, amount: number)
	profile.credits = math.clamp(profile.credits + math.floor(amount), 0, Config.Economy.maxCredits)
end

-- Équipement : coffre ↔ emplacements ↔ sac préparé -------------------------

-- Équipe un objet du coffre ; l'objet remplacé retourne au coffre.
function EconomyRules.equipFromVault(profile: Profile, uid: string, slot: Types.SlotName): (boolean, string?)
	local index = indexOf(profile.vault, uid)
	if index == nil then
		return false, "not_found"
	end
	local item = profile.vault[index]
	local info = ItemCatalog.get(item.itemId)
	if info == nil or ItemCatalog.slotCategories[slot] ~= info.category then
		return false, "wrong_slot"
	end
	local previous = (profile.loadout :: any)[slot] :: ItemInstance?
	local freeAfter = EconomyRules.vaultFree(profile)
		+ ItemRules.up(item)
		- (if previous then ItemRules.up(previous) else 0)
	if freeAfter < 0 then
		return false, "vault_full"
	end
	if slot == "backpack" and ItemRules.totalUp(profile.bag) > ItemRules.bagCapacity(item) then
		return false, "too_small"
	end
	table.remove(profile.vault, index);
	(profile.loadout :: any)[slot] = item
	if previous then
		table.insert(profile.vault, previous)
	end
	return true, nil
end

-- Range un objet équipé dans le coffre.
function EconomyRules.unequipToVault(profile: Profile, slot: Types.SlotName): (boolean, string?)
	local item = (profile.loadout :: any)[slot] :: ItemInstance?
	if item == nil then
		return false, "slot_empty"
	end
	if EconomyRules.vaultFree(profile) < ItemRules.up(item) then
		return false, "vault_full"
	end
	if slot == "backpack" and ItemRules.totalUp(profile.bag) > ItemRules.bagCapacity(nil) then
		return false, "too_small"
	end
	(profile.loadout :: any)[slot] = nil
	table.insert(profile.vault, item)
	return true, nil
end

-- Coffre → sac préparé (consommables, cellules, objets de rechange).
function EconomyRules.vaultToBag(profile: Profile, uid: string): (boolean, string?)
	local index = indexOf(profile.vault, uid)
	if index == nil then
		return false, "not_found"
	end
	local item = profile.vault[index]
	if ItemRules.totalUp(profile.bag) + ItemRules.up(item) > bagCapacity(profile) then
		return false, "bag_full"
	end
	table.remove(profile.vault, index)
	table.insert(profile.bag, item)
	return true, nil
end

-- Sac préparé → coffre.
function EconomyRules.bagToVault(profile: Profile, uid: string): (boolean, string?)
	local index = indexOf(profile.bag, uid)
	if index == nil then
		return false, "not_found"
	end
	local item = profile.bag[index]
	if EconomyRules.vaultFree(profile) < ItemRules.up(item) then
		return false, "vault_full"
	end
	table.remove(profile.bag, index)
	table.insert(profile.vault, item)
	return true, nil
end

-- Jette définitivement un objet (coffre, sac préparé ou loot à trier).
function EconomyRules.discard(profile: Profile, uid: string): (boolean, string?)
	for _, list in { profile.vault, profile.bag, profile.pendingLoot } do
		local index = indexOf(list, uid)
		if index then
			table.remove(list, index)
			return true, nil
		end
	end
	return false, "not_found"
end

-- Écran de tri -----------------------------------------------------------

-- Garder un objet extrait : il rejoint le coffre (s'il y a la place).
function EconomyRules.keepPending(profile: Profile, uid: string): (boolean, string?)
	local index = indexOf(profile.pendingLoot, uid)
	if index == nil then
		return false, "not_found"
	end
	local item = profile.pendingLoot[index]
	if EconomyRules.vaultFree(profile) < ItemRules.up(item) then
		return false, "vault_full"
	end
	table.remove(profile.pendingLoot, index)
	table.insert(profile.vault, item)
	return true, nil
end

-- Garder tout ce qui tient dans le coffre (le plus précieux d'abord). Retourne le nombre gardé.
function EconomyRules.keepAllPending(profile: Profile): (boolean, string?, number)
	local sorted = table.clone(profile.pendingLoot)
	table.sort(sorted, function(a, b)
		return ItemRules.value(a) > ItemRules.value(b)
	end)
	local kept = 0
	for _, item in sorted do
		if EconomyRules.vaultFree(profile) >= ItemRules.up(item) then
			local index = indexOf(profile.pendingLoot, item.uid)
			if index then
				table.remove(profile.pendingLoot, index)
				table.insert(profile.vault, item)
				kept += 1
			end
		end
	end
	if kept == 0 then
		return false, "vault_full", 0
	end
	return true, nil, kept
end

-- Marchand -------------------------------------------------------------------

--[[
	Vend des objets (coffre, sac préparé ou loot à trier). Les objets du kit
	et temporaires ne se vendent pas. Retourne le total encaissé.
]]
function EconomyRules.sell(profile: Profile, uids: { string }): (boolean, string?, number)
	local total = 0
	local plan: { { list: { ItemInstance }, item: ItemInstance } } = {}
	local seen: { [string]: boolean } = {}
	for _, uid in uids do
		if seen[uid] then
			return false, "duplicate", 0
		end
		seen[uid] = true
		local found = false
		for _, list in { profile.vault, profile.bag, profile.pendingLoot } do
			local index = indexOf(list, uid)
			if index then
				local item = list[index]
				if not ItemRules.isSellable(item) then
					return false, "not_sellable", 0
				end
				table.insert(plan, { list = list, item = item })
				total += Pricing.sellPrice(item)
				found = true
				break
			end
		end
		if not found then
			return false, "not_found", 0
		end
	end
	for _, entry in plan do
		local index = table.find(entry.list, entry.item)
		if index then
			table.remove(entry.list, index)
		end
	end
	addCredits(profile, total)
	return true, nil, total
end

--[[
	Achète un objet chez le Marchand ; il rejoint le coffre.
	Équipement : uniquement aux états vendus (Dégradé, Bon état).
]]
function EconomyRules.buy(
	profile: Profile,
	itemId: string,
	condition: number?,
	quantity: number?,
	create: Create
): (boolean, string?, ItemInstance?)
	local info = ItemCatalog.get(itemId)
	if info == nil then
		return false, "unknown", nil
	end
	local price = Pricing.merchantPrice(itemId, if info.hasCondition then condition else nil, quantity)
	if price == nil then
		return false, "not_for_sale", nil
	end
	if profile.credits < price then
		return false, "not_enough_credits", nil
	end
	local stackSize = info.stackSize
	if stackSize then
		-- Objet empilable : on complète d'abord les piles entamées du coffre (la
		-- place se compte par pile : acheter à l'unité ne doit pas en coûter plus).
		local amount = math.clamp(quantity or stackSize, 1, stackSize)
		local room = 0
		for _, owned in profile.vault do
			if owned.itemId == itemId then
				room += math.max(0, stackSize - (owned.stack or 1))
			end
		end
		if amount > room and EconomyRules.vaultFree(profile) < info.up then
			return false, "vault_full", nil
		end
		profile.credits -= price
		local remaining = amount
		local last: ItemInstance? = nil
		for _, owned in profile.vault do
			if remaining <= 0 then
				break
			end
			if owned.itemId == itemId and (owned.stack or 1) < stackSize then
				local added = math.min(remaining, stackSize - (owned.stack or 1))
				owned.stack = (owned.stack or 1) + added
				remaining -= added
				last = owned
			end
		end
		if remaining > 0 then
			local item = create(itemId, { stack = remaining })
			table.insert(profile.vault, item)
			last = item
		end
		return true, nil, last
	end
	if EconomyRules.vaultFree(profile) < info.up then
		return false, "vault_full", nil
	end
	local item = create(itemId, {
		condition = if info.hasCondition then condition else nil,
	})
	profile.credits -= price
	table.insert(profile.vault, item)
	return true, nil, item
end

-- Armurier -------------------------------------------------------------------

--[[
	Répare un objet d'un cran (coffre ou emplacement équipé). Bon état → Neuf
	consomme un Module de calibration du coffre. Retourne le coût.
]]
function EconomyRules.repair(profile: Profile, uid: string): (boolean, string?, number)
	local item: ItemInstance? = nil
	local vaultIndex = indexOf(profile.vault, uid)
	if vaultIndex then
		item = profile.vault[vaultIndex]
	else
		for _, slot in ItemCatalog.slotNames do
			local equipped = (profile.loadout :: any)[slot] :: ItemInstance?
			if equipped and equipped.uid == uid then
				item = equipped
			end
		end
	end
	if item == nil then
		return false, "not_found", 0
	end
	local cost, needsCalibration = Pricing.repairCost(item)
	if cost == nil then
		return false, "not_repairable", 0
	end
	if profile.credits < cost then
		return false, "not_enough_credits", 0
	end
	if needsCalibration then
		local calibrationId = Config.Economy.repair.calibrationItemId
		local moduleIndex: number? = nil
		for index, other in profile.vault do
			if other.itemId == calibrationId then
				moduleIndex = index
				break
			end
		end
		if moduleIndex == nil then
			return false, "needs_calibration", 0
		end
		table.remove(profile.vault, moduleIndex)
	end
	profile.credits -= cost
	item.condition = (item.condition :: number) + 1
	return true, nil, cost
end

-- Assurance -----------------------------------------------------------------

-- Objets couverts par l'assurance : équipement porté (hors consommables, cellules, kit, temporaires).
function EconomyRules.insurable(item: ItemInstance): boolean
	local info = ItemCatalog.get(item.itemId)
	return info ~= nil and info.hasCondition and not item.isKit and item.tempGamesLeft == nil
end

-- Valeur assurée d'un équipement de départ (base du prix de l'assurance).
function EconomyRules.insuredValue(loadout: Types.Loadout, bag: { ItemInstance }): number
	local total = 0
	for _, slot in ItemCatalog.slotNames do
		local item = (loadout :: any)[slot] :: ItemInstance?
		if item and EconomyRules.insurable(item) then
			total += ItemRules.value(item)
		end
	end
	for _, item in bag do
		if EconomyRules.insurable(item) then
			total += ItemRules.value(item)
		end
	end
	return total
end

--[[
	Indemnisation après une mort : copies des objets assurés (NOUVEAUX uid :
	les originaux sont dans le sac de dépouille), dégradées selon le niveau.
]]
function EconomyRules.insuranceClaim(tier: string, items: { ItemInstance }, create: Create): { ItemInstance }
	local def = Config.Economy.insurance.tiers[tier]
	if def == nil then
		return {}
	end
	local returned = {}
	for _, item in items do
		if EconomyRules.insurable(item) then
			local condition = math.max(Config.Conditions.MIN, (item.condition :: number) - def.conditionLoss)
			table.insert(returned, create(item.itemId, { condition = condition }))
		end
	end
	return returned
end

-- Les objets assurés d'une partie précédente sont rendus via l'écran de tri.
function EconomyRules.deliverInsurance(profile: Profile)
	local pending = profile.pendingInsurance
	if pending == nil then
		return
	end
	for _, item in pending do
		table.insert(profile.pendingLoot, item)
	end
	profile.pendingInsurance = nil
end

-- Caisse gratuite ----------------------------------------------------------

-- Met à jour les caisses accumulées (20 min réelles, 2 au maximum, même hors ligne).
function EconomyRules.accrueFreeCrate(profile: Profile, now: number)
	local def = Config.Economy.freeCrate
	local crate = profile.freeCrate
	if crate.stored >= def.maxStored then
		crate.lastGrantUnix = now
		return
	end
	local elapsed = math.max(0, now - crate.lastGrantUnix)
	local earned = math.floor(elapsed / def.interval)
	if earned <= 0 then
		return
	end
	crate.stored = math.min(def.maxStored, crate.stored + earned)
	if crate.stored >= def.maxStored then
		crate.lastGrantUnix = now
	else
		crate.lastGrantUnix += earned * def.interval
	end
end

export type CrateReward = { kind: "credits", amount: number } | { kind: "item", item: ItemInstance }

--[[
	Ouvre une caisse gratuite : 85 % de crédits (50 à 300), 15 % un objet
	temporaire (consommable ou gadget, Bon état, 3 parties). Si un objet
	temporaire est déjà détenu, la récompense est convertie en crédits.
]]
function EconomyRules.openFreeCrate(
	profile: Profile,
	now: number,
	rng: Rng,
	create: Create
): (boolean, string?, CrateReward?)
	EconomyRules.accrueFreeCrate(profile, now)
	local def = Config.Economy.freeCrate
	if profile.freeCrate.stored > 0 then
		local wasFull = profile.freeCrate.stored >= def.maxStored
		profile.freeCrate.stored -= 1
		if wasFull then
			-- Le minuteur repart quand une place se libère.
			profile.freeCrate.lastGrantUnix = now
		end
	elseif not CrateGifts.consume(profile, "free") then
		-- Ni caisse accumulée, ni caisse offerte par un administrateur.
		return false, "no_crate", nil
	end
	if rng:NextNumber() >= def.creditsChance and profile.tempItem == nil then
		local itemId = def.tempItemPool[rng:NextInteger(1, #def.tempItemPool)]
		local item = create(itemId, { condition = def.tempItemCondition, tempGamesLeft = def.tempItemGames })
		profile.tempItem = item
		return true, nil, { kind = "item", item = item }
	end
	local amount = rng:NextInteger(def.credits.min, def.credits.max)
	addCredits(profile, amount)
	return true, nil, { kind = "credits", amount = amount }
end

-- Fin de partie : l'objet temporaire perd une partie (et disparaît à 0).
function EconomyRules.ageTempItem(item: ItemInstance): ItemInstance?
	if item.tempGamesLeft == nil then
		return item
	end
	local left = item.tempGamesLeft - 1
	if left <= 0 then
		return nil
	end
	item.tempGamesLeft = left
	return item
end

return EconomyRules
