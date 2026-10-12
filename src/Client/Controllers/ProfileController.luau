--!strict
--[[
	ProfileController : copie locale (lecture seule) de la vue du profil.

	Le client ne modifie jamais son profil : il reçoit des instantanés du
	serveur (ProfileSync) et envoie des intentions (ex. UpdateSetting).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Localization = require(Shared.Localization)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)

local ProfileController = {}

ProfileController.Changed = Signal.new() :: Signal.Signal<Types.ProfileView>

local current: Types.ProfileView? = nil

local function apply(view: Types.ProfileView?)
	if type(view) ~= "table" then
		return
	end
	current = view
	ProfileController.Changed:Fire(view)
end

function ProfileController.init() end

function ProfileController.start()
	ClientNet.on("ProfileSync", apply)
	-- Au cas où la première synchronisation serait arrivée avant la connexion.
	task.spawn(function()
		for _ = 1, 10 do
			if current ~= nil then
				return
			end
			local view = ClientNet.invoke("RequestProfile")
			if view ~= nil then
				apply(view)
				return
			end
			task.wait(2)
		end
	end)
end

function ProfileController.get(): Types.ProfileView?
	return current
end

-- Langue effective du joueur (paramètre du profil, sinon langue du compte).
function ProfileController.language(): Localization.Language
	local setting = if current then current.settings.language else nil
	return Localization.resolve(setting, Players.LocalPlayer.LocaleId)
end

-- Raccourci de traduction dans la langue du joueur.
function ProfileController.t(key: string, params: { [string]: any }?): string
	return Localization.get(ProfileController.language(), key, params)
end

-- La clé existe-t-elle (sans avertissement) ?
function ProfileController.has(key: string): boolean
	return Localization.has(ProfileController.language(), key)
end

function ProfileController.setSetting(key: string, value: any)
	ClientNet.fire("UpdateSetting", key, value)
end

return ProfileController
