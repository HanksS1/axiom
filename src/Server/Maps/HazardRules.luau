--!strict
--[[
	HazardRules : effet des zones dangereuses d'une carte (logique pure, testée).

	- métal en fusion (Forge-7) : mort instantanée, pour tous (robots compris) ;
	- radiation (Terres Brûlées) : retire d'abord le bouclier, puis les PV
	  (`Config.Maps.byId.<carte>.radiation`) ; les robots y sont insensibles.

	Les positions sont relatives à l'origine des cartes (`Config.Maps.origin`).
]]

local LayoutBuilder = require(script.Parent.LayoutBuilder)

type Hazard = LayoutBuilder.Hazard

export type Radiation = { shieldPerSecond: number, healthPerSecond: number }

local HazardRules = {}

-- Zone en boîte (`size`) ou en cylindre vertical (`radius`), de 1 stud sous son
-- centre jusqu'à `height` au-dessus.
function HazardRules.inside(hazard: Hazard, position: Vector3): boolean
	if position.Y < hazard.center.Y - 1 or position.Y > hazard.center.Y + hazard.height then
		return false
	end
	if hazard.radius then
		local dx, dz = position.X - hazard.center.X, position.Z - hazard.center.Z
		return dx * dx + dz * dz <= hazard.radius * hazard.radius
	end
	local size = hazard.size :: Vector3
	return math.abs(position.X - hazard.center.X) <= size.X / 2 and math.abs(position.Z - hazard.center.Z) <= size.Z / 2
end

-- Effet subi à cette position : "molten" (prioritaire), "radiation" ou nil.
function HazardRules.effect(hazards: { Hazard }, position: Vector3, isRobot: boolean, radiation: Radiation?): string?
	local irradiated = false
	for _, hazard in hazards do
		if HazardRules.inside(hazard, position) then
			if hazard.kind == "molten" then
				return "molten"
			elseif hazard.kind == "radiation" and not isRobot and radiation ~= nil then
				irradiated = true
			end
		end
	end
	return if irradiated then "radiation" else nil
end

-- Dégâts de radiation sur `dt` secondes : au rythme du bouclier tant qu'il en reste.
function HazardRules.radiationDamage(radiation: Radiation, shield: number, dt: number): number
	return if shield > 0 then radiation.shieldPerSecond * dt else radiation.healthPerSecond * dt
end

return HazardRules
