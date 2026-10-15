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
	"WeaponPoseController",
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
	"ThreatController",
	"MapController",
	"GadgetController",
	"TerminusController",
	"BazaarController",
	"AdminController",
	"RangeController",
	"TutorialController",
	"AudioController",
	"HubAmbienceController",
	"NameplateController",
	"DeployController",
	"MapEffectsController",
	"HintController",
	"TouchControlsController",
	"SettingsController",
	"DevPanelController",
}

-- Un contrôleur en échec est signalé, mais n'empêche pas les suivants de démarrer.
local function guarded(name: string, step: string, fn: () -> ()): boolean
	local ok, message = xpcall(fn, debug.traceback)
	if not ok then
		warn(`[Axiom] ÉCHEC {step} de {name} : {message}`)
	end
	return ok
end

local loaded: { { name: string, controller: any } } = {}
for _, name in order do
	guarded(name, "init", function()
		local module = Controllers:FindFirstChild(name)
		assert(module and module:IsA("ModuleScript"), `contrôleur introuvable : {name}`)
		local controller = require(module) :: any
		controller.init()
		table.insert(loaded, { name = name, controller = controller })
	end)
end

-- Écran de chargement (ReplicatedFirst) : le client est prêt une fois le profil reçu.
task.spawn(function()
	local ProfileController = require(Controllers.ProfileController) :: any
	while ProfileController.get() == nil do
		task.wait(0.2)
	end
	game:GetService("Players").LocalPlayer:SetAttribute("AxiomReady", true)
end)

for _, entry in loaded do
	guarded(entry.name, "start", entry.controller.start)
end
