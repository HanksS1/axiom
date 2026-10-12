--!strict
--[[
	MatchService : déroulé d'une partie (sections 3, 4, 6.9, 6.10, 13, 15).

	1. Départ : l'équipement de chaque joueur QUITTE son profil (il est
	   « dans la partie ») ; un instantané est gardé dans `activeMatch` pour
	   être restitué si la partie ne se termine pas normalement. Sans arme,
	   le kit de base complète gratuitement l'équipement.
	2. 00:00 → 12:00 : 2 extractions sur 3 ouvertes. 12:00 : alerte d'AXIOM,
	   3e extraction, vague de robots (P4). 15:00 : Protocole de Purge.
	3. Mort : solo → fin de partie ; duo → orbe et réanimation possible.
	4. Extraction : l'équipement porté revient (loadout, puis loot à trier),
	   sauvegardé immédiatement. Score, XP, top 10 de saison, statistiques.
	5. Un joueur qui quitte une partie en cours perd son équipement (il tombe
	   dans un sac de dépouille), comme une mort.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Freeze = require(Shared.Util.Freeze)
local InventoryLogic = require(Shared.Items.InventoryLogic)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local ItemRules = require(Shared.Items.ItemRules)
local Leveling = require(Shared.Progression.Leveling)
local MatchRules = require(Shared.Match.MatchRules)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)

local Fighter = require(script.Parent.Parent.Combat.Fighter)
local ItemFactory = require(script.Parent.Parent.Inventory.ItemFactory)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)
local Uid = require(script.Parent.Parent.Util.Uid)
local ArenaService = require(script.Parent.ArenaService)
local CharacterService = require(script.Parent.CharacterService)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local GadgetService = require(script.Parent.GadgetService)
local ExtractionService = require(script.Parent.ExtractionService)
local LootService = require(script.Parent.LootService)
local MapService = require(script.Parent.MapService)
local MovementGuardService = require(script.Parent.MovementGuardService)
local ReviveService = require(script.Parent.ReviveService)

type Fighter = Fighter.Fighter
type ItemInstance = Types.ItemInstance
type Profile = Types.Profile

export type Status = "alive" | "orb" | "dead" | "extracted" | "left"
export type Outcome = "extracted" | "dead" | "left"

export type Participant = {
	player: Player,
	teamId: string,
	status: Status,
	stats: MatchRules.MatchStats,
	pendingBag: InventoryLogic.Inventory?, -- sac remis à la prochaine apparition
	reviveHealth: number?, -- PV à l'apparition (réanimation)
	finished: boolean,
}

