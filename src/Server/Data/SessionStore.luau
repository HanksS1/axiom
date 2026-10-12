--!strict
--[[
	SessionStore : stockage de profils avec VERROUILLAGE DE SESSION.

	Équivalent maison de ProfileStore (section 19.1), sans dépendance externe
	et testable hors Roblox (le DataStore est injecté).

	Principe :
	- un enregistrement = { data, lock = { jobId, sessionId, time, placeId } } ;
	- `acquire` prend le verrou de façon atomique (UpdateAsync). Si un autre
	  serveur détient un verrou récent, on réessaie quelques fois (cas normal
	  juste après une téléportation), sinon on abandonne ;
	- un verrou non rafraîchi depuis `lockTimeout` est considéré comme
	  abandonné (serveur planté) et peut être repris ;
	- chaque sauvegarde vérifie que le verrou nous appartient TOUJOURS. Si un
	  autre serveur l'a repris, la session est déclarée perdue et plus rien
	  n'est écrit (évite la duplication d'objets entre deux serveurs) ;
	- `save(session, true)` écrit et libère le verrou (départ, téléportation).
]]

export type DataStoreLike = {
	UpdateAsync: (self: any, key: string, transform: (any) -> (any, any?)) -> any,
}

export type Lock = {
	jobId: string,
	sessionId: string,
	time: number,
	placeId: number,
}

export type Session = {
	key: string,
	userId: number,
	sessionId: string,
	data: any,
	isNew: boolean,
	active: boolean, -- false après libération ou perte du verrou
	lastSaveTime: number,
}

export type Options = {
	store: DataStoreLike,
	jobId: string,
	placeId: number,
	now: () -> number,
	wait: (seconds: number) -> (),
	generateId: () -> string,
	template: () -> any,
	lockTimeout: number,
	loadAttempts: number,
	loadRetryDelay: number,
	saveAttempts: number,
	saveRetryDelay: number,
	log: ((message: string) -> ())?,
}

export type AcquireError = "locked" | "error"
export type SaveError = "lost" | "inactive" | "error"

export type SessionStore = {
	acquire: (self: SessionStore, key: string, userId: number) -> (Session?, AcquireError?),
	save: (self: SessionStore, session: Session, release: boolean) -> (boolean, SaveError?),
	isActive: (self: SessionStore, key: string) -> boolean,
}

local SessionStore = {}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for k, v in value do
		result[k] = deepCopy(v)
	end
	return result
end

function SessionStore.new(options: Options): SessionStore
	local log: (message: string) -> () = options.log or warn
	-- Sessions ouvertes par CE serveur, par clé.
	local activeByKey: { [string]: Session } = {}
	-- Sauvegardes en cours, par session (évite deux écritures concurrentes).
	local savingSessions: { [Session]: boolean } = {}

	local object = {} :: any

	local function isLockFresh(lock: any, now: number): boolean
		return type(lock) == "table" and type(lock.time) == "number" and now - lock.time < options.lockTimeout
	end

	function object:isActive(key: string): boolean
		local session = activeByKey[key]
		return session ~= nil and session.active
	end

	function object:acquire(key: string, userId: number): (Session?, AcquireError?)
		assert(activeByKey[key] == nil, `session déjà ouverte sur ce serveur pour {key}`)
		local sessionId = options.generateId()
		local lastError: AcquireError = "error"

		for attempt = 1, options.loadAttempts do
			local outcome: "acquired" | "locked" | nil = nil
			local isNew = false
			local ok, result = pcall(function()
				return options.store:UpdateAsync(key, function(record: any)
					-- La fonction peut être rappelée en cas de conflit : on
					-- réinitialise l'issue à chaque appel.
					local now = options.now()
					outcome = nil
					isNew = false
					if record ~= nil and type(record) ~= "table" then
						-- Données corrompues : on refuse d'écrire par-dessus.
						return nil
					end
					record = record or {}
					local lock = record.lock
					if lock ~= nil and isLockFresh(lock, now) then
						-- Verrou détenu par une autre session. Si elle vient de
						-- CE serveur et n'est plus ouverte ici, elle est orpheline.
						local orphanFromHere = lock.jobId == options.jobId and activeByKey[key] == nil
						if not orphanFromHere then
							outcome = "locked"
							return nil -- annule l'écriture
						end
					end
					if record.data == nil then
						record.data = options.template()
						isNew = true
					end
					record.lock = {
						jobId = options.jobId,
						sessionId = sessionId,
						time = now,
						placeId = options.placeId,
					}
					outcome = "acquired"
					return record, { userId }
				end)
			end)

			if ok and outcome == "acquired" and type(result) == "table" then
				local session: Session = {
					key = key,
					userId = userId,
					sessionId = sessionId,
					data = result.data,
					isNew = isNew,
					active = true,
					lastSaveTime = options.now(),
				}
				activeByKey[key] = session
				return session, nil
			end

			if not ok then
				log(`[SessionStore] échec de chargement de {key} (tentative {attempt}) : {result}`)
				lastError = "error"
			elseif outcome == "locked" then
				lastError = "locked"
			else
				lastError = "error"
			end

			if attempt < options.loadAttempts then
				options.wait(options.loadRetryDelay)
			end
		end
		return nil, lastError
	end

	function object:save(session: Session, release: boolean): (boolean, SaveError?)
		if not session.active then
			return false, "inactive"
		end
		-- Attend la fin d'une éventuelle sauvegarde en cours (autosave).
		while savingSessions[session] do
			options.wait(0.1)
		end
		if not session.active then
			return false, "inactive"
		end
		savingSessions[session] = true

		local lost = false
		local success = false
		for attempt = 1, options.saveAttempts do
			local ok, err = pcall(function()
				options.store:UpdateAsync(session.key, function(record: any)
					lost = false
					local lock = if type(record) == "table" then record.lock else nil
					if type(lock) ~= "table" or lock.sessionId ~= session.sessionId then
						-- Le verrou ne nous appartient plus : on n'écrit RIEN.
						lost = true
						return nil
					end
					-- Copie : la sérialisation ne doit jamais voir un état intermédiaire.
					record.data = deepCopy(session.data)
					if release then
						record.lock = nil
					else
						lock.time = options.now()
					end
					return record, { session.userId }
				end)
			end)
			if ok then
				success = not lost
				break
			end
			log(`[SessionStore] échec de sauvegarde de {session.key} (tentative {attempt}) : {err}`)
			if attempt < options.saveAttempts then
				options.wait(options.saveRetryDelay)
			end
		end

		savingSessions[session] = nil

		if lost then
			session.active = false
			activeByKey[session.key] = nil
			log(`[SessionStore] verrou perdu pour {session.key} : session fermée sans écriture`)
			return false, "lost"
		end
		if success then
			session.lastSaveTime = options.now()
			if release then
				session.active = false
				activeByKey[session.key] = nil
			end
			return true, nil
		end
		if release then
			-- La libération a échoué : on ferme quand même la session locale.
			-- Le verrou expirera après `lockTimeout` (aucune perte : la
			-- dernière sauvegarde réussie fait foi).
			session.active = false
			activeByKey[session.key] = nil
		end
		return false, "error"
	end

	return object :: SessionStore
end

return SessionStore
