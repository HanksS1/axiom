--!strict
--[[
	FfaBoard : tableau des scores de l'Arène FFA (logique pure, testée).

	ÉPHÉMÈRE : un score n'existe que pendant la présence du joueur dans
	l'arène (`join` à l'arrivée, `leave` au départ : remis à zéro). Rien
	n'est jamais écrit dans le profil — un élimination en bac à sable ne
	compte pas dans les statistiques permanentes.

	Seules comptent les éliminations d'un JOUEUR présent par un autre joueur
	présent (ni les mannequins, ni un suicide, ni un joueur hors de l'arène).
	Classement : éliminations décroissantes ; à égalité, celui qui a atteint ce
	score le premier ; puis l'ordre d'arrivée.
]]

export type Entry = {
	userId: number,
	name: string,
	kills: number,
	reachedAt: number, -- numéro d'ordre du dernier changement de score (égalités)
}

export type Board = {
	entries: { [number]: Entry },
	counter: number,
}

export type Row = { name: string, kills: number, me: boolean }
export type View = { kills: number, top: { Row }, players: number }

local FfaBoard = {}

function FfaBoard.new(): Board
	return { entries = {}, counter = 0 }
end

local function nextOrder(board: Board): number
	board.counter += 1
	return board.counter
end

-- Arrivée dans l'arène (sans effet si le joueur y est déjà).
function FfaBoard.join(board: Board, userId: number, name: string)
	if board.entries[userId] == nil then
		board.entries[userId] = { userId = userId, name = name, kills = 0, reachedAt = nextOrder(board) }
	end
end

-- Départ de l'arène (ou du serveur) : son score disparaît.
function FfaBoard.leave(board: Board, userId: number)
	board.entries[userId] = nil
end

-- Élimination de `victimId` par `killerId`. Retourne true si elle compte.
function FfaBoard.recordKill(board: Board, killerId: number?, victimId: number): boolean
	if killerId == nil or killerId == victimId then
		return false
	end
	local killer = board.entries[killerId]
	if killer == nil or board.entries[victimId] == nil then
		return false
	end
	killer.kills += 1
	killer.reachedAt = nextOrder(board)
	return true
end

function FfaBoard.ranked(board: Board): { Entry }
	local list = {}
	for _, entry in board.entries do
		table.insert(list, entry)
	end
	table.sort(list, function(a, b)
		if a.kills ~= b.kills then
			return a.kills > b.kills
		end
		if a.reachedAt ~= b.reachedAt then
			return a.reachedAt < b.reachedAt
		end
		return a.userId < b.userId
	end)
	return list
end

-- Ce qu'un joueur voit : ses éliminations et les `count` meilleurs scores.
function FfaBoard.view(board: Board, userId: number, count: number): View
	local ranked = FfaBoard.ranked(board)
	local top: { Row } = {}
	for index = 1, math.min(count, #ranked) do
		local entry = ranked[index]
		table.insert(top, { name = entry.name, kills = entry.kills, me = entry.userId == userId })
	end
	local mine = board.entries[userId]
	return { kills = if mine then mine.kills else 0, top = top, players = #ranked }
end

return FfaBoard
