--!strict
--[[
	DataService : profils joueurs, sauvegarde et verrouillage de session.

	- Chargement à l'arrivée (verrou de session, migrations, assainissement).
	- Sauvegarde automatique périodique, à la sortie et à l'arrêt du serveur.
	- Libération explicite avant une téléportation (`releaseForTeleport`).
	- Toute modification passe par `DataService.update(player, fn)` : le
	  profil n'est JAMAIS modifié par le client, et les mutations sont
	  synchrones (aucune attente dans `fn`) pour rester atomiques.
	- Après chaque modification, une vue publique du profil est envoyée au
	  client (regroupée à la fin de la frame).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Freeze = require(Shared.Util.Freeze)
local Guard = require(Shared.Util.Guard)
local Localization = require(Shared.Localization)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)
local try = require(Shared.Util.Try)
local ItemRules = require(Shared.Items.ItemRules)
local Leveling = require(Shared.Progression.Leveling)
local MatchRules = require(Shared.Match.MatchRules)

local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local Uid = require(script.Parent.Parent.Util.Uid)
local Migrations = require(script.Parent.Parent.Data.Migrations)
local MockDataStore = require(script.Parent.Parent.Data.MockDataStore)
local ProfileTemplate = require(script.Parent.Parent.Data.ProfileTemplate)
local SessionStore = require(script.Parent.Parent.Data.SessionStore)

type Profile = Types.Profile

local DataService = {}

-- (player, profile) : profil chargé et prêt.
DataService.ProfileLoaded = Signal.new() :: Signal.Signal<Player, Profile>

local store: SessionStore.SessionStore
local sessions: { [Player]: SessionStore.Session } = {}
local releasingUserIds: { [number]: boolean } = {}
local syncQueued: { [Player]: boolean } = {}
local beforeReleaseCallbacks: { (player: Player, profile: Profile) -> () } = {}
local usingMock = false
local shuttingDown = false

local function keyFor(userId: number): string
	return Config.Data.keyPrefix .. tostring(userId)
end

local function languageOf(player: Player): Localization.Language
	local session = sessions[player]
	local setting = if session then session.data.settings.language else nil
	return Localization.resolve(setting, player.LocaleId)
end

local function kick(player: Player, key: string)
	if player.Parent == Players then
		player:Kick(Localization.get(languageOf(player), key))
	end
end

-- Choisit le DataStore réel, ou un stockage en mémoire en Studio si les API sont désactivées.
local function selectDataStore(): SessionStore.DataStoreLike
	local dataStore = DataStoreService:GetDataStore(Config.Data.storeName)
	if RunService:IsStudio() and Config.Data.allowMockInStudio then
		local ok = pcall(function()
			dataStore:GetAsync("__access_probe")
		end)
		if not ok then
			usingMock = true
			warn(
				"[DataService] API DataStore inaccessibles en Studio : profils en MÉMOIRE (perdus à l'arrêt). "
					.. "Activez « Enable Studio Access to API Services » pour tester la persistance."
			)
			return MockDataStore.new()
		end
	end
	return dataStore
end

--[[
	Vue publique du profil envoyée au client. Ne contient que ce dont
	l'interface a besoin (pas de reçus, pas de compteurs internes).
]]
function DataService.buildView(profile: Profile): Types.ProfileView
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
		rank = MatchRules.rank(MatchRules.rankingScore(profile.season.top10)),
		rankingScore = MatchRules.rankingScore(profile.season.top10),
		seasonId = profile.season.id,
		top10 = profile.season.top10,
		bestScoreByMode = profile.bestScoreByMode,
		tutorialDone = profile.tutorialDone,
		settings = profile.settings,
		stats = profile.stats :: any,
	}
end

local function queueSync(player: Player)
	if syncQueued[player] then
		return
	end
	syncQueued[player] = true
	task.defer(function()
		syncQueued[player] = nil
		local session = sessions[player]
		if session and session.active and player.Parent == Players then
			ServerNet.fire("ProfileSync", player, DataService.buildView(session.data))
		end
	end)
end

