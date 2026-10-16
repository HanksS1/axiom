--!strict
--[[
	AudioController : audio dynamique (section 18).

	- Musique à 4 couches en fondu enchaîné : Terminus → exploration →
	  combat (dégâts infligés ou reçus, redescend après 8 s) → alerte (à
	  partir de 12:00, tempo qui accélère jusqu'à la Purge).
	- Voix d'AXIOM dans la langue du joueur, à chaque annonce.
	- Tirs des autres joueurs et alarmes de casiers SPATIALISÉS (information
	  tactique), avec une réserve de sources réutilisées (aucune création
	  d'instance par tir).
	- Sons d'interface : touche, tête, dégâts reçus, parade, extraction.

	Les identifiants viennent de Config.Audio ; un identifiant vide coupe
	simplement le son. Les volumes suivent les groupes réglés dans les
	paramètres (Music, Effects, Axiom).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Sounds = require(script.Parent.Parent.UI.Sounds)
local MatchHUDController = require(script.Parent.MatchHUDController)
local ProfileController = require(script.Parent.ProfileController)
local WeaponController = require(script.Parent.WeaponController)

local AudioController = {}

local A = Config.Audio
local Match = Config.Match

type Layer = "hub" | "exploration" | "combat" | "alert"
type Source = { attachment: Attachment, sound: Sound }

local layers: { [string]: Sound } = {}
local levels: { [string]: number } = {}
local lastCombatAt = -math.huge
local alertSince: number? = nil
local voice: Sound
local pool: { Source } = {}
local poolIndex = 0
local uiSounds: { [string]: Sound } = {}

-- Musique de partie : sur le terrain, et aussi mort en attendant la fin (spectateur).
local function inMatch(): boolean
	return MatchHUDController.isPlaying() or MatchHUDController.status() == "dead"
end

-- Couche voulue à cet instant.
local function wanted(): Layer
	if not inMatch() then
		return "hub"
	end
	if alertSince ~= nil then
		return "alert"
	end
	if os.clock() - lastCombatAt < A.music.combatHold then
		return "combat"
	end
	return "exploration"
end

local function makeLayer(name: string, def: { id: string, volume: number })
	if def.id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "Music_" .. name
	sound.SoundId = def.id
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = Sounds.group("Music")
	sound.Parent = SoundService
	layers[name] = sound
	levels[name] = 0
end

local function updateMusic(dt: number)
	local target = wanted()
	local step = dt / math.max(0.05, A.music.fadeTime)
	for name, sound in layers do
		local goal = if name == target then 1 else 0
		local level = levels[name]
		level = if level < goal then math.min(goal, level + step) else math.max(goal, level - step)
		levels[name] = level
		local def = (A.music.layers :: any)[name]
		sound.Volume = level * def.volume
		if level > 0 and not sound.IsPlaying then
			sound:Play()
		elseif level <= 0 and sound.IsPlaying then
			sound:Pause()
		end
	end
	-- Alerte : le tempo accélère jusqu'à la Purge.
	local alert = layers.alert
	local since = alertSince
	if alert and since then
		local span = math.max(1, Match.duration - Match.alertAt)
		local progress = math.clamp((os.clock() - since) / span, 0, 1)
		alert.PlaybackSpeed = A.music.alertPitchStart + (A.music.alertPitchEnd - A.music.alertPitchStart) * progress
	end
end

-- Sources spatialisées réutilisées (tirs, alarmes).
local function playAt(position: Vector3, id: string, volume: number, rollOffMax: number?)
	if id == "" then
		return
	end
	poolIndex = poolIndex % #pool + 1
	local source = pool[poolIndex]
	source.attachment.WorldPosition = position
	local sound = source.sound
	sound:Stop()
	sound.SoundId = id
	sound.Volume = volume
	sound.RollOffMaxDistance = rollOffMax or A.spatial.rollOffMax
	sound:Play()
end

local function playUi(name: string)
	local sound = uiSounds[name]
	if sound then
		sound:Play()
	end
end

local function weaponSound(itemId: string?): (string, number)
	local def = if itemId then (A.weapons :: any)[itemId] else nil
	if def then
		return def.fire, def.volume
	end
	return "", 0
end

function AudioController.init() end

function AudioController.start()
	for name, def in A.music.layers :: { [string]: any } do
		makeLayer(name, def)
	end

	voice = Instance.new("Sound")
	voice.Name = "AxiomVoice"
	voice.SoundGroup = Sounds.group("Axiom")
	voice.Parent = SoundService

	for name, def in A.sfx :: { [string]: any } do
		if def.id ~= "" then
			local sound = Instance.new("Sound")
			sound.Name = "Sfx_" .. name
			sound.SoundId = def.id
			sound.Volume = def.volume
			sound.SoundGroup = Sounds.group("Effects")
			sound.Parent = SoundService
			uiSounds[name] = sound
		end
	end

	for index = 1, A.spatial.pool do
		local attachment = Instance.new("Attachment")
		attachment.Name = "AudioSource" .. index
		attachment.Parent = Workspace.Terrain
		local sound = Instance.new("Sound")
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = A.spatial.rollOffMin
		sound.RollOffMaxDistance = A.spatial.rollOffMax
		sound.SoundGroup = Sounds.group("Effects")
		sound.Parent = attachment
		table.insert(pool, { attachment = attachment, sound = sound })
	end

	-- Combat : dégâts infligés ou reçus.
	ClientNet.on("HitConfirm", function(isHead: boolean)
		lastCombatAt = os.clock()
		playUi(if isHead then "headshot" else "hitMarker")
	end)
	ClientNet.on("DamageTaken", function()
		lastCombatAt = os.clock()
		playUi("damageTaken")
	end)
	ClientNet.on("ParryResult", function(result: string)
		if result == "perfect" then
			playUi("parry")
		end
	end)
	ClientNet.on("Extracted", function()
		playUi("extracted")
	end)

	-- Annonces d'AXIOM : voix dans la langue du joueur ; l'alerte lance la couche d'alerte.
	ClientNet.on("Announce", function(key: string)
		if key == "axiom.alert" then
			alertSince = os.clock()
		end
		local lines = (A.voice :: any)[key]
		local id = if lines then lines[ProfileController.language()] or "" else ""
		if id ~= "" then
			voice:Stop()
			voice.SoundId = id
			voice:Play()
		end
	end)
	MatchHUDController.StatusChanged:Connect(function(status)
		if status ~= "alive" and status ~= "orb" and status ~= "dead" then
			alertSince = nil
		end
	end)

	-- Tirs : les siens (non spatialisés, plus proches) et ceux des autres (spatialisés).
	WeaponController.Fired:Connect(function()
		local id, volume = weaponSound(WeaponController.snapshot().rangedId)
		if id ~= "" then
			local camera = Workspace.CurrentCamera
			playAt(camera.CFrame.Position, id, volume)
		end
	end)
	ClientNet.on("ShotFired", function(_shooter: Player?, itemId: string, origin: Vector3)
		local id, volume = weaponSound(itemId)
		playAt(origin, id, volume)
	end)
	ClientNet.on("LootAlarm", function(position: Vector3, radius: number)
		local def = A.sfx.lootAlarm
		playAt(position, def.id, def.volume, math.max(radius, A.spatial.rollOffMin))
	end)

	RunService.Heartbeat:Connect(updateMusic)
end

return AudioController