export type StartConfig = {
	modeId: string,
	format: "solo" | "duo",
	players: { Player },
	teams: { { Player } }?, -- duo : paires imposées (sinon formées dans l'ordre)
}

local MatchService = {}

MatchService.Started = Signal.new() :: Signal.Signal<string>
MatchService.AlertTriggered = Signal.new() :: Signal.Signal<>
MatchService.PlayerFinished = Signal.new() :: Signal.Signal<Player, Outcome>
MatchService.Ended = Signal.new() :: Signal.Signal<>

local running = false
local matchId = ""
local modeId = "easy"
local format: "solo" | "duo" = "solo"
local startTime = 0
local alerted = false
local purged = false
local random = Random.new()
local participants: { [Player]: Participant } = {}
local teams: { [string]: { Player } } = {}

local state = Instance.new("Folder")
state.Name = "MatchState"

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function announce(key: string)
	ServerNet.fireAll("Announce", key)
end

local function setStatus(participant: Participant, status: Status)
	participant.status = status
	if participant.player.Parent == Players then
		ServerNet.fire("MatchStatus", participant.player, status)
	end
end

function MatchService.isRunning(): boolean
	return running
end

function MatchService.participant(player: Player): Participant?
	return participants[player]
end

function MatchService.elapsed(): number
	return if running then now() - startTime else 0
end

-- Coéquipiers vivants (hors orbes, morts et extraits) d'une équipe.
local function aliveMembers(teamId: string): { Player }
	local list = {}
	local members: { Player } = teams[teamId] or {}
	for _, player in members do
		local participant = participants[player]
		if participant and participant.status == "alive" then
			table.insert(list, player)
		end
	end
	return list
end

local function teammateOf(participant: Participant): Participant?
	local members: { Player } = teams[participant.teamId] or {}
	for _, player in members do
		if player ~= participant.player then
			return participants[player]
		end
	end
	return nil
end

-- Le kit de base complète les emplacements vides (le jeu ne bloque jamais un joueur).
local function completeWithKit(inventory: InventoryLogic.Inventory)
	local equipped = inventory.equipped
	if equipped.ranged ~= nil or equipped.melee ~= nil then
		return
	end
	local kitLoadout, kitBag = ItemFactory.createBaseKit()
	equipped.ranged = kitLoadout.ranged
	equipped.melee = kitLoadout.melee
	if equipped.backpack == nil then
		equipped.backpack = kitLoadout.backpack
	end
	for _, item in kitBag do
		InventoryLogic.store(inventory, item)
	end
end

--[[
	Applique l'issue d'une partie au profil (sans céder la main : utilisé dans
	DataService.update ET dans le crochet de départ du joueur).
	Retourne le résultat à afficher.
]]
local function applyOutcome(
	profile: Profile,
	participant: Participant,
	outcome: Outcome,
	carried: InventoryLogic.Inventory?
): { [string]: any }
	local extracted = outcome == "extracted"
	local lootValue = 0
	if extracted and carried then
		-- Équipement porté : retour dans les emplacements libres, le reste à trier.
		for _, slot in ItemCatalog.slotNames do
			local item = (carried.equipped :: any)[slot] :: ItemInstance?
			if item and not item.isKit then
				lootValue += ItemRules.value(item)
				if (profile.loadout :: any)[slot] == nil then
					(profile.loadout :: any)[slot] = item
				else
					table.insert(profile.pendingLoot, item)
				end
			end
		end
		for _, item in carried.bag do
			if not item.isKit then
				lootValue += ItemRules.value(item)
				table.insert(profile.pendingLoot, item)
			end
		end
	end
	participant.stats.lootValue = lootValue
	profile.activeMatch = nil

	local breakdown = MatchRules.score(participant.stats, modeId, extracted)
	local xpGained = Leveling.matchXp(breakdown.total)
	local levelBefore = profile.level
	profile.level, profile.xp = Leveling.addXp(profile.level, profile.xp, xpGained)

	local stats = profile.stats
	stats.matchesPlayed += 1
	if extracted then
		stats.extractions += 1
	else
		stats.deaths += 1
	end
	stats.playerKills += participant.stats.playerKills
	stats.botKills += participant.stats.botKills

	-- Classement saisonnier (top 10).
	local unix = os.time()
	local season = MatchRules.seasonAt(unix)
	if profile.season.id ~= season then
		if profile.season.id > 0 and #profile.season.top10 > 0 then
			table.insert(profile.seasonHistory, {
				id = profile.season.id,
				rank = MatchRules.rank(MatchRules.rankingScore(profile.season.top10)),
			})
		end
		profile.season = { id = season, top10 = {} }
	end
	local top, position = MatchRules.insertTopGame(profile.season.top10, {
		score = breakdown.total,
		mode = modeId,
		date = unix,
	})
	profile.season.top10 = top
	if breakdown.total > (profile.bestScoreByMode[modeId] or 0) then
		profile.bestScoreByMode[modeId] = breakdown.total
	end

	return {
		outcome = outcome,
		mode = modeId,
		duration = math.floor(MatchService.elapsed()),
		kills = {
			players = participant.stats.playerKills,
			bots = participant.stats.botKills,
			robotPoints = participant.stats.robotPoints,
		},
		lootValue = lootValue,
		score = breakdown,
		topPosition = position,
		xpGained = xpGained,
		levelBefore = levelBefore,
		level = profile.level,
		xp = profile.xp,
		xpToNext = Leveling.xpToNext(profile.level),
	}
end

local function checkEnd()
	if not running then
		return
	end
	for _, participant in participants do
		if not participant.finished then
			return
		end
	end
	MatchService.finish()
end

local function finalize(participant: Participant, outcome: Outcome, carried: InventoryLogic.Inventory?)
	if participant.finished then
		return
	end
	participant.finished = true
	local player = participant.player
	local result: { [string]: any }? = nil
	DataService.update(player, function(profile)
		result = applyOutcome(profile, participant, outcome, carried)
	end)
	task.spawn(DataService.saveNow, player) -- « sauvegardé immédiatement »
	if result and player.Parent == Players then
		ServerNet.fire("MatchResult", player, result)
	end
	MatchService.PlayerFinished:Fire(player, outcome)
	checkEnd()
end

-- Retire et renvoie le sac porté par un combattant (le combattant n'a plus rien).
local function takeCarried(fighter: Fighter?): InventoryLogic.Inventory?
	if fighter == nil or fighter.bag == nil then
		return nil
	end
	local bag = fighter.bag :: InventoryLogic.Inventory
	local carried = InventoryLogic.new(bag.equipped, bag.bag)
	bag.equipped = {}
	bag.bag = {}
	return carried
end

local function extract(participant: Participant)
	if participant.status ~= "alive" then
		return
	end
	local player = participant.player
	local fighter = CombatService.getFighter(player)
	local carried = takeCarried(fighter)
	setStatus(participant, "extracted")
	ServerNet.fireAll("Extracted", player.UserId, if fighter then fighter.root.Position else Vector3.zero)
	-- Si le coéquipier était en orbe, elle est perdue (extraction seul).
	local teammate = teammateOf(participant)
	if teammate and teammate.status == "orb" then
		ReviveService.abandonFor(player)
	end
	task.delay(0.5, function()
		if player.Character then
			player.Character:Destroy()
		end
	end)
	finalize(participant, "extracted", carried)
end

local function spawnPlayer(participant: Participant, cframe: CFrame)
	local player = participant.player
	if player.Parent ~= Players then
		return
	end
	player:LoadCharacter()
	local character = player.Character
	if character then
		character:PivotTo(cframe)
		MovementGuardService.reset(player)
	end
	local health = participant.reviveHealth
	if health then
		participant.reviveHealth = nil
		task.spawn(function()
			for _ = 1, 50 do
				local fighter = CombatService.getFighter(player)
				if fighter and fighter.character == player.Character then
					CombatService.setHealth(fighter, health)
					return
				end
				task.wait(0.1)
			end
		end)
	end
end

-- Mort d'un combattant pendant la partie (remplace la réapparition de l'arène).
local function onDeath(fighter: Fighter, _killer: Fighter?)
	local player = fighter.player
	local participant = if player then participants[player] else nil
	local character = fighter.character
	task.delay(Config.Combat.death.disintegrateDuration, function()
		if fighter.kind ~= "object" and character.Parent then
			character:Destroy()
		end
	end)
	if participant == nil or participant.status ~= "alive" then
		return
	end
	local teammate = teammateOf(participant)
	if format == "duo" and teammate and teammate.status == "alive" then
		setStatus(participant, "orb")
		ReviveService.begin(participant.player, teammate.player, participant.teamId, fighter.root.Position, random)
		return
	end
	setStatus(participant, "dead")
	-- Le coéquipier qui attendait une réanimation la perd.
	ReviveService.abandonFor(participant.player)
	task.delay(Config.Match.deathScreenDelay, function()
		finalize(participant, "dead", nil)
	end)
end

-- Crédits de kills (score) et fil des éliminations.
local function onFighterDied(victim: Fighter, killer: Fighter?)
	if not running then
		return
	end
	if killer and killer.player and killer ~= victim and not Fighter.sameTeam(killer, victim) then
		local participant = participants[killer.player]
		if participant then
			if victim.kind == "player" then
				participant.stats.playerKills += 1
			elseif victim.kind == "bot" then
				participant.stats.botKills += 1
			elseif victim.kind == "robot" and victim.robotId then
				local def = Config.Robots.byId[victim.robotId]
				participant.stats.robotPoints += if def then def.scorePoints else 0
			end
		end
	end
	if victim.kind == "player" or victim.kind == "bot" then
		local victimName = if victim.player then victim.player.DisplayName else victim.character.Name
		local killerName = if killer and killer.player
			then killer.player.DisplayName
			elseif killer and killer.kind == "bot" then killer.character.Name
			else nil
		ServerNet.fireAll("KillFeed", victimName, killerName, if killer then killer.kind else nil)
	end
end

-- Protocole de Purge : tous les combattants encore présents meurent.
local function purge()
	purged = true
	announce("axiom.purge")
	for _, fighter in CombatService.allFighters() do
		if fighter.kind ~= "object" and Fighter.isAlive(fighter) then
			CombatService.kill(fighter)
		end
	end
	-- Les orbes en attente sont perdues.
	for _, participant in participants do
		if participant.status == "orb" then
			ReviveService.abandonFor(participant.player)
		end
	end
	task.delay(Config.Match.deathScreenDelay + 1, function()
		for _, participant in participants do
			if not participant.finished then
				setStatus(participant, "dead")
				finalize(participant, "dead", nil)
			end
		end
		checkEnd()
	end)
end

local function tick()
	if not running then
		return
	end
	local elapsed = MatchService.elapsed()
	local phase = MatchRules.phase(elapsed)
	if not alerted and (phase == "alert" or phase == "final" or phase == "purge") then
		alerted = true
		ExtractionService.openAll()
		announce("axiom.alert")
		MatchService.AlertTriggered:Fire()
	end
	if not purged and phase == "purge" then
		purge()
	end
end

--[[
	Lance une partie avec les joueurs indiqués (serveur de partie en P6 ;
	en Studio, depuis le panneau DEV dans l'arène).
]]
function MatchService.begin(config: StartConfig): boolean
	if running or Config.Modes.byId[config.modeId] == nil then
		return false
	end
	running = true
	matchId = Uid.new()
	modeId = config.modeId
	format = config.format
	alerted = false
	purged = false
	random = Random.new()
	table.clear(participants)
	table.clear(teams)

	-- Équipes : solo = une équipe par joueur ; duo = paires.
	local groups: { { Player } } = config.teams or {}
	if config.teams == nil then
		local size = if format == "duo" then 2 else 1
		local current: { Player } = {}
		for _, player in config.players do
			table.insert(current, player)
			if #current == size then
				table.insert(groups, current)
				current = {}
			end
		end
		if #current > 0 then
			table.insert(groups, current)
		end
	end
	for index, members in groups do
		local teamId = "t" .. index
		teams[teamId] = members
		for _, player in members do
			player:SetAttribute("TeamId", teamId)
			participants[player] = {
				player = player,
				teamId = teamId,
				status = "alive",
				stats = { playerKills = 0, botKills = 0, robotPoints = 0, lootValue = 0 },
				pendingBag = nil,
				reviveHealth = nil,
				finished = false,
			}
		end
	end

	-- L'équipement quitte les profils (instantané de secours dans activeMatch).
	for player, participant in participants do
		local matchBag: InventoryLogic.Inventory? = nil
		local ok = DataService.update(player, function(profile)
			local loadout = profile.loadout
			local bag = profile.bag
			profile.activeMatch = {
				id = matchId,
				startedAt = os.time(),
				mode = modeId,
				insurance = nil,
				snapshot = { loadout = Freeze.copy(loadout), bag = Freeze.copy(bag) },
			}
			matchBag = InventoryLogic.new(Freeze.copy(loadout), Freeze.copy(bag))
			profile.loadout = {}
			profile.bag = {}
		end)
		if not ok or matchBag == nil then
			-- Profil indisponible : le joueur ne participe pas.
			participants[player] = nil
			player:SetAttribute("TeamId", nil)
			continue
		end
		completeWithKit(matchBag :: InventoryLogic.Inventory)
		participant.pendingBag = matchBag
		task.spawn(DataService.saveNow, player)
	end

	-- Carte : caisses, extractions, mode de loot.
	ArenaService.setSandbox(false)
	GadgetService.reset()
	LootService.clearAll()
	LootService.modeId = modeId
	for _, marker in MapService.crateSpawns() do
		LootService.spawnCrate(marker.cframe, marker.attributes.CrateType or "supply")
	end
	ExtractionService.setup(random, aliveMembers)

	CharacterService.setLoadoutProvider(function(player)
		local participant = participants[player]
		if participant == nil or participant.status ~= "alive" then
			return nil
		end
		local bag = participant.pendingBag
		participant.pendingBag = nil
		if bag == nil then
			-- Réanimation : le kit de base (l'équipement d'origine est dans le sac de dépouille).
			local kitLoadout, kitBag = ItemFactory.createBaseKit()
			bag = InventoryLogic.new(kitLoadout, kitBag)
		end
		return bag
	end)
	CombatService.setDeathHandler(onDeath)
	Players.CharacterAutoLoads = false

	-- Déploiement : chaque équipe sur un point de départ différent, en bordure.
	local spawns = MapService.deploySpawns()
	for index = #spawns, 2, -1 do
		local swap = random:NextInteger(1, index)
		spawns[index], spawns[swap] = spawns[swap], spawns[index]
	end
	local teamIndex = 0
	for _, members in teams do
		teamIndex += 1
		local marker = spawns[(teamIndex - 1) % math.max(1, #spawns) + 1]
		local base = if marker then marker.cframe else CFrame.new(0, 5, 0)
		for memberIndex, player in members do
			local participant = participants[player]
			if participant then
				local offset = CFrame.new((memberIndex - 1) * 4, 0, 0)
				task.spawn(spawnPlayer, participant, base * offset)
				setStatus(participant, "alive")
			end
		end
	end

	startTime = now()
	state:SetAttribute("Running", true)
	state:SetAttribute("StartTime", startTime)
	state:SetAttribute("Mode", modeId)
	state:SetAttribute("Format", format)
	announce("axiom.start")
	MatchService.Started:Fire(matchId)
	return true
end

-- Fin de partie : nettoyage puis retour (arène de test en Studio ; Terminus en P6).
function MatchService.finish()
	if not running then
		return
	end
	running = false
	state:SetAttribute("Running", false)
	for _, participant in participants do
		if not participant.finished then
			finalize(participant, "dead", nil)
		end
	end
	ExtractionService.clear()
	ReviveService.clearAll()
	CombatService.setDeathHandler(nil)
	CharacterService.setLoadoutProvider(nil)
	MatchService.Ended:Fire()

	task.delay(Config.Match.returnDelay, function()
		if running then
			return
		end
		LootService.clearAll()
		GadgetService.reset()
		Players.CharacterAutoLoads = true
		for player in participants do
			player:SetAttribute("TeamId", nil)
			if player.Parent == Players then
				ServerNet.fire("MatchStatus", player, "none")
				task.spawn(function()
					player:LoadCharacter()
				end)
			end
		end
		table.clear(participants)
		table.clear(teams)
		ArenaService.setSandbox(true)
		ArenaService.spawnSandboxCrates()
	end)
end

-- Avance le chrono (outil de test Studio : vérifier l'alerte et la Purge).
function MatchService.skip(seconds: number)
	if running then
		startTime -= seconds
		state:SetAttribute("StartTime", startTime)
	end
end

function MatchService.init()
	state.Parent = ReplicatedStorage

	ExtractionService.TeamExtracted:Connect(function(_zoneId, _teamId, members)
		for _, player in members do
			local participant = participants[player]
			if participant then
				extract(participant)
			end
		end
	end)

	ReviveService.Revived:Connect(function(player, cframe)
		local participant = participants[player]
		if participant == nil or participant.status ~= "orb" then
			return
		end
		setStatus(participant, "alive")
		participant.reviveHealth = Config.Combat.revive.reviveHealth
		task.spawn(spawnPlayer, participant, cframe)
	end)

	ReviveService.Lost:Connect(function(player)
		local participant = participants[player]
		if participant and participant.status == "orb" then
			setStatus(participant, "dead")
			finalize(participant, "dead", nil)
		end
	end)

	CombatService.FighterDied:Connect(onFighterDied)

	-- Partie non terminée (serveur planté, téléportation échouée…) : à la
	-- connexion hors de cette partie, l'équipement emporté est restitué.
	DataService.ProfileLoaded:Connect(function(player, profile)
		local active = profile.activeMatch
		if active == nil or (running and active.id == matchId) then
			return
		end
		DataService.update(player, function(current)
			local match = current.activeMatch
			if match == nil then
				return
			end
			for _, slot in ItemCatalog.slotNames do
				local item = (match.snapshot.loadout :: any)[slot] :: ItemInstance?
				if item then
					if (current.loadout :: any)[slot] == nil then
						(current.loadout :: any)[slot] = item
					else
						table.insert(current.pendingLoot, item)
					end
				end
			end
			for _, item in match.snapshot.bag do
				table.insert(current.bag, item)
			end
			current.activeMatch = nil
		end)
	end)

	-- Départ en cours de partie : le sac tombe au sol, la partie est perdue.
	CombatService.PlayerLeaving:Connect(function(fighter)
		local player = fighter.player
		local participant = if player then participants[player] else nil
		if participant and participant.status == "alive" and Fighter.isAlive(fighter) then
			local carried = takeCarried(fighter)
			if carried then
				LootService.spawnDeathBag(
					fighter.root.Position,
					InventoryLogic.drainAll(carried),
					player and player.DisplayName
				)
			end
		end
	end)
	DataService.onBeforeRelease(function(player, profile)
		local participant = participants[player]
		if participant and running and not participant.finished then
			participant.finished = true
			setStatus(participant, "left")
			applyOutcome(profile, participant, "left", nil)
			ReviveService.abandonFor(player)
			task.defer(checkEnd)
		end
	end)
end

function MatchService.start()
	RunService.Heartbeat:Connect(tick)
end

return MatchService