-- Ferme la session d'un joueur : callbacks de finalisation puis sauvegarde + libération.
local function releaseSession(player: Player): boolean
	local session = sessions[player]
	if session == nil then
		return true
	end
	sessions[player] = nil
	syncQueued[player] = nil
	for _, callback in beforeReleaseCallbacks do
		local ok, err = try(callback, player, session.data)
		if not ok then
			warn(`[DataService] erreur de finalisation pour {player.UserId} : {err}`)
		end
	end
	releasingUserIds[player.UserId] = true
	local ok, err = store:save(session, true)
	releasingUserIds[player.UserId] = nil
	if not ok then
		warn(`[DataService] libération du profil {player.UserId} : {err}`)
	end
	return ok
end

local function onPlayerAdded(player: Player)
	-- Le joueur revient sur ce serveur alors que son ancienne session se
	-- libère encore : on attend la fin de l'écriture.
	while releasingUserIds[player.UserId] do
		task.wait(0.1)
	end
	if player.Parent ~= Players or shuttingDown then
		return
	end

	local session, acquireError = store:acquire(keyFor(player.UserId), player.UserId)
	if session == nil then
		warn(`[DataService] profil {player.UserId} non chargé : {acquireError}`)
		kick(player, "kick.profileLoadFailed")
		return
	end

	local profile, migrationError, report = Migrations.run(session.data, os.time())
	if profile == nil then
		-- On libère le verrou en réécrivant les données brutes telles quelles.
		warn(`[DataService] profil {player.UserId} inutilisable : {migrationError}`)
		store:save(session, true)
		kick(player, "kick.profileLoadFailed")
		return
	end
	if report and (report.removedItems > 0 or report.duplicateUids > 0) then
		warn(
			`[DataService] profil {player.UserId} assaini : {report.removedItems} objet(s) invalide(s), `
				.. `{report.duplicateUids} uid dupliqué(s)`
		)
	end
	session.data = profile

	if player.Parent ~= Players or shuttingDown then
		-- Parti pendant le chargement : on sauvegarde la version migrée et on libère.
		store:save(session, true)
		return
	end

	sessions[player] = session
	DataService.ProfileLoaded:Fire(player, profile)
	queueSync(player)
end

local function onPlayerRemoving(player: Player)
	releaseSession(player)
end

