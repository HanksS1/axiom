--!strict
--[[
	MapService : repères d'une carte, posés dans Studio avec des TAGS
	(CollectionService). Toute carte (arène de test, cartes de la P7) se
	décrit ainsi, sans code spécifique :

	| Tag               | Rôle                                   | Attributs                      |
	|-------------------|----------------------------------------|--------------------------------|
	| DeploySpawn       | 8 points de départ en bordure          |                                |
	| ExtractionPoint   | 3 points d'extraction                  | NameKey (texte traduit)        |
	| AcceleratorSpot   | 6 emplacements d'Accélérateur (duo)    |                                |
	| CrateSpawn        | emplacement de caisse                  | CrateType (supply, military…)  |
	| RobotSpawn        | apparition de robot (P4)               | RobotId, Garrison (bool)       |
	| RiskZone          | zone à risque (P4)                     | Main (bool)                    |

	Les repères sont des pièces (souvent invisibles) dans Workspace.
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local MapService = {}

export type Marker = {
	part: BasePart,
	cframe: CFrame,
	position: Vector3,
	attributes: { [string]: any },
}

local function collect(tag: string): { Marker }
	local markers = {}
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(Workspace) then
			table.insert(markers, {
				part = instance,
				cframe = instance.CFrame,
				position = instance.Position,
				attributes = instance:GetAttributes(),
			})
		end
	end
	-- Ordre stable (par nom puis position) : tirages reproductibles.
	table.sort(markers, function(a, b)
		if a.part.Name ~= b.part.Name then
			return a.part.Name < b.part.Name
		end
		return a.position.X < b.position.X
	end)
	return markers
end

function MapService.deploySpawns(): { Marker }
	return collect("DeploySpawn")
end

function MapService.extractionPoints(): { Marker }
	return collect("ExtractionPoint")
end

function MapService.acceleratorSpots(): { Marker }
	return collect("AcceleratorSpot")
end

function MapService.crateSpawns(): { Marker }
	return collect("CrateSpawn")
end

function MapService.robotSpawns(): { Marker }
	return collect("RobotSpawn")
end

function MapService.riskZones(): { Marker }
	return collect("RiskZone")
end

-- Pose un repère (utilisé par l'arène de test et les cartes générées).
function MapService.placeMarker(parent: Instance, tag: string, cframe: CFrame, attributes: { [string]: any }?): Part
	local part = Instance.new("Part")
	part.Name = tag
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(2, 2, 2)
	part.CFrame = cframe
	if attributes then
		for key, value in attributes do
			part:SetAttribute(key, value)
		end
	end
	part.Parent = parent
	CollectionService:AddTag(part, tag)
	return part
end

function MapService.init() end
function MapService.start() end

return MapService
