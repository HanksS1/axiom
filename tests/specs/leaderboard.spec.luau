--!nocheck
-- Classements : meilleur score conservé, cache, classement par position, changement de saison.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	local Boards = H.require("ServerScriptService/Server/Progression/Boards")
	local MatchRules = H.require("ReplicatedStorage/Shared/Match/MatchRules")
	local Config = H.require("ReplicatedStorage/Shared/Config")

	local function newBoard(store)
		local clock = { now = 0 }
		local board = Boards.new(store or Boards.memoryStore(), {
			clock = function()
				return clock.now
			end,
			topCacheSeconds = 60,
			scoreCacheSeconds = 300,
		})
		return board, clock
	end

	describe("Boards", function()
		it("ne garde que le meilleur score (jamais de baisse)", function()
			local board = newBoard()
			expect(board:submit(1, 500)).toBe(true)
			expect(board:submit(1, 300)).toBe(false)
			expect(board:get(1)).toBe(500)
			expect(board:submit(1, 900.7)).toBe(true)
			expect(board:get(1)).toBe(900)
			expect(board:submit(2, 0)).toBe(false)
			expect(board:submit(2, -10)).toBe(false)
		end)

		it("top trié, limité et mis en cache", function()
			local store = Boards.memoryStore()
			local board, clock = newBoard(store)
			for userId = 1, 150 do
				board:submit(userId, userId * 10)
			end
			local top = board:top(120)
			expect(#top).toBe(120)
			expect(top[1].userId).toBe(150)
			expect(top[120].score).toBe(310)
			-- Un nouveau score n'apparaît qu'après expiration du cache.
			store:UpdateAsync("999", function()
				return 99999
			end)
			expect(board:top(5)[1].userId).toBe(150)
			clock.now = 61
			expect(board:top(5)[1].userId).toBe(999)
		end)

		it("stockage en panne : nil (ou l'ancienne liste), jamais d'erreur", function()
			local broken = {
				UpdateAsync = function()
					error("panne")
				end,
				GetAsync = function()
					error("panne")
				end,
				GetSortedAsync = function()
					error("panne")
				end,
			}
			local board = newBoard(broken)
			expect(board:submit(1, 10)).toBe(false)
			expect(board:top(10)).toBe(nil)
			expect(board:get(1)).toBe(nil)
		end)

		it("positions : score décroissant, égalité départagée", function()
			local ranked = Boards.rank({
				{ userId = 7, score = 100 },
				{ userId = 3, score = 400 },
				{ userId = 5, score = 100 },
			})
			expect(ranked[1].userId).toBe(3)
			expect(ranked[2].userId).toBe(5)
			expect(ranked[3].position).toBe(3)
		end)
	end)

	describe("Saisons", function()
		local start = Config.Progression.season.firstSeasonStartUnix
		local length = 8 * 7 * 86400

		it("archive le rang final et remet le top 10 à zéro", function()
			local profile = {
				season = { id = 1, top10 = { { score = 4000 }, { score = 2500 } } },
				seasonHistory = {},
			}
			expect(MatchRules.rollSeason(profile, start + 10)).toBe(false)
			expect(MatchRules.rollSeason(profile, start + length + 5)).toBe(true)
			expect(profile.season.id).toBe(2)
			expect(#profile.season.top10).toBe(0)
			expect(profile.seasonHistory[1].rank).toBe("steel")
		end)

		it("une Légende garde son titre dans l'historique", function()
			local profile = {
				season = { id = 1, top10 = { { score = 100 } }, legend = true },
				seasonHistory = {},
			}
			expect(MatchRules.seasonRank(profile.season)).toBe("legend")
			MatchRules.rollSeason(profile, start + length)
			expect(profile.seasonHistory[1].rank).toBe("legend")
			expect(profile.season.legend).toBe(nil)
		end)

		it("pré-saison sans historique", function()
			local profile = { season = { id = 0, top10 = { { score = 50 } } }, seasonHistory = {} }
			MatchRules.rollSeason(profile, start)
			expect(#profile.seasonHistory).toBe(0)
			expect(profile.season.id).toBe(1)
		end)
	end)
end
