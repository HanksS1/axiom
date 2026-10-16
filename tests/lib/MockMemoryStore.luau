--!nocheck
--[[
	MockMemoryStore : MemoryStoreService simulé pour les tests (SortedMap en
	mémoire, expiration sur une horloge réglable, pannes injectables).

	Usage :
		local store = MockMemoryStore.new()
		H.setService("MemoryStoreService", store)
		store.now = 100        -- horloge des expirations (secondes)
		store.failing = true   -- toutes les opérations lèvent une erreur
]]

local MockMemoryStore = {}

local function newMap(store)
	local entries = {} -- clé → { value, sortKey, expires }
	local sortedMap = {}

	local function check()
		if store.failing then
			error("MemoryStore indisponible (simulé)")
		end
	end

	local function alive(key)
		local entry = entries[key]
		if entry and entry.expires <= store.now then
			entries[key] = nil
			return nil
		end
		return entry
	end

	function sortedMap:SetAsync(key, value, expiration, sortKey)
		check()
		entries[key] = { value = value, sortKey = sortKey, expires = store.now + expiration }
		return true
	end

	function sortedMap:GetAsync(key)
		check()
		local entry = alive(key)
		return if entry then entry.value else nil
	end

	function sortedMap:UpdateAsync(key, transform, expiration)
		check()
		local entry = alive(key)
		local value, sortKey = transform(if entry then entry.value else nil, if entry then entry.sortKey else nil)
		if value == nil then
			return nil -- transformation annulée : rien n'est écrit
		end
		entries[key] = {
			value = value,
			sortKey = if sortKey ~= nil then sortKey else (entry and entry.sortKey),
			expires = store.now + expiration,
		}
		return value
	end

	function sortedMap:RemoveAsync(key)
		check()
		entries[key] = nil
	end

	function sortedMap:GetRangeAsync(_direction, count)
		check()
		local list = {}
		for key in entries do
			local entry = alive(key)
			if entry then
				table.insert(list, { key = key, value = entry.value, sortKey = entry.sortKey })
			end
		end
		table.sort(list, function(a, b)
			local sa, sb = a.sortKey or 0, b.sortKey or 0
			if sa ~= sb then
				return sa < sb
			end
			return a.key < b.key
		end)
		local result = {}
		for index = 1, math.min(count, #list) do
			table.insert(result, { key = list[index].key, value = list[index].value })
		end
		return result
	end

	return sortedMap
end

function MockMemoryStore.new()
	local store = { now = 0, failing = false, maps = {} }
	function store:GetSortedMap(name)
		local existing = self.maps[name]
		if existing == nil then
			existing = newMap(self)
			self.maps[name] = existing
		end
		return existing
	end
	return store
end

return MockMemoryStore
