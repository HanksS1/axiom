-- Affiche la valeur moyenne / min / max des caisses par mode : `lune run tests/tools/crate_values.luau`
local H = require("../lib/Harness")
H.loadProject("./")
local LootGenerator = H.require("ServerScriptService/Server/Loot/LootGenerator")
local ItemRules = H.require("ReplicatedStorage/Shared/Items/ItemRules")
local ItemCatalog = H.require("ReplicatedStorage/Shared/Items/ItemCatalog")
local n = 0
local function create(id, o)
	n += 1
	o = o or {}
	local info = ItemCatalog.get(id)
	return {
		uid = "u" .. n,
		itemId = id,
		condition = if info.hasCondition then (o.condition or 4) else nil,
		stack = if info.stackSize then (o.stack or info.stackSize) else nil,
	}
end
local rng = H.FakeRandom.new(3)
for _, mode in { "easy", "medium", "hard" } do
	for _, crate in { "supply", "military", "axiom_locker" } do
		local tot, runs, lo, hi = 0, 3000, math.huge, 0
		for _ = 1, runs do
			local v = 0
			for _, it in LootGenerator.crate(crate, mode, rng, create) do
				v += ItemRules.value(it)
			end
			tot += v
			lo = math.min(lo, v)
			hi = math.max(hi, v)
		end
		print(mode, crate, math.floor(tot / runs), lo, hi)
	end
end
