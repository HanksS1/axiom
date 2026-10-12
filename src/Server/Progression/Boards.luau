--!strict
--[[
	Boards : classements persistants (section 15.4).

	- submit  : ne garde que le MEILLEUR score d'un joueur (UpdateAsync qui
	  n'écrit jamais une valeur plus basse) ; aucune écriture si le score
	  connu est déjà au moins aussi haut.
	- top     : les N premières entrées, mises en cache (une lecture par
	  classement et par minute et par serveur, quel que soit le nombre de
	  demandes) ; les lectures simultanées attendent la première.
	- get     : score d'un joueur, mis en cache.

	Le stockage est injecté : OrderedDataStore réel, ou Boards.memoryStore()
	(tests, Studio sans accès aux API). Toutes les erreurs de stockage sont
	absorbées : un classement indisponible renvoie nil, jamais une erreur.
]]

local Boards = {}

export type Entry = { userId: number, score: number }

export type StoreLike = {
	UpdateAsync: (self: any, key: string, transform: (any) -> any) -> any,
	GetAsync: (self: any, key: string) -> any,
	GetSortedAsync: (self: any, ascending: boolean, pageSize: number) -> any,
}

export type Board = {
	submit: (self: Board, userId: number, score: number) -> boolean,
	top: (self: Board, count: number) -> { Entry }?,
	get: (self: Board, userId: number) -> number?,
}

export type Options = {
	clock: () -> number,
	topCacheSeconds: number,
	scoreCacheSeconds: number,
	-- Attente pendant qu'une autre lecture du même classement est en cours.
	wait: ((seconds: number) -> ())?,
}

local MAX_PAGE = 100
local WAIT_STEP = 0.1
local WAIT_LIMIT = 100 -- 10 s

-- Stockage trié en mémoire, même contrat qu'un OrderedDataStore.
function Boards.memoryStore(): StoreLike
	local data: { [string]: number } = {}
	local store = {} :: any

	function store:UpdateAsync(key: string, transform: (any) -> any): any
		local result = transform(data[key])
		if result ~= nil then
			assert(type(result) == "number" and result == math.floor(result), "valeur entière attendue")
			data[key] = result
			return result
		end
		return data[key]
	end

	function store:GetAsync(key: string): any
		return data[key]
	end

	function store:GetSortedAsync(ascending: boolean, pageSize: number): any
		local sorted = {}
		for key, value in data do
			table.insert(sorted, { key = key, value = value })
		end
		table.sort(sorted, function(a, b)
			if a.value ~= b.value then
				if ascending then
					return a.value < b.value
				end
				return a.value > b.value
			end
			return a.key < b.key
		end)
		local index = 0
		local pages = {} :: any
		local function load()
			local page = {}
			for i = index + 1, math.min(#sorted, index + pageSize) do
				table.insert(page, sorted[i])
			end
			pages.current = page
			pages.IsFinished = index + pageSize >= #sorted
		end
		pages.GetCurrentPage = function(_: any)
			return pages.current
		end
		pages.AdvanceToNextPageAsync = function(_: any)
			index += pageSize
			load()
		end
		load()
		return pages
	end

	return store
end

function Boards.new(store: StoreLike, options: Options): Board
	local topCache: { at: number, count: number, entries: { Entry } }? = nil
	local topLoading = false
	local scores: { [number]: { at: number, score: number } } = {}
	local board = {} :: any

	local function fresh(at: number, ttl: number): boolean
		return options.clock() - at < ttl
	end

	local function remember(userId: number, score: number)
		local known = scores[userId]
		if known == nil or score >= known.score or not fresh(known.at, options.scoreCacheSeconds) then
			scores[userId] = { at = options.clock(), score = score }
		end
	end

	function board:submit(userId: number, score: number): boolean
		score = math.floor(score)
		if score <= 0 then
			return false
		end
		local known = scores[userId]
		if known and known.score >= score and fresh(known.at, options.scoreCacheSeconds) then
			return false
		end
		local best = score
		local written = false
		local ok = pcall(function()
			store:UpdateAsync(tostring(userId), function(old: any): any
				if type(old) == "number" and old >= score then
					best, written = old, false
					return nil -- jamais de baisse : écriture annulée
				end
				best, written = score, true
				return score
			end)
		end)
		if not ok then
			return false
		end
		remember(userId, best)
		return written
	end

	local function load(count: number): { Entry }?
		local entries: { Entry } = {}
		local ok = pcall(function()
			local pages = store:GetSortedAsync(false, math.clamp(count, 1, MAX_PAGE))
			while true do
				for _, row in pages:GetCurrentPage() do
					local userId = tonumber(row.key)
					if userId and type(row.value) == "number" then
						table.insert(entries, { userId = userId, score = row.value })
						remember(userId, row.value)
					end
					if #entries >= count then
						return
					end
				end
				if pages.IsFinished then
					return
				end
				pages:AdvanceToNextPageAsync()
			end
		end)
		return if ok then entries else nil
	end

	function board:top(count: number): { Entry }?
		count = math.max(1, math.floor(count))
		local waited = 0
		while topLoading and options.wait and waited < WAIT_LIMIT do
			options.wait(WAIT_STEP)
			waited += 1
		end
		local cache = topCache
		if cache and cache.count >= count and fresh(cache.at, options.topCacheSeconds) then
			return table.move(cache.entries, 1, math.min(count, #cache.entries), 1, {})
		end
		topLoading = true
		local entries = load(count)
		topLoading = false
		if entries == nil then
			-- Lecture impossible : on garde l'ancienne liste plutôt que rien.
			return if cache then table.move(cache.entries, 1, math.min(count, #cache.entries), 1, {}) else nil
		end
		topCache = { at = options.clock(), count = count, entries = entries }
		return table.clone(entries)
	end

	function board:get(userId: number): number?
		local known = scores[userId]
		if known and fresh(known.at, options.scoreCacheSeconds) then
			return known.score
		end
		local value: any = nil
		local ok = pcall(function()
			value = store:GetAsync(tostring(userId))
		end)
		if not ok then
			return if known then known.score else nil
		end
		local score = if type(value) == "number" then value else 0
		scores[userId] = { at = options.clock(), score = score }
		return score
	end

	return board :: Board
end

-- Classe des entrées par score décroissant (égalité : identifiant croissant) avec leur position.
function Boards.rank(entries: { Entry }): { { position: number, userId: number, score: number } }
	local sorted = table.clone(entries)
	table.sort(sorted, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.userId < b.userId
	end)
	local ranked = {}
	for index, entry in sorted do
		table.insert(ranked, { position = index, userId = entry.userId, score = entry.score })
	end
	return ranked
end

return Boards
