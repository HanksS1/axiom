--!strict
--[[
	ConsumableRules : un consommable peut-il être utilisé maintenant ? (calcul
	pur, testé ; appliqué par CombatService.useConsumable).

	Raisons de refus (texte : `consumable.failure.<raison>`) :
	- "useless"  : PV ou bouclier déjà pleins, pas de bouclier à recharger ;
	- "exo_used" : un exo-harnais est déjà actif (un seul par partie : la place
	  ajoutée au sac ne se cumule pas).
]]

local ConsumableRules = {}

export type FighterView = {
	health: number,
	maxHealth: number,
	shield: number,
	maxShield: number,
	exoUsed: boolean,
}

export type Effect = {
	heal: number?,
	shield: number?,
	bonusUp: number?,
	speedMultiplier: number?,
	duration: number?,
}

-- Raison du refus, ou nil si l'objet peut être utilisé.
function ConsumableRules.refusal(effect: Effect, fighter: FighterView): string?
	if effect.heal and fighter.health >= fighter.maxHealth then
		return "useless"
	end
	if effect.shield and (fighter.maxShield <= 0 or fighter.shield >= fighter.maxShield) then
		return "useless"
	end
	if effect.bonusUp and fighter.exoUsed then
		return "exo_used"
	end
	return nil
end

return ConsumableRules
