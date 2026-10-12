--!strict
--[[
	Shop : règles de la boutique cosmétique (sections 14.5 à 14.9). Module pur.

	- Caisses : tirage de la rareté selon les probabilités affichées, puis
	  d'un cosmétique de cette rareté. Compteur de garantie par caisse : au
	  seuil, le tirage se fait parmi les raretés garanties (probabilités
	  renormalisées et AFFICHÉES comme telles avant l'achat).
	- Probabilités affichées : pourcentages réels dont la somme fait
	  exactement 100 % (arrondi au centième par la méthode du plus fort reste).
	- Doublon : 20 % de la valeur de l'objet, en Noyaux.
	- Holo-Bazar : 6 objets par jour, choisis à partir d'une graine basée sur
	  la date (identiques sur tous les serveurs), renouvelés à 00:00 UTC.
	- Reçus Robux : chaque PurchaseId n'est traité qu'une fois (mémoire bornée).
]]

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

local M = Config.Monetization

local Shop = {}

export type Rng = {
	NextNumber: (self: any, min: number?, max: number?) -> number,
	NextInteger: (self: any, min: number, max: number) -> number,
}

function Shop.rarityIndex(rarity: string): number
	return table.find(M.rarities, rarity) or 0
end

-- Les probabilités d'une caisse font-elles exactement 100 % ?
function Shop.oddsValid(crateId: string): boolean
	local crate = M.crates[crateId]
	if crate == nil then
		return false
	end
	local total = 0
	for _, rarity in M.rarities do
		local value = crate.odds[rarity]
		if type(value) ~= "number" or value < 0 then
			return false
		end
		total += value
	end
	return math.abs(total - 100) < 1e-9
end

-- La garantie s'applique-t-elle au PROCHAIN tirage ?
function Shop.guaranteeNext(crateId: string, pityCount: number): boolean
	local crate = M.crates[crateId]
	return crate ~= nil and pityCount + 1 >= crate.pity.threshold
end

-- Caisses restantes avant la garantie (1 = la prochaine est garantie).
function Shop.untilGuarantee(crateId: string, pityCount: number): number
	local crate = M.crates[crateId]
	return math.max(1, crate.pity.threshold - pityCount)
end

-- Probabilités (en %) du prochain tirage, garantie comprise.
function Shop.effectiveOdds(crateId: string, pityCount: number): { [string]: number }
	local crate = M.crates[crateId]
	local odds: { [string]: number } = {}
	if not Shop.guaranteeNext(crateId, pityCount) then
		for _, rarity in M.rarities do
			odds[rarity] = crate.odds[rarity]
		end
		return odds
	end
	local minimum = Shop.rarityIndex(crate.pity.minRarity)
	local total = 0
	for index, rarity in M.rarities do
		if index >= minimum then
			total += crate.odds[rarity]
		end
	end
	for index, rarity in M.rarities do
		odds[rarity] = if index >= minimum and total > 0 then crate.odds[rarity] / total * 100 else 0
	end
	return odds
end

--[[
	Pourcentages affichés au centième, dont la somme fait exactement 100,00
	(méthode du plus fort reste). Retourne les centièmes entiers par rareté.
]]
function Shop.displayHundredths(odds: { [string]: number }): { [string]: number }
	local result: { [string]: number } = {}
	local remainders: { { rarity: string, rest: number } } = {}
	local sum = 0
	for _, rarity in M.rarities do
		local exact = (odds[rarity] or 0) * 100
		local floor = math.floor(exact + 1e-9)
		result[rarity] = floor
		sum += floor
		table.insert(remainders, { rarity = rarity, rest = exact - floor })
	end
	table.sort(remainders, function(a, b)
		return a.rest > b.rest
	end)
	local missing = 10000 - sum
	for index = 1, math.max(0, missing) do
		local entry = remainders[(index - 1) % #remainders + 1]
		result[entry.rarity] += 1
	end
	return result
end

-- Tire la rareté du prochain objet et retourne le nouveau compteur de garantie.
function Shop.rollRarity(crateId: string, pityCount: number, rng: Rng): (string, number)
	local crate = M.crates[crateId]
	local odds = Shop.effectiveOdds(crateId, pityCount)
	local roll = rng:NextNumber(0, 100)
	local chosen = nil
	local cumulative = 0
	local last = nil
	for _, rarity in M.rarities do
		local chance = odds[rarity]
		if chance > 0 then
			last = rarity
			cumulative += chance
			if chosen == nil and roll < cumulative then
				chosen = rarity
			end
		end
	end
	local rarity = chosen or last :: string
	local reset = Shop.rarityIndex(rarity) >= Shop.rarityIndex(crate.pity.minRarity)
	return rarity, if reset then 0 else pityCount + 1
end

function Shop.cosmeticsOfRarity(rarity: string): { string }
	local result = {}
	for _, id in Config.Cosmetics.list do
		if Config.Cosmetics.byId[id].rarity == rarity then
			table.insert(result, id)
		end
	end
	return result
end

function Shop.pickCosmetic(rarity: string, rng: Rng): string?
	local pool = Shop.cosmeticsOfRarity(rarity)
	if #pool == 0 then
		return nil
	end
	return pool[rng:NextInteger(1, #pool)]
end

function Shop.value(rarity: string): number
	return (M.rarityValue :: any)[rarity] or 0
end

function Shop.duplicateRefund(rarity: string): number
	return math.floor(Shop.value(rarity) * M.duplicateRefundShare)
end

-- Prix d'achat direct (nil : Mythique, caisses uniquement).
function Shop.directPrice(cosmeticId: string): number?
	local def = Config.Cosmetics.byId[cosmeticId]
	if def == nil then
		return nil
	end
	return (M.directPrices :: any)[def.rarity]
end

-- Holo-Bazar --------------------------------------------------------------------

function Shop.dayIndex(unix: number): number
	return math.floor(unix / M.bazaar.rotationPeriod)
end

function Shop.nextRotationAt(unix: number): number
	return (Shop.dayIndex(unix) + 1) * M.bazaar.rotationPeriod
end

-- Générateur déterministe (Park-Miller) : même suite sur tous les serveurs.
local function generator(seed: number): () -> number
	local state = (math.floor(seed) % 2147483646) + 1
	return function(): number
		state = (state * 48271) % 2147483647
		return state
	end
end

-- Sélection du jour : objets achetables directement (pas de Mythique), distincts.
function Shop.rotation(day: number): { string }
	local candidates = {}
	for _, id in Config.Cosmetics.list do
		if Shop.directPrice(id) ~= nil then
			table.insert(candidates, id)
		end
	end
	local nextValue = generator(day * 7919 + 17)
	for index = #candidates, 2, -1 do
		local swap = nextValue() % index + 1
		candidates[index], candidates[swap] = candidates[swap], candidates[index]
	end
	local count = math.min(M.bazaar.featuredCount, #candidates)
	local featured = {}
	for index = 1, count do
		table.insert(featured, candidates[index])
	end
	return featured
end

-- L'objet est-il en vente aujourd'hui (tolérance juste après le changement de jour) ?
function Shop.inRotation(cosmeticId: string, unix: number, grace: number): boolean
	local today = Shop.dayIndex(unix)
	if table.find(Shop.rotation(today), cosmeticId) then
		return true
	end
	local sinceReset = unix - today * M.bazaar.rotationPeriod
	return sinceReset < grace and table.find(Shop.rotation(today - 1), cosmeticId) ~= nil
end

-- Reçus Robux ---------------------------------------------------------------------

function Shop.receiptProcessed(profile: Types.Profile, purchaseId: string): boolean
	return profile.processedReceipts[purchaseId] ~= nil
end

-- Mémorise un reçu traité (les plus anciens sont oubliés au-delà de la limite).
function Shop.recordReceipt(profile: Types.Profile, purchaseId: string, now: number)
	if profile.processedReceipts[purchaseId] ~= nil then
		return
	end
	profile.processedReceipts[purchaseId] = now
	table.insert(profile.receiptOrder, purchaseId)
	while #profile.receiptOrder > M.maxRememberedReceipts do
		local oldest = table.remove(profile.receiptOrder, 1) :: string
		profile.processedReceipts[oldest] = nil
	end
end

-- Emplacement d'équipement d'un cosmétique (arme précise, ou sac / casque / gilet).
function Shop.slotOf(cosmeticId: string): string?
	local def = Config.Cosmetics.byId[cosmeticId]
	if def == nil then
		return nil
	end
	return if def.category == "weapon" then "weapon:" .. def.target else def.category
end

return Shop
