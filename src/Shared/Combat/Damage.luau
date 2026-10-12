--!strict
--[[
	Damage : calcul des dégâts (sections 6.2, 6.3, 6.7, 6.8, 7.1).

	Fonctions PURES, utilisées par le serveur (qui seul applique les dégâts)
	et testées hors Studio. Le client ne s'en sert que pour l'affichage.
]]

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local ItemRules = require(script.Parent.Parent.Items.ItemRules)

local Combat = Config.Combat

local Damage = {}

export type TargetKind = "player" | "bot" | "robot" | "object"

--[[
	Multiplicateur de distance : 1 jusqu'à la portée efficace, puis baisse
	linéaire jusqu'à `minDamageMultiplier` à `endRangeMultiplier` × portée,
	puis 0 au-delà de `maxRangeMultiplier` × portée.
]]
function Damage.falloff(effectiveRange: number, distance: number): number
	local falloff = Combat.falloff
	if distance <= effectiveRange then
		return 1
	end
	if distance > effectiveRange * falloff.maxRangeMultiplier then
		return 0
	end
	local endRange = effectiveRange * falloff.endRangeMultiplier
	if distance >= endRange then
		return falloff.minDamageMultiplier
	end
	local t = (distance - effectiveRange) / (endRange - effectiveRange)
	return 1 + (falloff.minDamageMultiplier - 1) * t
end

-- Portée maximale d'une arme (au-delà, le tir ne fait aucun dégât).
function Damage.maxRange(effectiveRange: number): number
	return effectiveRange * Combat.falloff.maxRangeMultiplier
end

export type RangedHit = {
	def: any, -- RangedDef
	condition: number,
	distance: number,
	isHead: boolean,
	helmet: Types.ItemInstance?,
	targetKind: TargetKind,
}

-- Dégâts d'un projectile d'arme à distance (avant bouclier).
function Damage.ranged(hit: RangedHit): number
	local def = hit.def
	local damage = def.damage * ItemRules.efficiency(hit.condition) * Damage.falloff(def.effectiveRange, hit.distance)
	if hit.isHead and def.headshots and (hit.targetKind == "player" or hit.targetKind == "bot") then
		damage *= ItemRules.headMultiplier(hit.helmet)
	end
	if def.robotDamageMultiplier and hit.targetKind == "robot" then
		damage *= def.robotDamageMultiplier
	end
	return damage
end

-- Dégâts d'un coup de mêlée (avant parade et bouclier).
function Damage.melee(def: any, condition: number): number
	return def.damage * ItemRules.efficiency(condition)
end

export type ApplyResult = {
	health: number,
	shield: number,
	shieldDamage: number,
	healthDamage: number,
}

--[[
	Applique des dégâts : le bouclier absorbe d'abord, puis les PV.
	`shieldIgnore` (0..1) : part des dégâts qui contourne le bouclier
	(Lame vibrante d'Exécuteur : 0,5).
]]
function Damage.apply(health: number, shield: number, amount: number, shieldIgnore: number?): ApplyResult
	local total = math.max(0, amount)
	local bypass = total * math.clamp(shieldIgnore or 0, 0, 1)
	local blockable = total - bypass
	local shieldDamage = math.min(shield, blockable)
	local healthDamage = math.min(health, bypass + (blockable - shieldDamage))
	return {
		health = health - healthDamage,
		shield = shield - shieldDamage,
		shieldDamage = shieldDamage,
		healthDamage = healthDamage,
	}
end

export type ParryOutcome = "none" | "reduced" | "perfect" | "broken"

export type ParryInput = {
	parrying: boolean,
	parryStartedAt: number,
	now: number,
	frontal: boolean, -- l'attaque arrive de face
	breaksParry: boolean, -- arme qui brise la garde (Marteau hydraulique)
}

--[[
	Résolution d'une attaque de mêlée contre un joueur en garde (6.8) :
	- "none"    : pas de garde (ou attaque de dos) → dégâts pleins ;
	- "broken"  : garde brisée (Marteau) → dégâts pleins, le défenseur est étourdi ;
	- "perfect" : attaque dans la fenêtre de parade parfaite → dégâts annulés,
	              l'attaquant est étourdi ;
	- "reduced" : garde normale → dégâts réduits de 60 %.
]]
function Damage.resolveParry(input: ParryInput): ParryOutcome
	if not input.parrying or not input.frontal then
		return "none"
	end
	if input.breaksParry then
		return "broken"
	end
	if input.now - input.parryStartedAt <= Combat.parry.perfectWindow then
		return "perfect"
	end
	return "reduced"
end

function Damage.parryMultiplier(outcome: ParryOutcome): number
	if outcome == "perfect" then
		return 0
	elseif outcome == "reduced" then
		return 1 - Combat.parry.meleeFrontalReduction
	end
	return 1
end

-- L'attaquant est-il face au défenseur ? (angle entre le regard du défenseur
-- et la direction de l'attaquant ≤ frontalAngle / 2)
function Damage.isFrontal(defenderLook: Vector3, defenderPosition: Vector3, attackerPosition: Vector3): boolean
	local toAttacker = attackerPosition - defenderPosition
	local flat = Vector3.new(toAttacker.X, 0, toAttacker.Z)
	local look = Vector3.new(defenderLook.X, 0, defenderLook.Z)
	if flat.Magnitude < 1e-3 or look.Magnitude < 1e-3 then
		return true
	end
	local cosine = flat.Unit:Dot(look.Unit)
	return cosine >= math.cos(math.rad(Combat.parry.frontalAngle / 2))
end

return Damage
