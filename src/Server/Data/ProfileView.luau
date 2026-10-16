--!strict
--[[
	ProfileView : ce que le client reçoit de son profil (remote ProfileSync).

	Liste EXPLICITE des champs publics : un champ ajouté au profil reste privé
	tant qu'il n'est pas recopié ici. Jamais envoyés : reçus Robux
	(`processedReceipts`, `receiptOrder`), partie en cours (`activeMatch`),
	détail des remboursements d'assurance (seulement leur nombre), version et
	dates internes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local ItemRules = require(Shared.Items.ItemRules)
local Leveling = require(Shared.Progression.Leveling)
local MatchRules = require(Shared.Match.MatchRules)

local ProfileView = {}

function ProfileView.build(profile: Types.Profile): Types.ProfileView
	local freeCrate = Config.Economy.freeCrate
	local nextGrant: number? = nil
	if profile.freeCrate.stored < freeCrate.maxStored then
		nextGrant = profile.freeCrate.lastGrantUnix + freeCrate.interval
	end
	return {
		level = profile.level,
		xp = profile.xp,
		xpToNext = Leveling.xpToNext(profile.level),
		credits = profile.credits,
		noyaux = profile.noyaux,
		vault = profile.vault,
		vaultCapacity = ItemRules.vaultCapacity(profile.hasVaultExtension),
		loadout = profile.loadout,
		bag = profile.bag,
		tempItem = profile.tempItem,
		hasVaultExtension = profile.hasVaultExtension,
		freeCrate = { stored = profile.freeCrate.stored, nextGrantUnix = nextGrant },
		pendingLoot = profile.pendingLoot,
		pendingInsuranceCount = if profile.pendingInsurance then #profile.pendingInsurance else 0,
		insuranceTier = profile.insuranceTier,
		rank = MatchRules.seasonRank(profile.season),
		rankingScore = MatchRules.rankingScore(profile.season.top10),
		seasonId = profile.season.id,
		top10 = profile.season.top10,
		seasonHistory = profile.seasonHistory,
		bestScoreByMode = profile.bestScoreByMode,
		tutorialDone = profile.tutorialDone,
		guidesSeen = profile.guidesSeen,
		crateTokens = profile.crateTokens,
		settings = profile.settings,
		pity = profile.pity,
		cosmeticsOwned = profile.cosmeticsOwned,
		cosmeticsEquipped = profile.cosmeticsEquipped,
		stats = profile.stats :: any,
	}
end

return ProfileView
