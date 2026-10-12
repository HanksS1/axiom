--!strict
--[[
	MockDataStore : DataStore en mémoire, même contrat que UpdateAsync.
	Utilisé par les tests et, en Studio, quand les API DataStore sont
	désactivées. Les valeurs sont copiées en profondeur (comme une vraie
	sérialisation) pour qu'aucune référence ne fuie entre appels.
]]

local MockDataStore = {}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for k, v in value do
		result[deepCopy(k)] = deepCopy(v)
	end
	return result
end

export type MockDataStore = {
	UpdateAsync: (self: MockDataStore, key: string, transform: (any) -> (any, any?)) -> any,
	GetAsync: (self: MockDataStore, key: string) -> any,
	SetRaw: (self: MockDataStore, key: string, value: any) -> (),
	-- Injection de pannes pour les tests : nombre de prochains appels qui échouent.
	failNext: number,
	writes: number,
}

function MockDataStore.new(): MockDataStore
	local data: { [string]: any } = {}
	local object = { failNext = 0, writes = 0 } :: any

	function object:UpdateAsync(key: string, transform: (any) -> (any, any?)): any
		if self.failNext > 0 then
			self.failNext -= 1
			error("MockDataStore : panne simulée")
		end
		local current = deepCopy(data[key])
		local newValue = transform(current)
		if newValue == nil then
			return nil
		end
		data[key] = deepCopy(newValue)
		self.writes += 1
		return deepCopy(newValue)
	end

	function object:GetAsync(key: string): any
		return deepCopy(data[key])
	end

	function object:SetRaw(key: string, value: any)
		data[key] = deepCopy(value)
	end

	return object :: MockDataStore
end

return MockDataStore
