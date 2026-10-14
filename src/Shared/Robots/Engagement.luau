--!strict
--[[
	Engagement : tours d'attaque des robots sur une même cible (module PUR).

	Sans limite, une meute entière frappe au même instant et le joueur meurt
	sans avoir pu réagir. Chaque cible n'accepte donc qu'un nombre limité
	d'attaquants à la fois (selon le mode) : les autres robots approchent,
	encerclent, et prennent la place dès qu'elle se libère (attaquant détruit,
	étourdi, ou qui n'a plus attaqué depuis `hold` secondes).
]]

local Engagement = {}

-- cible → { attaquant → moment où son tour expire }
export type State = { [any]: { [any]: number } }

function Engagement.new(): State
	return {}
end

-- Nombre d'attaquants ayant un tour valide sur `target`.
function Engagement.count(state: State, target: any, now: number): number
	local slots = state[target]
	if slots == nil then
		return 0
	end
	local count = 0
	for attacker, expires in slots do
		if expires > now then
			count += 1
		else
			slots[attacker] = nil
		end
	end
	if count == 0 then
		state[target] = nil
	end
	return count
end

--[[
	`attacker` demande à attaquer `target`. Accordé s'il a déjà son tour ou
	s'il reste une place (`limit`). Un tour accordé est prolongé de `hold`.
]]
function Engagement.request(state: State, target: any, attacker: any, now: number, limit: number, hold: number): boolean
	local slots = state[target]
	local mine = if slots then slots[attacker] else nil
	if mine == nil or mine <= now then
		if Engagement.count(state, target, now) >= limit then
			return false
		end
	end
	local current = state[target]
	if current == nil then
		current = {}
		state[target] = current
	end
	current[attacker] = now + hold
	return true
end

-- L'attaquant rend ses tours (détruit, étourdi, cible perdue).
function Engagement.release(state: State, attacker: any)
	for target, slots in state do
		slots[attacker] = nil
		if next(slots) == nil then
			state[target] = nil
		end
	end
end

-- Oublie une cible (morte, extraite).
function Engagement.forget(state: State, target: any)
	state[target] = nil
end

return Engagement
