--!strict
--[[
	HintRules : quand une aide contextuelle a-t-elle le droit de s'afficher ?

	Logique PURE (testée hors Studio). Une aide est refusée si :
	- les aides sont désactivées, ou le moment ne s'y prête pas (panneau
	  ouvert, mort, tutoriel en cours) ;
	- le joueur a déjà accompli le geste (« apprise ») ;
	- elle a déjà été affichée assez souvent, ou trop récemment ;
	- une autre aide est à l'écran, ou vient de l'être ;
	- elle n'est pas urgente et le joueur est en plein combat.
]]

local HintRules = {}

export type Def = {
	maxShows: number,
	cooldown: number,
	urgent: boolean?,
}

export type State = {
	shows: { [string]: number },
	lastShown: { [string]: number },
	learned: { [string]: boolean },
	visibleUntil: number,
}

export type Context = {
	enabled: boolean, -- paramètre du joueur
	blocked: boolean, -- panneau ouvert, mort, tutoriel
	calm: boolean, -- ni tir ni dégât récemment
	gap: number, -- silence imposé entre deux aides (secondes)
}

function HintRules.new(): State
	return { shows = {}, lastShown = {}, learned = {}, visibleUntil = -math.huge }
end

function HintRules.canShow(state: State, id: string, def: Def?, now: number, context: Context): boolean
	if def == nil or not context.enabled or context.blocked then
		return false
	end
	if state.learned[id] or (state.shows[id] or 0) >= def.maxShows then
		return false
	end
	local last = state.lastShown[id]
	if last ~= nil and now - last < def.cooldown then
		return false
	end
	if now < state.visibleUntil + context.gap then
		return false
	end
	if not def.urgent and not context.calm then
		return false
	end
	return true
end

-- L'aide vient d'être affichée pour `duration` secondes.
function HintRules.markShown(state: State, id: string, now: number, duration: number)
	state.shows[id] = (state.shows[id] or 0) + 1
	state.lastShown[id] = now
	state.visibleUntil = now + duration
end

-- Le joueur a fait le geste de lui-même : l'aide ne s'affichera plus.
function HintRules.learn(state: State, id: string)
	state.learned[id] = true
end

return HintRules
