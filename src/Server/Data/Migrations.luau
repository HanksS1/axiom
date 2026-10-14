--!strict
--[[
	Migrations et assainissement des profils.

	Appelé à chaque chargement :
	1. refuse un profil d'une version plus récente que ce serveur (un vieux
	   serveur ne doit jamais écraser des données qu'il ne comprend pas) ;
	2. applique les migrations successives jusqu'à la version courante ;
	3. assainit les données : clés manquantes, types, bornes, objets
	   invalides et uid dupliqués (anti-duplication).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local SettingRules = require(Shared.Settings.SettingRules)
local Types = require(Shared.Types)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local ItemRules = require(Shared.Items.ItemRules)
local ProfileTemplate = require(script.Parent.ProfileTemplate)

type Profile = Types.Profile
type ItemInstance = Types.ItemInstance

local Migrations = {}

export type Report = {
	removedItems: number,
	duplicateUids: number,
	fixedFields: number,
}

--[[
	steps[v] transforme un profil de version v-1 en version v.
	Exemple pour une future version 2 :
		steps[2] = function(data) data.newField = 0 end
]]
local steps: { [number]: (data: any) -> () } = {
	[1] = function(_data)
		-- Version initiale : rien à transformer (l'assainissement complète les clés).
	end,
	[2] = function(data)
		-- P3 : loot extrait en attente de tri, partie en cours.
		data.pendingLoot = data.pendingLoot or {}
	end,
	[3] = function(_data)
		-- P5 : assurance choisie pour la prochaine partie (assainie plus bas).
	end,
	[4] = function(data)
		-- Aides ponctuelles déjà montrées (première caisse du Holo-Bazar…).
		data.guidesSeen = data.guidesSeen or {}
	end,
	[5] = function(data)
		-- Caisses offertes par un administrateur (Config.Admin).
		data.crateTokens = data.crateTokens or {}
	end,
}

local function isInteger(value: any): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and math.abs(value) ~= math.huge
end

local function clampInteger(value: any, min: number, max: number, fallback: number, report: Report): number
	if not isInteger(value) then
		report.fixedFields += 1
		return fallback
	end
	if value < min or value > max then
		report.fixedFields += 1
		return math.clamp(value, min, max)
	end
	return value
end

-- Nettoie un objet : retourne nil s'il est invalide ou si son uid est déjà vu.
local function cleanItem(item: any, seen: { [string]: boolean }, report: Report, where: string): ItemInstance?
	local ok, reason = ItemRules.validate(item)
	if not ok then
		report.removedItems += 1
		warn(`[Migrations] objet invalide retiré ({where}) : {reason}`)
		return nil
	end
	if seen[item.uid] then
		report.duplicateUids += 1
		warn(`[Migrations] uid dupliqué retiré ({where}) : {item.uid}`)
		return nil
	end
	seen[item.uid] = true
	-- Ne conserve que les champs connus (aucune donnée parasite).
	return {
		uid = item.uid,
		itemId = item.itemId,
		condition = item.condition,
		stack = item.stack,
		isKit = if item.isKit then true else nil,
		tempGamesLeft = item.tempGamesLeft,
	}
end

local function cleanItemList(list: any, seen: { [string]: boolean }, report: Report, where: string): { ItemInstance }
	local result = {}
	if type(list) ~= "table" then
		report.fixedFields += 1
		return result
	end
	-- ipairs implicite : s'arrête au premier trou (les clés non séquentielles sont ignorées).
	local index = 1
	while list[index] ~= nil do
		local item = cleanItem(list[index], seen, report, where)
		if item then
			table.insert(result, item)
		end
		index += 1
	end
	return result
end

local function cleanSettings(settings: any, report: Report): { [string]: any }
	local result = ProfileTemplate.defaultSettings()
	if type(settings) ~= "table" then
		report.fixedFields += 1
		return result
	end
	for key in Config.Settings do
		local value = settings[key]
		if value == nil then
			continue
		end
		if SettingRules.isValid(key, value) then
			result[key] = value
		else
			report.fixedFields += 1
		end
	end
	return result
end

local function cleanNumberMap(map: any, report: Report): { [string]: number }
	local result = {}
	if type(map) ~= "table" then
		report.fixedFields += 1
		return result
	end
	for key, value in map do
		if type(key) == "string" and isInteger(value) and value >= 0 then
			result[key] = value
		end
	end
	return result
end

local function cleanBooleanMap(map: any): { [string]: boolean }
	local result = {}
	if type(map) == "table" then
		for key, value in map do
			if type(key) == "string" and value == true then
				result[key] = true
			end
		end
	end
	return result
end

local function cleanStringMap(map: any): { [string]: string }
	local result = {}
	if type(map) == "table" then
		for key, value in map do
			if type(key) == "string" and type(value) == "string" then
				result[key] = value
			end
		end
	end
	return result
end

--[[
	Assainit un profil déjà migré. Retourne un NOUVEAU profil (les données
	brutes ne sont jamais réutilisées telles quelles).
]]
function Migrations.sanitize(data: any, now: number): (Profile, Report)
	local report: Report = { removedItems = 0, duplicateUids = 0, fixedFields = 0 }
	local template = ProfileTemplate.new(now)
	local seen: { [string]: boolean } = {}

	local profile = template
	profile.createdAt = if isInteger(data.createdAt) then data.createdAt else now
	profile.level = clampInteger(data.level, 1, Config.Progression.xp.maxLevel, 1, report)
	profile.xp = clampInteger(data.xp, 0, math.huge, 0, report)
	profile.credits = clampInteger(data.credits, 0, Config.Economy.maxCredits, 0, report)
	profile.noyaux = clampInteger(data.noyaux, 0, Config.Monetization.maxNoyaux, 0, report)
	profile.hasVaultExtension = data.hasVaultExtension == true
	-- Les profils créés avant le tutoriel (P10) et déjà au niveau 2 en sont dispensés.
	profile.tutorialDone = data.tutorialDone == true or profile.level >= Config.Progression.minLevelToPlay
	if type(data.guidesSeen) == "table" then
		for guide, shown in data.guidesSeen do
			if type(guide) == "string" and #guide <= 32 and shown == true then
				profile.guidesSeen[guide] = true
			end
		end
	end
	if type(data.crateTokens) == "table" then
		for _, kind in Config.Admin.giftCrates do
			local count = data.crateTokens[kind]
			if count ~= nil then
				local clean = clampInteger(count, 0, Config.Admin.maxStock, 0, report)
				if clean > 0 then
					profile.crateTokens[kind] = clean
				end
			end
		end
	end

	-- Ordre de priorité en cas d'uid dupliqué : le loadout, puis le sac, puis le coffre.
	local loadout = {}
	if type(data.loadout) == "table" then
		for _, slot in ItemCatalog.slotNames do
			local raw = data.loadout[slot]
			if raw ~= nil then
				local item = cleanItem(raw, seen, report, `loadout.{slot}`)
				if item then
					local info = ItemCatalog.get(item.itemId)
					if info and info.category == ItemCatalog.slotCategories[slot :: Types.SlotName] then
						(loadout :: any)[slot] = item
					else
						-- Objet valide mais dans le mauvais emplacement : on le range au coffre.
						seen[item.uid] = nil
						report.fixedFields += 1
						data.vault = if type(data.vault) == "table" then data.vault else {}
						table.insert(data.vault, item)
					end
				end
			end
		end
	end
	profile.loadout = loadout
	profile.bag = cleanItemList(data.bag, seen, report, "bag")
	profile.vault = cleanItemList(data.vault, seen, report, "vault")
	profile.tempItem = if data.tempItem ~= nil then cleanItem(data.tempItem, seen, report, "tempItem") else nil
	if data.pendingInsurance ~= nil then
		profile.pendingInsurance = cleanItemList(data.pendingInsurance, seen, report, "pendingInsurance")
	end
	profile.pendingLoot = cleanItemList(data.pendingLoot, seen, report, "pendingLoot")
	if type(data.insuranceTier) == "string" and Config.Economy.insurance.tiers[data.insuranceTier] ~= nil then
		profile.insuranceTier = data.insuranceTier
	end
	-- Partie en cours : en dernier (un uid déjà présent ailleurs est écarté).
	local active = data.activeMatch
	if type(active) == "table" and type(active.id) == "string" and type(active.mode) == "string" then
		local snapshot = if type(active.snapshot) == "table" then active.snapshot else {}
		local snapshotLoadout = {}
		if type(snapshot.loadout) == "table" then
			for _, slot in ItemCatalog.slotNames do
				local raw = snapshot.loadout[slot]
				if raw ~= nil then
					local item = cleanItem(raw, seen, report, `activeMatch.{slot}`)
					local info = if item then ItemCatalog.get(item.itemId) else nil
					if item and info and info.category == ItemCatalog.slotCategories[slot :: Types.SlotName] then
						(snapshotLoadout :: any)[slot] = item
					end
				end
			end
		end
		profile.activeMatch = {
			id = active.id,
			startedAt = if isInteger(active.startedAt) then active.startedAt else now,
			mode = active.mode,
			insurance = if type(active.insurance) == "string" then active.insurance else nil,
			snapshot = { loadout = snapshotLoadout, bag = cleanItemList(snapshot.bag, seen, report, "activeMatch.bag") },
		}
	end

	if type(data.freeCrate) == "table" then
		profile.freeCrate = {
			stored = clampInteger(data.freeCrate.stored, 0, Config.Economy.freeCrate.maxStored, 0, report),
			lastGrantUnix = clampInteger(data.freeCrate.lastGrantUnix, 0, now, now, report),
		}
	end

	profile.pity = cleanNumberMap(data.pity, report)
	profile.bestScoreByMode = cleanNumberMap(data.bestScoreByMode, report)
	profile.cosmeticsOwned = cleanBooleanMap(data.cosmeticsOwned)
	profile.cosmeticsEquipped = cleanStringMap(data.cosmeticsEquipped)
	profile.settings = cleanSettings(data.settings, report)

	if type(data.stats) == "table" then
		for key in profile.stats do
			profile.stats[key] = clampInteger(data.stats[key], 0, math.huge, 0, report)
		end
	end

	if type(data.season) == "table" then
		profile.season.id = clampInteger(data.season.id, 0, math.huge, 0, report)
		profile.season.legend = if data.season.legend == true then true else nil
		if type(data.season.top10) == "table" then
			for _, entry in data.season.top10 do
				if
					type(entry) == "table"
					and isInteger(entry.score)
					and type(entry.mode) == "string"
					and isInteger(entry.date)
					and #profile.season.top10 < Config.Progression.season.topGames
				then
					local detail = entry.detail
					local cleanDetail = nil
					if
						type(detail) == "table"
						and isInteger(detail.kills)
						and isInteger(detail.bots)
						and isInteger(detail.robots)
						and isInteger(detail.loot)
						and type(detail.extracted) == "boolean"
					then
						cleanDetail = {
							kills = detail.kills,
							bots = detail.bots,
							robots = detail.robots,
							loot = detail.loot,
							extracted = detail.extracted,
						}
					end
					table.insert(
						profile.season.top10,
						{ score = entry.score, mode = entry.mode, date = entry.date, detail = cleanDetail }
					)
				end
			end
		end
	end
	if type(data.seasonHistory) == "table" then
		for _, entry in data.seasonHistory do
			if type(entry) == "table" and isInteger(entry.id) and type(entry.rank) == "string" then
				table.insert(profile.seasonHistory, { id = entry.id, rank = entry.rank })
			end
		end
	end

	-- Reçus déjà traités (idempotence des achats Robux) : jamais perdus.
	if type(data.processedReceipts) == "table" then
		for purchaseId, time in data.processedReceipts do
			if type(purchaseId) == "string" then
				profile.processedReceipts[purchaseId] = if isInteger(time) then time else now
			end
		end
	end
	if type(data.receiptOrder) == "table" then
		for _, purchaseId in data.receiptOrder do
			if type(purchaseId) == "string" and profile.processedReceipts[purchaseId] ~= nil then
				table.insert(profile.receiptOrder, purchaseId)
			end
		end
	end
	-- Tout reçu présent dans la table mais absent de l'ordre est ajouté en tête.
	local ordered: { [string]: boolean } = {}
	for _, purchaseId in profile.receiptOrder do
		ordered[purchaseId] = true
	end
	for purchaseId in profile.processedReceipts do
		if not ordered[purchaseId] then
			table.insert(profile.receiptOrder, 1, purchaseId)
		end
	end

	profile.version = ProfileTemplate.VERSION
	return profile, report
end

--[[
	Migre puis assainit des données brutes. Retourne nil + code d'erreur si
	le profil ne peut pas être utilisé sans risque.
]]
function Migrations.run(data: any, now: number): (Profile?, string?, Report?)
	if type(data) ~= "table" then
		return nil, "invalid_data"
	end
	local version = data.version
	if version == nil then
		version = 0
	end
	if not isInteger(version) or version < 0 then
		return nil, "invalid_version"
	end
	if version > ProfileTemplate.VERSION then
		-- Profil écrit par une version plus récente du jeu : ce serveur est
		-- obsolète, il ne doit surtout pas le réécrire.
		return nil, "newer_version"
	end
	for target = version + 1, ProfileTemplate.VERSION do
		local step = steps[target]
		assert(step ~= nil, `migration manquante vers la version {target}`)
		step(data)
		data.version = target
	end
	local profile, report = Migrations.sanitize(data, now)
	return profile, nil, report
end

return Migrations
