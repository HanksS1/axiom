--!strict
--[[
	WeaponLogic : état d'une arme à distance (chargeur, recharge, surchauffe).

	Fonctions PURES : le temps (`now`) et les cellules disponibles sont
	passés en paramètre. Le serveur fait autorité ; le client utilise la
	même logique pour prédire (affichage immédiat des munitions, cadence).
]]

local Config = require(script.Parent.Parent.Config)

local Overheat = Config.Combat.overheat

export type RangedState = {
	ammo: number, -- projectiles dans le chargeur (armes à chargeur)
	heat: number, -- 0..100 (armes à surchauffe)
	heatUpdatedAt: number,
	overheatedUntil: number,
	lastFireAt: number,
	reloadEndsAt: number?, -- nil = pas de recharge en cours
	cellDebt: number, -- fraction de cellule déjà « entamée » (armes à surchauffe)
}

export type FireBlock = "reloading" | "overheated" | "cooldown" | "empty" | "no_cells"

local WeaponLogic = {}

function WeaponLogic.new(def: any, ammo: number?): RangedState
	return {
		ammo = if def.capacity then math.clamp(ammo or def.capacity, 0, def.capacity) else 0,
		heat = 0,
		heatUpdatedAt = 0,
		overheatedUntil = 0,
		lastFireAt = -math.huge,
		reloadEndsAt = nil,
		cellDebt = 0,
	}
end

function WeaponLogic.usesHeat(def: any): boolean
	return def.heat ~= nil
end

-- Intervalle minimal entre deux activations (tir, rafale, ou tic d'un rayon continu).
function WeaponLogic.fireInterval(def: any): number
	if def.beamTick then
		return def.beamTick
	end
	if def.fireRate <= 0 then
		return 0
	end
	return 1 / def.fireRate
end

-- Chaleur ajoutée par activation (un tir, ou un tic de rayon).
function WeaponLogic.heatPerShot(def: any): number
	local heat = def.heat
	if heat == nil then
		return 0
	end
	return (heat.perShot or 0) + (heat.perSecond or 0) * (def.beamTick or 0)
end

-- Cellules consommées par activation (fraction possible : 1 cellule / 3 tirs, 1 cellule / 0,5 s).
function WeaponLogic.cellsPerShot(def: any): number
	local cost = def.cellCost
	if cost == nil then
		return 0
	end
	if cost.everyShots then
		return cost.cells / cost.everyShots
	end
	if cost.everySeconds and def.beamTick then
		return cost.cells * def.beamTick / cost.everySeconds
	end
	return 0
end

-- Applique le refroidissement : -30/s après 0,4 s sans tirer.
function WeaponLogic.updateHeat(state: RangedState, now: number)
	if state.heat <= 0 then
		state.heatUpdatedAt = now
		return
	end
	local coolStart = math.max(state.heatUpdatedAt, state.lastFireAt + Overheat.coolDelay, state.overheatedUntil)
	if now > coolStart then
		state.heat = math.max(0, state.heat - (now - coolStart) * Overheat.coolPerSecond)
		state.heatUpdatedAt = now
	end
end

-- Cellules nécessaires pour le prochain tir d'une arme à surchauffe.
function WeaponLogic.cellsForNextShot(def: any, state: RangedState): number
	local perShot = WeaponLogic.cellsPerShot(def)
	if perShot <= 0 then
		return 0
	end
	return math.max(0, math.ceil(state.cellDebt + perShot - 1e-9))
end

--[[
	Le tir est-il possible maintenant ? `intervalScale` (0..1) assouplit le
	contrôle de cadence côté serveur (paquets réseau regroupés) ; 1 = strict.
]]
function WeaponLogic.canFire(
	def: any,
	state: RangedState,
	now: number,
	cellsAvailable: number,
	intervalScale: number?
): (boolean, FireBlock?)
	if state.reloadEndsAt ~= nil then
		return false, "reloading"
	end
	if now < state.overheatedUntil then
		return false, "overheated"
	end
	if now - state.lastFireAt < WeaponLogic.fireInterval(def) * (intervalScale or 1) - 1e-6 then
		return false, "cooldown"
	end
	if WeaponLogic.usesHeat(def) then
		if WeaponLogic.cellsForNextShot(def, state) > cellsAvailable then
			return false, "no_cells"
		end
	elseif state.ammo <= 0 then
		return false, "empty"
	end
	return true, nil
end

export type FireResult = {
	projectiles: number, -- nombre total de projectiles (rafale × plombs)
	cellsConsumed: number, -- cellules à retirer du sac (armes à surchauffe)
	overheated: boolean,
}

-- Enregistre un tir (à n'appeler que si `canFire` a répondu oui).
function WeaponLogic.fire(def: any, state: RangedState, now: number): FireResult
	local result: FireResult = { projectiles = 0, cellsConsumed = 0, overheated = false }
	WeaponLogic.updateHeat(state, now)
	if WeaponLogic.usesHeat(def) then
		result.projectiles = def.burstCount * def.pellets
		state.heat = math.min(Overheat.max, state.heat + WeaponLogic.heatPerShot(def))
		-- Coût en cellules : accumulation fractionnaire (1 cellule / 3 tirs…).
		local perShot = WeaponLogic.cellsPerShot(def)
		if perShot > 0 then
			state.cellDebt += perShot
			local whole = math.floor(state.cellDebt + 1e-9)
			result.cellsConsumed = whole
			state.cellDebt -= whole
		end
		if state.heat >= Overheat.max then
			state.overheatedUntil = now + Overheat.lockDuration
			result.overheated = true
		end
	else
		local bullets = math.min(def.burstCount, state.ammo)
		state.ammo -= bullets
		result.projectiles = bullets * def.pellets
	end
	state.lastFireAt = now
	state.heatUpdatedAt = now
	return result
end

-- Peut-on recharger ? (armes à chargeur uniquement)
function WeaponLogic.canReload(def: any, state: RangedState, cellsAvailable: number): boolean
	if def.capacity == nil or state.reloadEndsAt ~= nil then
		return false
	end
	return state.ammo < def.capacity and cellsAvailable > 0
end

function WeaponLogic.startReload(def: any, state: RangedState, now: number)
	state.reloadEndsAt = now + (def.reloadTime :: number)
end

function WeaponLogic.cancelReload(state: RangedState)
	state.reloadEndsAt = nil
end

-- Termine la recharge si son délai est écoulé. Retourne le nombre de
-- cellules à prélever dans le sac (0 si la recharge n'est pas finie).
function WeaponLogic.finishReload(def: any, state: RangedState, now: number, cellsAvailable: number): number
	if state.reloadEndsAt == nil or now < state.reloadEndsAt then
		return 0
	end
	state.reloadEndsAt = nil
	local needed = (def.capacity :: number) - state.ammo
	local used = math.clamp(needed, 0, cellsAvailable)
	state.ammo += used
	return used
end

return WeaponLogic
