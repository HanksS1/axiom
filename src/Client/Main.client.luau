--!strict
--[[
	Point d'entrée du client. Même cycle que le serveur : `init()` puis `start()`.
]]

local Controllers = script.Parent.Controllers

local order = {
	"ProfileController",
	"InputController",
	"CameraController",
	"MovementController",
	"EffectsController",
	"WeaponController",
	"HUDController",
	"NotificationController",
	"InventoryController",
	"ContainerController",
	"QuickBarController",
	"MatchHUDController",
	"SpectateController",
	"PingController",
	"GadgetController",
	"TouchControlsController",
	"DevPanelController",
}

local loaded = {}
for _, name in order do
	local module = Controllers:FindFirstChild(name)
	assert(module and module:IsA("ModuleScript"), `contrôleur introuvable : {name}`)
	local controller = require(module) :: any
	controller.init()
	table.insert(loaded, controller)
end

for _, controller in loaded do
	controller.start()
end
