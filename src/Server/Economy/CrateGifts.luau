--!strict
--[[
	CrateGifts : caisses offertes par un administrateur (module PUR).

	Le profil garde, par type de caisse, le nombre de caisses offertes en
	attente (`crateTokens`). Une caisse offerte s'ouvre exactement comme une
	caisse achetée (mêmes probabilités, même garantie), mais sans payer :
	- caisse gratuite : utilisée quand le compteur normal est à zéro ;
	- caisses du Holo-Bazar : utilisée avant les Noyaux.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local CrateGifts = {}

local Admin = Config.Admin

-- Type de caisse qu'un administrateur peut offrir ?
function CrateGifts.isGiftable(kind: any): boolean
	return type(kind) == "string" and table.find(Admin.giftCrates, kind) ~= nil
end

-- Caisses offertes en attente d'un type.
function CrateGifts.count(profile: any, kind: string): number
	local tokens = profile.crateTokens
	return if type(tokens) == "table" and type(tokens[kind]) == "number" then tokens[kind] else 0
end

--[[
	Ajoute `amount` caisses offertes de type `kind`. Retourne (succès, raison,
	nouveau total). Refus : type inconnu, quantité invalide ou trop grande,
	stock plein.
]]
function CrateGifts.grant(profile: any, kind: string, amount: number): (boolean, string?, number)
	if not CrateGifts.isGiftable(kind) then
		return false, "unknown_crate", 0
	end
	if type(amount) ~= "number" or amount % 1 ~= 0 or amount < 1 or amount > Admin.maxPerGift then
		return false, "invalid_amount", CrateGifts.count(profile, kind)
	end
	local current = CrateGifts.count(profile, kind)
	if current + amount > Admin.maxStock then
		return false, "stock_full", current
	end
	profile.crateTokens = profile.crateTokens or {}
	profile.crateTokens[kind] = current + amount
	return true, nil, current + amount
end

--[[
	Ajoute `amount` crédits offerts. Retourne (succès, raison, crédits réellement
	ajoutés) : le total reste borné par Economy.maxCredits.
]]
function CrateGifts.grantCredits(profile: any, amount: number): (boolean, string?, number)
	if type(amount) ~= "number" or amount % 1 ~= 0 or amount < 1 or amount > Admin.maxCreditsPerGift then
		return false, "invalid_amount", 0
	end
	local before = profile.credits
	profile.credits = math.min(Config.Economy.maxCredits, before + amount)
	local added = profile.credits - before
	if added <= 0 then
		return false, "credits_full", 0
	end
	return true, nil, added
end

-- Utilise une caisse offerte de type `kind`, s'il en reste. Retourne true si une a été utilisée.
function CrateGifts.consume(profile: any, kind: string): boolean
	local current = CrateGifts.count(profile, kind)
	if current <= 0 then
		return false
	end
	profile.crateTokens[kind] = if current > 1 then current - 1 else nil
	return true
end

--[[
	Est-ce un administrateur ? Liste d'identifiants, rang dans le groupe
	(`groupRank`, 0 si inconnu), ou Roblox Studio si la config le permet.
]]
function CrateGifts.isAdmin(userId: number, groupRank: number, inStudio: boolean): boolean
	if inStudio and Admin.everyoneInStudio then
		return true
	end
	if table.find(Admin.userIds, userId) ~= nil then
		return true
	end
	return Admin.groupId ~= 0 and groupRank >= Admin.minGroupRank
end

return CrateGifts
