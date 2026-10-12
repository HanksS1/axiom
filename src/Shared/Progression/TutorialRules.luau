--!strict
--[[
	TutorialRules : règles PURES du tutoriel obligatoire (section 15.2).

	Étapes, dans l'ordre : se déplacer, tirer, parer, ramasser, se soigner,
	s'extraire. À la fin (ou au bout de 5 min) : niveau 2 au minimum, ce qui
	ouvre l'accès aux parties.
]]

local Config = require(script.Parent.Parent.Config)

local Tutorial = Config.Progression.tutorial

local TutorialRules = {}

export type Step = "move" | "shoot" | "parry" | "loot" | "heal" | "extract"

local steps: { Step } = { "move", "shoot", "parry", "loot", "heal", "extract" }
TutorialRules.steps = table.freeze(steps)

function TutorialRules.index(step: Step): number
	return table.find(steps, step) or 0
end

-- Étape suivante (nil après l'extraction : tutoriel terminé).
function TutorialRules.next(step: Step): Step?
	return steps[TutorialRules.index(step) + 1]
end

function TutorialRules.timedOut(startedAt: number, now: number): boolean
	return now - startedAt >= Tutorial.maxDuration
end

-- Récompense : tutoriel validé et niveau minimum pour jouer. Renvoie true si le profil change.
function TutorialRules.complete(profile: { level: number, xp: number, tutorialDone: boolean }): boolean
	local changed = not profile.tutorialDone
	profile.tutorialDone = true
	if profile.level < Tutorial.rewardLevel then
		profile.level = Tutorial.rewardLevel
		profile.xp = 0
		changed = true
	end
	return changed
end

-- Peut-on jouer ? (niveau minimum, atteint par le tutoriel)
function TutorialRules.canPlay(level: number): boolean
	return level >= Config.Progression.minLevelToPlay
end

return TutorialRules
