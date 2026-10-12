--!strict
--[[
	Sounds : groupes de sons (volumes séparés, section 17.3, écran 17) et
	petit clic électronique des actions d'interface (17.1).

	Groupes : Music, Effects, Axiom (voix d'AXIOM), Voice. Le chat vocal
	Roblox n'est pas réglable par script : son volume se règle dans le menu
	Roblox ; le groupe Voice est réservé aux voix enregistrées du jeu.
]]

local SoundService = game:GetService("SoundService")

local Sounds = {}

local GROUPS = { "Music", "Effects", "Axiom", "Voice" }
local CLICK_ID = "rbxasset://sounds/electronicpingshort.wav"

local groups: { [string]: SoundGroup } = {}
local click: Sound? = nil

function Sounds.group(name: string): SoundGroup
	local existing = groups[name]
	if existing then
		return existing
	end
	local group = Instance.new("SoundGroup")
	group.Name = "Axiom" .. name
	group.Parent = SoundService
	groups[name] = group
	return group
end

function Sounds.setVolume(name: string, volume: number)
	Sounds.group(name).Volume = math.clamp(volume, 0, 1)
end

function Sounds.init()
	for _, name in GROUPS do
		Sounds.group(name)
	end
end

-- Clic électronique (boutons, onglets).
function Sounds.click()
	local sound = click
	if sound == nil then
		local created = Instance.new("Sound")
		created.Name = "UIClick"
		created.SoundId = CLICK_ID
		created.Volume = 0.25
		created.PlaybackSpeed = 1.6
		created.SoundGroup = Sounds.group("Effects")
		created.Parent = SoundService
		click = created
		sound = created
	end
	(sound :: Sound):Play()
end

return Sounds
