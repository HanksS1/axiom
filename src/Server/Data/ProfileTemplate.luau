--!strict
--[[
	Profil par défaut d'un nouveau joueur (section 19.3).
	Toute nouvelle clé ajoutée ici doit aussi être ajoutée par une
	migration (Migrations.luau) pour les profils existants.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Types = require(Shared.Types)

local ProfileTemplate = {}

-- Version courante du format de profil (doit correspondre à la dernière migration).
ProfileTemplate.VERSION = 1

function ProfileTemplate.defaultSettings(): { [string]: any }
	local settings = {}
	for key, def in Config.Settings do
		settings[key] = def.default
	end
	return settings
end

function ProfileTemplate.new(now: number): Types.Profile
	return {
		version = ProfileTemplate.VERSION,
		createdAt = now,
		level = 1,
		xp = 0,
		credits = 0,
		noyaux = 0,
		vault = {},
		loadout = {},
		bag = {},
		tempItem = nil,
		hasVaultExtension = false,
		-- Le premier joueur reçoit sa première caisse au bout de 20 minutes.
		freeCrate = { stored = 0, lastGrantUnix = now },
		pity = {},
		cosmeticsOwned = {},
		cosmeticsEquipped = {},
		pendingInsurance = nil,
		season = { id = 0, top10 = {} },
		seasonHistory = {},
		bestScoreByMode = {},
		stats = {
			matchesPlayed = 0,
			extractions = 0,
			deaths = 0,
			playerKills = 0,
			botKills = 0,
			robotKills = 0,
		},
		tutorialDone = false,
		settings = ProfileTemplate.defaultSettings(),
		processedReceipts = {},
		receiptOrder = {},
	}
end

return ProfileTemplate