local function autosaveLoop()
	while true do
		task.wait(Config.Data.autosaveInterval)
		local players = {}
		for player in sessions do
			table.insert(players, player)
		end
		if #players == 0 then
			continue
		end
		-- Étale les sauvegardes sur l'intervalle pour lisser le budget DataStore.
		local spacing = math.min(1, Config.Data.autosaveInterval / (#players + 1))
		for _, player in players do
			local session = sessions[player]
			if session and session.active then
				task.spawn(function()
					local ok, err = store:save(session, false)
					if not ok and err == "lost" and sessions[player] == session then
						sessions[player] = nil
						kick(player, "kick.profileSessionLost")
					end
				end)
			end
			task.wait(spacing)
		end
	end
end

local function onClose()
	shuttingDown = true
	local pending = 0
	for player in table.clone(sessions) do
		pending += 1
		task.spawn(function()
			releaseSession(player)
			pending -= 1
		end)
	end
	local deadline = os.clock() + 25
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end

local function settingValid(key: string, value: any): boolean
	local def = Config.Settings[key]
	if def == nil then
		return false
	end
	if def.kind == "boolean" then
		return type(value) == "boolean"
	elseif def.kind == "number" then
		return Guard.isFiniteNumber(value) and value >= (def.min :: number) and value <= (def.max :: number)
	elseif def.kind == "enum" then
		return type(value) == "string" and table.find(def.values :: { string }, value) ~= nil
	end
	return false
end

-- API ----------------------------------------------------------------------

function DataService.init()
	store = SessionStore.new({
		store = selectDataStore() :: any,
		jobId = if game.JobId ~= "" then game.JobId else "studio-" .. Uid.new(),
		placeId = game.PlaceId,
		now = os.time,
		wait = function(seconds)
			task.wait(seconds)
		end,
		generateId = Uid.new,
		template = function()
			return ProfileTemplate.new(os.time())
		end,
		lockTimeout = Config.Data.lockTimeout,
		loadAttempts = Config.Data.loadAttempts,
		loadRetryDelay = Config.Data.loadRetryDelay,
		saveAttempts = Config.Data.saveAttempts,
		saveRetryDelay = Config.Data.saveRetryDelay,
	})

	ServerNet.onRequest("RequestProfile", Guard.tuple(), function(player)
		local session = sessions[player]
		return if session then DataService.buildView(session.data) else nil
	end)

	ServerNet.onEvent(
		"UpdateSetting",
		Guard.tuple(Guard.keyOf(Config.Settings), Guard.any()),
		function(player, key: string, value: any)
			if not settingValid(key, value) then
				return
			end
			DataService.update(player, function(profile)
				profile.settings[key] = value
			end)
		end
	)
end

function DataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	task.spawn(autosaveLoop)
	game:BindToClose(onClose)
end

function DataService.isUsingMock(): boolean
	return usingMock
end

-- Profil chargé du joueur (nil s'il n'est pas encore chargé ou déjà libéré).
-- À utiliser en LECTURE : toute écriture passe par `update`.
function DataService.getProfile(player: Player): Profile?
	local session = sessions[player]
	return if session and session.active then session.data else nil
end

-- Attend le chargement du profil (nil si le joueur part ou si le délai expire).
function DataService.waitForProfile(player: Player, timeout: number?): Profile?
	local deadline = os.clock() + (timeout or 30)
	while player.Parent == Players and os.clock() < deadline do
		local profile = DataService.getProfile(player)
		if profile then
			return profile
		end
		task.wait(0.1)
	end
	return DataService.getProfile(player)
end

--[[
	Modifie le profil de façon atomique. `mutator` ne doit PAS céder la main
	(pas de task.wait, pas d'appel réseau). Si `mutator` lève une erreur, la
	modification est abandonnée : on travaille sur une copie qui ne
	remplace l'original qu'en cas de succès.
	Retourne true si la modification a été appliquée.
]]
function DataService.update(player: Player, mutator: (profile: Profile) -> ...any): boolean
	local session = sessions[player]
	if session == nil or not session.active then
		return false
	end
	-- Copie profonde : un échec en cours de route ne laisse jamais le profil
	-- à moitié modifié (le profil fait quelques Ko, la copie est négligeable).
	local original = session.data
	local working = Freeze.copy(original)
	-- Exécution dans une coroutine : si `mutator` cède la main (task.wait,
	-- appel réseau…), la modification est refusée au lieu de risquer
	-- d'écraser une autre modification faite pendant l'attente.
	local routine = coroutine.create(mutator)
	local ok, err = coroutine.resume(routine, working)
	if ok and err == false then
		-- Refus explicite (`return false`) : abandon silencieux.
		return false
	end
	if not ok then
		warn(`[DataService] modification annulée pour {player.UserId} : {err}`)
		return false
	end
	if coroutine.status(routine) ~= "dead" then
		warn(`[DataService] modification annulée pour {player.UserId} : la fonction a cédé la main`)
		return false
	end
	if session.data ~= original or not session.active then
		return false
	end
	session.data = working
	queueSync(player)
	return true
end

-- Sauvegarde immédiate (après un achat Robux, une extraction…).
function DataService.saveNow(player: Player): boolean
	local session = sessions[player]
	if session == nil then
		return false
	end
	local ok, err = store:save(session, false)
	if not ok and err == "lost" and sessions[player] == session then
		sessions[player] = nil
		kick(player, "kick.profileSessionLost")
	end
	return ok
end

-- Sauvegarde et libère le profil AVANT une téléportation (section 19.4).
-- Après cet appel, plus aucune modification n'est acceptée pour ce joueur.
function DataService.releaseForTeleport(player: Player): boolean
	return releaseSession(player)
end

-- Recharge le profil d'un joueur resté sur ce serveur après une
-- libération (téléportation échouée).
function DataService.reload(player: Player)
	if sessions[player] == nil and player.Parent == Players and not shuttingDown then
		task.spawn(onPlayerAdded, player)
	end
end

-- Enregistre une fonction appelée (de façon synchrone, sans céder la main)
-- juste avant la libération d'un profil : dernier moment pour le finaliser.
-- La fonction peut modifier directement le profil reçu.
function DataService.onBeforeRelease(callback: (player: Player, profile: Profile) -> ())
	table.insert(beforeReleaseCallbacks, callback)
end

return DataService
