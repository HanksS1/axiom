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
	- `waitForSaves` : à l'arrêt du serveur, attendre les écritures EN COURS
	  (une libération lancée par le départ du dernier joueur, par exemple).

	Journal (diagnostic des retours en arrière) : chaque chargement, sauvegarde,
	échec, reprise et perte de verrou émet un événement (`options.event`) avec la
	clé, le joueur, le serveur (`jobId`), l'horodatage et le résultat. Chaque
	écriture des données incrémente `meta.seq` dans l'enregistrement : un
	chargement qui lit un `seq` plus petit que la dernière libération connue
	prouve un retour en arrière, et le journal dit quel serveur a écrit quoi.
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
	seq: number, -- numéro de la dernière écriture des données connue (meta.seq)
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
	-- Événements de diagnostic (voir l'en-tête) ; par défaut, une ligne dans `log`.
	event: ((name: string, fields: { [string]: any }) -> ())?,
}

export type AcquireError = "locked" | "error"
export type SaveError = "lost" | "inactive" | "error"

export type SessionStore = {
	acquire: (self: SessionStore, key: string, userId: number) -> (Session?, AcquireError?),
	save: (self: SessionStore, session: Session, release: boolean) -> (boolean, SaveError?),
	isActive: (self: SessionStore, key: string) -> boolean,
	waitForSaves: (self: SessionStore, timeout: number) -> boolean,
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

local function describe(fields: { [string]: any }): string
	local keys = {}
	for k in fields do
		table.insert(keys, k)
	end
	table.sort(keys)
	local parts = {}
	for _, k in keys do
		table.insert(parts, `{k}={fields[k]}`)
	end
	return table.concat(parts, " ")
end

local function seqOf(record: any): number
	local meta = if type(record) == "table" then record.meta else nil
	return if type(meta) == "table" and type(meta.seq) == "number" then meta.seq else 0
end

function SessionStore.new(options: Options): SessionStore
	local log: (message: string) -> () = options.log or warn
	-- Sessions ouvertes par CE serveur, par clé.
	local activeByKey: { [string]: Session } = {}
	-- Sauvegardes en cours, par session (évite deux écritures concurrentes).
	local savingSessions: { [Session]: boolean } = {}
	-- Appels à `save` pas encore terminés (y compris ceux qui attendent leur tour).
	local inFlight = 0

	local function emit(name: string, key: string, userId: number, fields: { [string]: any })
		fields.key = key
		fields.userId = userId
		fields.jobId = options.jobId
		fields.time = options.now()
		if options.event then
			options.event(name, fields)
		else
			log(`[SessionStore] {name} {describe(fields)}`)
		end
	end

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
			local outcome: "acquired" | "locked" | "corrupt" | nil = nil
			local isNew = false
			-- Verrou trouvé (diagnostic) : serveur qui le détenait, âge, et s'il a été repris.
			local holder: string? = nil
			local holderAge: number? = nil
			local takeover: string? = nil
			local ok, result = pcall(function()
				return options.store:UpdateAsync(key, function(record: any)
					-- La fonction peut être rappelée en cas de conflit : on
					-- réinitialise l'issue à chaque appel.
					local now = options.now()
					outcome = nil
					isNew = false
					holder, holderAge, takeover = nil, nil, nil
					if record ~= nil and type(record) ~= "table" then
						-- Données corrompues : on refuse d'écrire par-dessus.
						outcome = "corrupt"
						return nil
					end
					record = record or {}
					local lock = record.lock
					if type(lock) == "table" then
						holder = tostring(lock.jobId)
						holderAge = if type(lock.time) == "number" then now - lock.time else nil
					end
					if lock ~= nil and isLockFresh(lock, now) then
						-- Verrou détenu par une autre session. Si elle vient de
						-- CE serveur et n'est plus ouverte ici, elle est orpheline.
						local orphanFromHere = lock.jobId == options.jobId and activeByKey[key] == nil
						if not orphanFromHere then
							outcome = "locked"
							return nil -- annule l'écriture
						end
						takeover = "orphan"
					elseif lock ~= nil then
						takeover = "stale" -- serveur planté : verrou non rafraîchi
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
					seq = seqOf(result),
				}
				activeByKey[key] = session
				emit("load", key, userId, {
					result = if isNew then "new" else "acquired",
					attempt = attempt,
					seq = session.seq,
					session = sessionId,
					previousHolder = if takeover then holder else nil,
					takeover = takeover,
					lockAge = if takeover then holderAge else nil,
				})
				return session, nil
			end

			if not ok then
				lastError = "error"
				emit("load", key, userId, { result = "error", attempt = attempt, error = tostring(result) })
			elseif outcome == "locked" then
				lastError = "locked"
				emit(
					"load",
					key,
					userId,
					{ result = "locked", attempt = attempt, holder = holder, lockAge = holderAge }
				)
			else
				lastError = "error"
				emit("load", key, userId, { result = outcome or "error", attempt = attempt })
			end

			if attempt < options.loadAttempts then
				options.wait(options.loadRetryDelay)
			end
		end
		emit("load.gaveup", key, userId, { result = lastError, attempts = options.loadAttempts })
		return nil, lastError
	end

	--[[
		Attend la fin des sauvegardes en cours (au plus `timeout` secondes de
		`options.now`). Retourne false si le délai est dépassé. À appeler à
		l'arrêt du serveur : une libération lancée par le départ du dernier
		joueur ne doit pas être coupée par la fermeture.
	]]
	function object:waitForSaves(timeout: number): boolean
		local deadline = options.now() + timeout
		while inFlight > 0 do
			if options.now() >= deadline then
				return false
			end
			options.wait(0.1)
		end
		return true
	end

	local function saveNow(session: Session, release: boolean): (boolean, SaveError?)
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
		local attempts = 0
		local nextSeq = session.seq
		-- Verrou trouvé à la place du nôtre (diagnostic d'une perte de verrou).
		local foundJob: string? = nil
		for attempt = 1, options.saveAttempts do
			attempts = attempt
			local ok, err = pcall(function()
				options.store:UpdateAsync(session.key, function(record: any)
					lost = false
					foundJob = nil
					local lock = if type(record) == "table" then record.lock else nil
					if type(lock) ~= "table" or lock.sessionId ~= session.sessionId then
						-- Le verrou ne nous appartient plus : on n'écrit RIEN.
						lost = true
						foundJob = if type(lock) == "table" then tostring(lock.jobId) else "none"
						return nil
					end
					-- Copie : la sérialisation ne doit jamais voir un état intermédiaire.
					record.data = deepCopy(session.data)
					nextSeq = seqOf(record) + 1
					record.meta = { seq = nextSeq, savedAt = options.now(), jobId = options.jobId }
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
			emit("save", session.key, session.userId, {
				result = "retry",
				attempt = attempt,
				release = release,
				error = tostring(err),
			})
			if attempt < options.saveAttempts then
				options.wait(options.saveRetryDelay)
			end
		end

		savingSessions[session] = nil

		if lost then
			session.active = false
			activeByKey[session.key] = nil
			emit("lock.lost", session.key, session.userId, {
				result = "lost",
				session = session.sessionId,
				holder = foundJob,
				release = release,
			})
			return false, "lost"
		end
		if success then
			session.lastSaveTime = options.now()
			session.seq = nextSeq
			emit("save", session.key, session.userId, {
				result = "ok",
				seq = nextSeq,
				release = release,
				attempts = attempts,
			})
			if release then
				session.active = false
				activeByKey[session.key] = nil
			end
			return true, nil
		end
		emit("save", session.key, session.userId, {
			result = "error",
			seq = session.seq,
			release = release,
			attempts = attempts,
		})
		if release then
			-- La libération a échoué : on ferme quand même la session locale.
			-- Le verrou expirera après `lockTimeout` (aucune perte : la
			-- dernière sauvegarde réussie fait foi).
			session.active = false
			activeByKey[session.key] = nil
		end
		return false, "error"
	end

	function object:save(session: Session, release: boolean): (boolean, SaveError?)
		inFlight += 1
		local ok, saved, err = pcall(saveNow, session, release)
		inFlight -= 1
		if not ok then
			error(saved, 0)
		end
		return saved, err
	end

	return object :: SessionStore
end

return SessionStore
