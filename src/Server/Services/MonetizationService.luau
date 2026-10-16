--!strict
--[[
	MonetizationService : Noyaux, Holo-Bazar, caisses cosmétiques, extension
	de coffre (sections 14.5 à 14.9).

	Obligations Roblox :
	- achats en Robux uniquement via MarketplaceService ; `ProcessReceipt`
	  IDEMPOTENT : chaque PurchaseId est mémorisé dans le profil, et le reçu
	  n'est confirmé qu'APRÈS une sauvegarde réussie (sinon Roblox le
	  représentera, sans double crédit) ;
	- PolicyService : si les objets aléatoires payants sont interdits pour le
	  joueur (ou si l'information est indisponible), les caisses lui sont
	  refusées et masquées ; les achats directs restent possibles ;
	- probabilités exactes affichées avant l'achat (Shop.effectiveOdds).

	Les Noyaux ne s'échangent jamais contre des crédits ni de l'équipement.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Guard = require(Shared.Util.Guard)
local Shop = require(Shared.Monetization.Shop)
local Types = require(Shared.Types)

local TransactionLog = require(script.Parent.Parent.Economy.TransactionLog)
local CrateGifts = require(script.Parent.Parent.Economy.CrateGifts)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local CharacterService = require(script.Parent.CharacterService)
local DataService = require(script.Parent.DataService)

local M = Config.Monetization

local MonetizationService = {}

-- Tolérance (s) pour acheter un objet de la rotation précédente juste après minuit UTC.
local ROTATION_GRACE = 120
local POLICY_ATTRIBUTE = "PaidRandomItemsRestricted"

local random = Random.new()

local function packForProduct(productId: number): any?
	if productId == 0 then
		return nil
	end
	for _, pack in M.noyauxPacks :: { [string]: any } do
		if pack.productId == productId then
			return pack
		end
	end
	return nil
end

-- PolicyService ---------------------------------------------------------------------

local function checkPolicy(player: Player)
	-- Par prudence, les caisses restent masquées tant que la réponse n'est pas connue.
	player:SetAttribute(POLICY_ATTRIBUTE, true)
	for attempt = 1, 3 do
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		if ok and type(info) == "table" then
			if player.Parent == Players then
				player:SetAttribute(POLICY_ATTRIBUTE, (info :: any).ArePaidRandomItemsRestricted == true)
			end
			return
		end
		if attempt < 3 then
			task.wait(5 * attempt)
		end
		if player.Parent ~= Players then
			return
		end
	end
	warn(`[MonetizationService] PolicyService indisponible pour {player.UserId} : caisses masquées`)
end

local function paidRandomAllowed(player: Player): boolean
	return player:GetAttribute(POLICY_ATTRIBUTE) == false
end

-- Reçus Robux (Noyaux) -------------------------------------------------------------

local function processReceipt(receipt: any): EnumItem
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local pack = packForProduct(receipt.ProductId)
	if pack == nil then
		warn(`[MonetizationService] produit inconnu : {receipt.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = DataService.waitForProfile(player, 15)
	if profile == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	local granted = false
	if not Shop.receiptProcessed(profile, purchaseId) then
		granted = DataService.update(player, function(current)
			if Shop.receiptProcessed(current, purchaseId) then
				return false
			end
			current.noyaux = math.min(M.maxNoyaux, current.noyaux + pack.noyaux)
			Shop.recordReceipt(current, purchaseId, os.time())
			return true
		end)
	end
	local current = DataService.getProfile(player)
	if current == nil or not Shop.receiptProcessed(current, purchaseId) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- Confirmation uniquement après une sauvegarde réussie.
	if not DataService.saveNow(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if granted then
		TransactionLog.record(player, "robux.noyaux", {
			purchaseId = purchaseId,
			productId = receipt.ProductId,
			noyaux = pack.noyaux,
		})
		ServerNet.notify(player, "shop.noyauxAdded", { noyaux = pack.noyaux })
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Extension de coffre (Game Pass) ------------------------------------------------------

local function grantVaultExtension(player: Player)
	local changed = DataService.update(player, function(profile)
		if profile.hasVaultExtension then
			return false
		end
		profile.hasVaultExtension = true
		return true
	end)
	if changed then
		TransactionLog.record(player, "robux.vaultExtension", nil)
		ServerNet.notify(player, "shop.vaultExtended")
	end
end

local function checkGamePass(player: Player)
	local gamePassId = M.vaultExtension.gamePassId
	if gamePassId == 0 then
		return
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
	end)
	-- En cas d'erreur, on garde la valeur du profil (un achat n'est jamais retiré).
	if ok and owns then
		grantVaultExtension(player)
	end
end

-- Actions du Holo-Bazar -------------------------------------------------------------

local function fail(player: Player, reason: string)
	ServerNet.notify(player, "shop.failure." .. reason)
end

local function buy(player: Player, cosmeticId: string)
	local reason: string? = nil
	local price = 0
	local ok = DataService.update(player, function(profile)
		if profile.cosmeticsOwned[cosmeticId] then
			reason = "owned"
			return false
		end
		if not Shop.inRotation(cosmeticId, os.time(), ROTATION_GRACE) then
			reason = "not_in_rotation"
			return false
		end
		local directPrice = Shop.directPrice(cosmeticId)
		if directPrice == nil then
			reason = "not_for_sale"
			return false
		end
		if profile.noyaux < directPrice then
			reason = "not_enough_noyaux"
			return false
		end
		price = directPrice
		profile.noyaux -= directPrice
		profile.cosmeticsOwned[cosmeticId] = true
		return true
	end)
	if not ok then
		fail(player, reason or "unknown")
		return
	end
	TransactionLog.record(player, "bazaar.buy", { cosmeticId = cosmeticId, price = price })
	-- Noyaux (achetés en Robux) dépensés : sauvegardé tout de suite.
	task.spawn(DataService.saveNow, player)
	ServerNet.notify(player, "shop.bought", { item = cosmeticId })
end

local function openCrate(player: Player, crateId: string)
	if not Shop.oddsValid(crateId) then
		fail(player, "unknown")
		return
	end
	-- Une caisse OFFERTE (administrateur) ne s'achète pas : elle reste ouvrable
	-- même là où les objets aléatoires payants sont interdits.
	local profileNow = DataService.getProfile(player)
	local gifted = profileNow ~= nil and CrateGifts.count(profileNow, crateId) > 0
	if not gifted and not paidRandomAllowed(player) then
		fail(player, "restricted")
		return
	end
	local crate = M.crates[crateId]
	local reason: string? = nil
	local result: { [string]: any }? = nil
	local usedGift = false
	local ok = DataService.update(player, function(profile)
		usedGift = CrateGifts.consume(profile, crateId)
		if not usedGift and profile.noyaux < crate.price then
			reason = "not_enough_noyaux"
			return false
		end
		local pity = profile.pity[crateId] or 0
		local rarity, nextPity = Shop.rollRarity(crateId, pity, random)
		local cosmeticId = Shop.pickCosmetic(rarity, random)
		if cosmeticId == nil then
			reason = "unknown"
			return false
		end
		if not usedGift then
			profile.noyaux -= crate.price
		end
		profile.pity[crateId] = nextPity
		local duplicate = profile.cosmeticsOwned[cosmeticId] == true
		local refund = 0
		if duplicate then
			refund = Shop.duplicateRefund(rarity)
			profile.noyaux = math.min(M.maxNoyaux, profile.noyaux + refund)
		else
			profile.cosmeticsOwned[cosmeticId] = true
		end
		-- Première caisse : le client explique ce qu'est un cosmétique (une seule fois).
		local firstTime = profile.guidesSeen.cosmetics ~= true
		profile.guidesSeen.cosmetics = true
		result = {
			crateId = crateId,
			cosmeticId = cosmeticId,
			rarity = rarity,
			duplicate = duplicate,
			refund = refund,
			guaranteed = Shop.guaranteeNext(crateId, pity),
			firstTime = firstTime,
			gifted = usedGift,
		}
		return true
	end)
	if not ok or result == nil then
		fail(player, reason or "unknown")
		return
	end
	TransactionLog.record(player, "crate.open", result)
	-- Tirage au sort (et compteur de garantie) : sauvegardé tout de suite, pour qu'un
	-- plantage ne fasse ni perdre le cosmétique ni rejouer le tirage.
	task.spawn(DataService.saveNow, player)
	ServerNet.fire("CosmeticCrateResult", player, result)
end

-- Emplacement d'équipement valide (arme connue, sac, casque, gilet) ?
local function validSlot(slot: string): boolean
	if slot == "backpack" or slot == "helmet" or slot == "vest" then
		return true
	end
	local weaponId = string.match(slot, "^weapon:([%w_]+)$")
	return weaponId ~= nil and (Config.Weapons.ranged[weaponId] ~= nil or Config.Weapons.melee[weaponId] ~= nil)
end

local function equip(player: Player, slot: string, cosmeticId: string?)
	if not validSlot(slot) then
		ServerNet.flag(player, "EquipCosmetic", "emplacement invalide")
		return
	end
	local ok = DataService.update(player, function(profile: Types.Profile)
		if cosmeticId == nil then
			if profile.cosmeticsEquipped[slot] == nil then
				return false
			end
			profile.cosmeticsEquipped[slot] = nil
			return true
		end
		if not profile.cosmeticsOwned[cosmeticId] or Shop.slotOf(cosmeticId) ~= slot then
			return false
		end
		profile.cosmeticsEquipped[slot] = cosmeticId
		return true
	end)
	if ok then
		CharacterService.applySkins(player)
	end
end

function MonetizationService.init()
	MarketplaceService.ProcessReceipt = processReceipt

	ServerNet.onEvent("BazaarBuy", Guard.tuple(Guard.keyOf(Config.Cosmetics.byId)), buy)
	ServerNet.onEvent("CosmeticCrateOpen", Guard.tuple(Guard.keyOf(M.crates)), openCrate)
	ServerNet.onEvent(
		"EquipCosmetic",
		Guard.tuple(Guard.string(48, "^[%w_:]+$"), Guard.optional(Guard.keyOf(Config.Cosmetics.byId))),
		equip
	)
end

function MonetizationService.start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(checkPolicy, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(checkPolicy, player)
	end
	DataService.ProfileLoaded:Connect(function(player)
		task.spawn(checkGamePass, player)
		CharacterService.applySkins(player)
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
		if purchased and gamePassId == M.vaultExtension.gamePassId and gamePassId ~= 0 then
			grantVaultExtension(player)
		end
	end)
end

return MonetizationService
