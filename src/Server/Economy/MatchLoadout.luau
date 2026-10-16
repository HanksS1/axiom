--!strict
--[[
	MatchLoadout : l'équipement du joueur entre le profil et une partie
	(module PUR, testé : tests/specs/matchloadout.spec.luau).

	- `takeForMatch` : au départ, l'objet temporaire rejoint l'équipement,
	  l'assurance choisie est payée, l'équipement QUITTE le profil (il est « dans
	  la partie ») et un instantané de secours est gardé dans `activeMatch`.
	- `settle` : à la fin, l'équipement extrait revient (emplacements libres,
	  le reste au tri) ou, après une mort assurée, l'assurance prépare sa
	  restitution pour la partie suivante. `activeMatch` est toujours effacé.
	- `restoreAbandoned` : une partie qui ne s'est pas terminée (serveur planté,
	  téléportation échouée) rend l'équipement de l'instantané, sans jamais
	  dépasser la capacité du sac préparé (l'excédent part au tri).

	Aucune attente, aucune Instance : appelé dans DataService.update.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Freeze = require(Shared.Util.Freeze)
local InventoryLogic = require(Shared.Items.InventoryLogic)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local ItemRules = require(Shared.Items.ItemRules)
local Pricing = require(Shared.Economy.Pricing)
local Types = require(Shared.Types)

local EconomyRules = require(script.Parent.EconomyRules)

type Profile = Types.Profile
type ItemInstance = Types.ItemInstance
type Create = (itemId: string, options: { [string]: any }?) -> ItemInstance

local MatchLoadout = {}

export type Departure = {
	bag: InventoryLogic.Inventory, -- équipement emporté (copie de travail de la partie)
	insurance: string?, -- niveau payé (nil : pas d'assurance)
	insuranceRefused: boolean, -- niveau choisi mais pas assez de crédits
	insuranceUseless: boolean, -- niveau choisi mais rien d'assurable : rien n'est payé
}

-- Objet d'un emplacement d'équipement (lecture par nom d'emplacement).
local function slotItem(loadout: Types.Loadout, slot: string): ItemInstance?
	return (loadout :: any)[slot] :: ItemInstance?
end

local function setSlotItem(loadout: Types.Loadout, slot: string, item: ItemInstance?)
	(loadout :: any)[slot] = item
end

-- Prix de l'assurance au départ, sur la valeur ASSURÉE (nil : pas d'assurance
-- choisie ou niveau inconnu ; 0 : rien d'assurable).
function MatchLoadout.insuranceCost(tier: string?, loadout: Types.Loadout, bag: { ItemInstance }): number?
	if tier == nil then
		return nil
	end
	return Pricing.insuranceCost(tier, Pricing.insuredValue(loadout, bag))
end

--[[
	Départ en partie : l'équipement quitte le profil. Retourne le sac de la
	partie et l'assurance payée.
]]
function MatchLoadout.takeForMatch(profile: Profile, matchId: string, modeId: string, now: number): Departure
	local loadout = profile.loadout
	local bag = profile.bag
	-- L'objet temporaire part avec le joueur (gadget : emplacement libre, sinon sac).
	local temp = profile.tempItem
	profile.tempItem = nil
	if temp then
		local info = ItemCatalog.get(temp.itemId)
		if info and info.category == "gadget" and loadout.gadget1 == nil then
			loadout.gadget1 = temp
		elseif info and info.category == "gadget" and loadout.gadget2 == nil then
			loadout.gadget2 = temp
		else
			table.insert(bag, temp)
		end
	end
	-- Assurance choisie : payée maintenant, selon l'équipement de départ.
	local insurance: string? = nil
	local insuranceRefused = false
	local insuranceUseless = false
	local tier = profile.insuranceTier
	profile.insuranceTier = nil
	if tier then
		local cost = MatchLoadout.insuranceCost(tier, loadout, bag)
		if cost == 0 then
			insuranceUseless = true -- rien d'assurable : on ne paie pas pour rien
		elseif cost and profile.credits >= cost then
			profile.credits -= cost
			insurance = tier
		else
			insuranceRefused = true
		end
	end
	profile.activeMatch = {
		id = matchId,
		startedAt = now,
		mode = modeId,
		insurance = insurance,
		snapshot = { loadout = Freeze.copy(loadout), bag = Freeze.copy(bag) },
	}
	local matchBag = InventoryLogic.new(Freeze.copy(loadout), Freeze.copy(bag))
	profile.loadout = {}
	profile.bag = {}
	return {
		bag = matchBag,
		insurance = insurance,
		insuranceRefused = insuranceRefused,
		insuranceUseless = insuranceUseless,
	}
end

--[[
	Fin de partie : retour de l'équipement (extraction) ou restitution par
	l'assurance (mort assurée). Retourne la valeur du butin ramené.
]]
function MatchLoadout.settle(
	profile: Profile,
	carried: InventoryLogic.Inventory?,
	extracted: boolean,
	create: Create
): number
	local active = profile.activeMatch
	-- Les objets assurés perdus lors d'une partie PRÉCÉDENTE sont rendus maintenant.
	EconomyRules.deliverInsurance(profile)

	local lootValue = 0
	local function bringBack(item: ItemInstance, slot: string?)
		if item.isKit then
			return -- le kit reste gratuit et illimité : rien à conserver
		end
		if item.tempGamesLeft ~= nil then
			-- Objet temporaire : il perd une partie et retourne dans son emplacement spécial.
			local aged = EconomyRules.ageTempItem(item)
			if aged and profile.tempItem == nil then
				profile.tempItem = aged
			end
			return
		end
		lootValue += ItemRules.value(item)
		if slot and slotItem(profile.loadout, slot) == nil then
			setSlotItem(profile.loadout, slot, item)
		else
			table.insert(profile.pendingLoot, item)
		end
	end

	if extracted and carried then
		-- Équipement porté : retour dans les emplacements libres, le reste à trier.
		for _, slot in ItemCatalog.slotNames do
			local item = slotItem(carried.equipped, slot)
			if item then
				bringBack(item, slot)
			end
		end
		for _, item in carried.bag do
			bringBack(item, nil)
		end
	elseif active and active.insurance then
		-- Mort : l'assurance rendra l'équipement de départ (dégradé selon le niveau)
		-- après la PROCHAINE partie, avec de nouveaux uid.
		local insured: { ItemInstance } = {}
		for _, slot in ItemCatalog.slotNames do
			local item = slotItem(active.snapshot.loadout, slot)
			if item then
				table.insert(insured, item)
			end
		end
		for _, item in active.snapshot.bag do
			table.insert(insured, item)
		end
		local returned = EconomyRules.insuranceClaim(active.insurance, insured, create)
		if #returned > 0 then
			profile.pendingInsurance = returned
		end
	end
	profile.activeMatch = nil
	return lootValue
end

--[[
	Partie non terminée : rend l'équipement de l'instantané. Les emplacements
	occupés entre-temps envoient l'objet au tri ; le sac préparé ne dépasse
	jamais sa capacité (l'excédent part au tri). Retourne false s'il n'y avait
	rien à restaurer.
]]
function MatchLoadout.restoreAbandoned(profile: Profile): boolean
	local match = profile.activeMatch
	if match == nil then
		return false
	end
	for _, slot in ItemCatalog.slotNames do
		local item = slotItem(match.snapshot.loadout, slot)
		if item then
			if slotItem(profile.loadout, slot) == nil then
				setSlotItem(profile.loadout, slot, item)
			else
				table.insert(profile.pendingLoot, item)
			end
		end
	end
	local capacity = ItemRules.bagCapacity(profile.loadout.backpack)
	local used = ItemRules.totalUp(profile.bag)
	for _, item in match.snapshot.bag do
		local up = ItemRules.up(item)
		if used + up <= capacity then
			table.insert(profile.bag, item)
			used += up
		else
			table.insert(profile.pendingLoot, item)
		end
	end
	profile.activeMatch = nil
	return true
end

return MatchLoadout
