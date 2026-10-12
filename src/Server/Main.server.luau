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
	"MatchService",
	"EconomyService",
	"HubService",
	"DevService",
}

ServerNet.init()

local loaded = {}
for _, name in order do
	local module = Services:FindFirstChild(name)
	assert(module and module:IsA("ModuleScript"), `service introuvable : {name}`)
	local service = require(module) :: any
	service.init()
	table.insert(loaded, service)
end

ServerNet.assertAllHandled()

for _, service in loaded do
	service.start()
end

print("[Axiom] serveur prêt")
