--!strict
--[[
	ReviveRules : règles de la réanimation en duo (section 6.10), logique pure.

	- Accélérateur posé sur un emplacement de la carte entre 80 et 200 studs du
	  lieu de la mort (tiré au hasard), sinon sur le plus proche de cette plage.
	- Dépôt de l'orbe : maintien de 5 s (marge de latence), à portée de la base.
	Réglages : `Config.Combat.revive`, `Config.Match.revive`.
]]

local Config = require(script.Parent.Parent.Config)

local R = Config.Combat.revive

export type Spot = { position: Vector3, cframe: CFrame }

local ReviveRules = {}

-- Écart à la plage autorisée (0 si la distance y est).
local function gap(distance: number): number
	if distance < R.acceleratorMinDistance then
		return R.acceleratorMinDistance - distance
	end
	return math.max(0, distance - R.acceleratorMaxDistance)
end

function ReviveRules.chooseSpot(spots: { Spot }, deathPosition: Vector3, random: Random): CFrame
	local inRange: { CFrame } = {}
	local best: CFrame? = nil
	local bestGap = math.huge
	for _, spot in spots do
		local distance = (spot.position - deathPosition).Magnitude
		local g = gap(distance)
		if g == 0 then
			table.insert(inRange, spot.cframe)
		end
		if g < bestGap then
			bestGap = g
			best = spot.cframe
		end
	end
	if #inRange > 0 then
		return inRange[random:NextInteger(1, #inRange)]
	end
	-- Carte sans emplacement : à la distance minimale, pour ne jamais bloquer.
	return best or CFrame.new(deathPosition + Vector3.new(R.acceleratorMinDistance, 0, 0))
end

-- Maintien assez long (le client peut relâcher un peu tôt à cause de la latence).
function ReviveRules.channelComplete(heldFor: number): boolean
	return heldFor >= R.channelTime * 0.85 - 0.05
end

-- Porteur assez près de la base de l'Accélérateur (marge de déplacement).
function ReviveRules.inReach(distance: number): boolean
	return distance <= Config.Match.revive.acceleratorDistance + 4
end

return ReviveRules
