--!strict
--[[
	Point d'entrée du serveur.

	Chaque service expose `init()` (préparation, aucune attente) puis
	`start()` (connexions, boucles). L'ordre ci-dessous est l'ordre
	d'initialisation : un service peut utiliser ceux qui le précèdent.
]]

local ServerNet = require(script.Parent.Net.ServerNet)

local Services = script.Parent.Services

local order = {
	"DataService",
	"CombatService",
	"LootService",
	"InventoryService",
	"CharacterService",
	"MovementGuardService",
	"MapService",
	"ArenaService",
	"GadgetService",
	"ExtractionService",
	"ReviveService",
	"PingService",
	"RobotService",
	"MercenaryService",
	"MapRuntimeService",
	"MatchService",
	"PartyService",
	"QueueService",
	"EconomyService",
	"MonetizationService",
	"LeaderboardService",
	"RangeService",
	"TutorialService",
	"HubService",
	"MatchServerService",
	"DevService",
}

-- Un service en échec est signalé, mais n'empêche pas les suivants de démarrer
-- (sinon une seule erreur prive le serveur du Terminus, des parties, etc.).
local failures = 0
local function guarded(name: string, step: string, fn: () -> ())
	local ok, message = xpcall(fn, debug.traceback)
	if not ok then
		failures += 1
		warn(`[Axiom] ÉCHEC {step} de {name} : {message}`)
	end
end

ServerNet.init()

local loaded: { { name: string, service: any } } = {}
for _, name in order do
	guarded(name, "init", function()
		local module = Services:FindFirstChild(name)
		assert(module and module:IsA("ModuleScript"), `service introuvable : {name}`)
		local service = require(module) :: any
		service.init()
		table.insert(loaded, { name = name, service = service })
	end)
end

guarded("ServerNet", "contrôle des remotes", ServerNet.assertAllHandled)

for _, entry in loaded do
	guarded(entry.name, "start", entry.service.start)
end

if failures == 0 then
	print("[Axiom] serveur prêt")
else
	warn(`[Axiom] serveur démarré avec {failures} échec(s) : voir les messages « ÉCHEC » ci-dessus`)
end
