--!strict
--[[
	ArenaLightingController : éclairage de l'Arène FFA, posé par CE client
	quand sa caméra est dans l'arène, retiré à la sortie (Shared/Visuals/
	LightingOverlay). Le Terminus voisin, sur le même serveur, garde son
	éclairage : aucun autre joueur n'est touché.

	Réglages : Config.Arena.lighting (lisibilité d'abord). Pendant une partie
	sur le même serveur, les effets d'ambiance de la carte (brume, halo,
	étalonnage) sont neutralisés localement dans l'arène.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Zone = require(Shared.Match.Zone)
local LightingOverlay = require(Shared.Visuals.LightingOverlay)

local ArenaLightingController = {}

-- Vérification de la position de la caméra (secondes) : entrée et sortie de l'arène.
local CHECK_INTERVAL = 0.25
-- Effets d'ambiance posés par le serveur pour une carte (MapRuntimeService).
local MOOD = { MapAtmosphere = true, MapBloom = true, MapColor = true }

local overlay = LightingOverlay.new(Config.Arena.lighting)
local changed: RBXScriptConnection? = nil
local moodAdded: RBXScriptConnection? = nil
-- Effets d'ambiance neutralisés : valeur d'origine à rétablir.
local neutralized: { [Instance]: any } = {}

local function write(values: { [string]: any })
	for property, value in values do
		(Lighting :: any)[property] = value
	end
end

local function neutralize(effect: Instance)
	if not Config.Arena.neutralizeMood or not MOOD[effect.Name] or neutralized[effect] ~= nil then
		return
	end
	if effect:IsA("Atmosphere") then
		neutralized[effect] = effect.Density
		effect.Density = 0
	elseif effect:IsA("PostEffect") then
		neutralized[effect] = effect.Enabled
		effect.Enabled = false
	end
end

local function restoreMood()
	for effect, value in neutralized do
		if effect.Parent ~= nil then
			if effect:IsA("Atmosphere") then
				effect.Density = value
			elseif effect:IsA("PostEffect") then
				effect.Enabled = value
			end
		end
	end
	table.clear(neutralized)
end

local function enter()
	write(LightingOverlay.enter(overlay, function(property)
		return (Lighting :: any)[property]
	end))
	-- Réplication d'un changement du serveur (partie qui démarre) : on garde sa
	-- valeur pour la sortie et on remet celle de l'arène.
	changed = Lighting.Changed:Connect(function(property)
		if LightingOverlay.serverChanged(overlay, property, (Lighting :: any)[property]) then
			(Lighting :: any)[property] = overlay.target[property]
		end
	end)
	for _, child in Lighting:GetChildren() do
		neutralize(child)
	end
	moodAdded = Lighting.ChildAdded:Connect(neutralize)
end

local function leave()
	if changed then
		changed:Disconnect()
		changed = nil
	end
	if moodAdded then
		moodAdded:Disconnect()
		moodAdded = nil
	end
	write(LightingOverlay.exit(overlay))
	restoreMood()
end

local function cameraInArena(): boolean
	local camera = Workspace.CurrentCamera
	return camera ~= nil and Workspace:FindFirstChild("Arena") ~= nil and Zone.inArena(camera.CFrame.Position)
end

function ArenaLightingController.init() end

function ArenaLightingController.start()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < CHECK_INTERVAL then
			return
		end
		elapsed = 0
		local inside = cameraInArena()
		if inside and not overlay.active then
			enter()
		elseif not inside and overlay.active then
			leave()
		end
	end)
end

return ArenaLightingController
