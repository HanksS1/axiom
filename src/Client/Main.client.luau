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
	"RobotTurnController",
	"MapController",
	"GadgetController",
	"TerminusController",
	"BazaarController",
	"AdminController",
	"RangeController",
	"TutorialController",
	"AudioController",
	"HubAmbienceController",
	"ArenaLightingController",
	"ArenaHUDController",
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

--[[
	Démarrage dans l'ordre. Une erreur est déjà isolée par `guarded` ; une
	attente qui ne finit pas (WaitForChild sans délai…) ne doit pas non plus
	bloquer les contrôleurs suivants : chaque `start` tourne dans sa propre
	tâche, on l'attend au plus START_TIMEOUT secondes (les suivants peuvent
	compter sur lui : ordre conservé tant qu'il répond), puis on continue.
]]
local START_TIMEOUT = 5
for _, entry in loaded do
	local done = false
	task.spawn(function()
		guarded(entry.name, "start", entry.controller.start)
		done = true
	end)
	local began = os.clock()
	while not done and os.clock() - began < START_TIMEOUT do
		task.wait()
	end
	if not done then
		warn(
			`[Axiom] start de {entry.name} toujours en attente après {START_TIMEOUT} s : les contrôleurs suivants démarrent quand même`
		)
	end
end
