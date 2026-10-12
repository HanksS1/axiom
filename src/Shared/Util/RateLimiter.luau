--!strict
--[[
	RateLimiter : seau à jetons (token bucket) par clé.

	Chaque clé (en pratique un joueur) dispose d'un seau de `burst` jetons
	qui se remplit de `ratePerSecond` jetons par seconde. Chaque requête
	consomme un jeton ; sans jeton, la requête est refusée.
]]

export type RateLimiter = {
	consume: (self: RateLimiter, key: any, cost: number?) -> boolean,
	reset: (self: RateLimiter, key: any) -> (),
}

type Bucket = {
	tokens: number,
	updatedAt: number,
}

local RateLimiter = {}

function RateLimiter.new(ratePerSecond: number, burst: number, clock: (() -> number)?): RateLimiter
	assert(ratePerSecond > 0, "ratePerSecond doit être > 0")
	assert(burst >= 1, "burst doit être >= 1")
	local now = clock or os.clock
	local buckets: { [any]: Bucket } = {}

	local object = {} :: any

	function object:consume(key: any, cost: number?): boolean
		local price = cost or 1
		local time = now()
		local bucket = buckets[key]
		if bucket == nil then
			bucket = { tokens = burst, updatedAt = time }
			buckets[key] = bucket
		else
			local elapsed = math.max(0, time - bucket.updatedAt)
			bucket.tokens = math.min(burst, bucket.tokens + elapsed * ratePerSecond)
			bucket.updatedAt = time
		end
		if bucket.tokens < price then
			return false
		end
		bucket.tokens -= price
		return true
	end

	function object:reset(key: any)
		buckets[key] = nil
	end

	return object :: RateLimiter
end

return RateLimiter
