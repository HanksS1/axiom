--!strict
--[[
	TransactionLog : journal des transactions importantes (section 19.4) —
	achats, ventes, réparations, caisses, Robux — pour pouvoir enquêter.

	Les entrées sont regroupées et écrites périodiquement dans un DataStore
	dédié (une clé par joueur et par jour, 500 entrées au plus par clé).
	En cas d'indisponibilité (Studio sans API), elles sont seulement affichées
	dans la sortie serveur.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local TransactionLog = {}

local MAX_PER_KEY = 500
local FLUSH_INTERVAL = 60

local pending: { [string]: { any } } = {}
local store: any = nil

local function storeOrNil(): any
	if store == nil then
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore("AxiomTransactions_v1")
		end)
		store = if ok then result else false
	end
	return if store then store else nil
end

-- Entrée pour un identifiant de joueur (le joueur peut déjà être parti : journal
-- de persistance, écrit pendant la libération du profil).
function TransactionLog.recordUser(userId: number, kind: string, detail: any?)
	local day = os.date("!%Y%m%d") :: string
	local key = `log_{userId}_{day}`
	local entry = {
		t = os.time(),
		k = kind,
		d = detail,
	}
	pending[key] = pending[key] or {}
	table.insert(pending[key], entry)
end

function TransactionLog.record(player: Player, kind: string, detail: any?)
	if RunService:IsStudio() then
		print(`[Transaction] {player.Name} {kind} {HttpService:JSONEncode(detail or {})}`)
	end
	TransactionLog.recordUser(player.UserId, kind, detail)
end

function TransactionLog.flush()
	local dataStore = storeOrNil()
	local batch = pending
	pending = {}
	if dataStore == nil then
		return
	end
	for key, entries in batch do
		pcall(function()
			dataStore:UpdateAsync(key, function(current: any)
				local list = if type(current) == "table" then current else {}
				for _, entry in entries do
					table.insert(list, entry)
				end
				while #list > MAX_PER_KEY do
					table.remove(list, 1)
				end
				return list
			end)
		end)
	end
end

task.spawn(function()
	while true do
		task.wait(FLUSH_INTERVAL)
		TransactionLog.flush()
	end
end)

game:BindToClose(function()
	TransactionLog.flush()
end)

return TransactionLog
