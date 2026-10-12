--!strict
--[[
	TutorialBuilder : la simulation du tutoriel (section 15.2).

	Un couloir de ruines reconstitué par AXIOM, parcouru vers -Z :
	départ → balise de déplacement → pas de tir (3 cibles) → robot
	d'entraînement (parade) → caisse de ravitaillement → zone d'extraction.

	Une simulation est construite par joueur, loin du Terminus ; elle est
	détruite à la fin du tutoriel.
]]

local Kit = require(script.Parent.Kit)

local TutorialBuilder = {}

local CONCRETE = Color3.fromRGB(78, 80, 86)
local DARK = Color3.fromRGB(34, 36, 42)
local RUST = Color3.fromRGB(116, 70, 44)
local GRID = Color3.fromRGB(0, 229, 255)
local RED = Color3.fromRGB(255, 40, 40)
local GREEN = Color3.fromRGB(57, 255, 20)
local ORANGE = Color3.fromRGB(255, 138, 0)

export type Built = {
	folder: Folder,
	start: CFrame,
	moveBeacon: Vector3,
	targetSpots: { CFrame },
	dummySpot: CFrame,
	crateSpot: CFrame,
	extractCenter: Vector3,
	beacons: { [string]: BasePart },
}

function TutorialBuilder.build(origin: Vector3, extractRadius: number): Built
	local folder = Instance.new("Folder")
	folder.Name = "Tutorial"
	local function at(x: number, y: number, z: number): Vector3
		return origin + Vector3.new(x, y, z)
	end

	-- Sol, murs et plafond ouvert sur un ciel de cendres.
	Kit.part(folder, "Floor", Vector3.new(40, 2, 150), CFrame.new(at(0, -1, -65)), CONCRETE, Enum.Material.Concrete)
	for _, side in { -1, 1 } do
		Kit.part(
			folder,
			"Wall",
			Vector3.new(2, 16, 150),
			CFrame.new(at(side * 21, 8, -65)),
			DARK,
			Enum.Material.CorrodedMetal
		)
		-- Lignes de la grille de simulation.
		for index = 0, 6 do
			Kit.decor(
				folder,
				"GridLine",
				Vector3.new(0.1, 0.15, 150),
				CFrame.new(at(side * 19.9, 2 + index * 2, -65)),
				GRID,
				Enum.Material.Neon,
				{ transparency = 0.6 }
			)
		end
	end
	Kit.part(folder, "BackWall", Vector3.new(40, 16, 2), CFrame.new(at(0, 8, 11)), DARK, Enum.Material.CorrodedMetal)
	Kit.part(folder, "EndWall", Vector3.new(40, 16, 2), CFrame.new(at(0, 8, -141)), DARK, Enum.Material.CorrodedMetal)

	-- Œil d'AXIOM au fond (il observe la simulation).
	local eye = Kit.cylinder(folder, "AxiomEye", 0.4, 6, at(0, 10, -139.6), RED, Enum.Material.Neon)
	eye.CFrame = CFrame.new(at(0, 10, -139.6)) * CFrame.Angles(0, math.rad(90), 0)
	Kit.light(eye, RED, 30, 2, true)
	local banner = Kit.decor(
		folder,
		"SimulationSign",
		Vector3.new(18, 2.4, 0.3),
		CFrame.new(at(0, 14, -139.7)),
		DARK,
		Enum.Material.Metal
	)
	Kit.text(banner, Enum.NormalId.Back, "tutorial.sign", RED, Enum.Font.GothamBlack)

	-- Décombres et câbles : la simulation reproduit les ruines.
	local debris = {
		{ -14, -18, 4, 2, 7, 0.4 },
		{ 15, -44, 6, 3, 4, -0.3 },
		{ -15, -80, 5, 2, 6, 0.2 },
		{ 14, -100, 3, 5, 3, 0.7 },
		{ -12, -122, 7, 2, 4, -0.5 },
	}
	for _, d in debris do
		Kit.part(
			folder,
			"Debris",
			Vector3.new(d[4], d[5], d[6]),
			CFrame.new(at(d[1], d[5] / 2, d[2])) * CFrame.Angles(0, d[3], d[3] * 0.1),
			if d[2] % 2 == 0 then RUST else CONCRETE,
			Enum.Material.Slate
		)
	end
	for index = 1, 6 do
		local z = -10 - index * 20
		local lamp = Kit.decor(
			folder,
			"Lamp",
			Vector3.new(6, 0.3, 0.6),
			CFrame.new(at(if index % 2 == 0 then -8 else 8, 14, z)),
			Color3.fromRGB(255, 230, 190),
			Enum.Material.Neon,
			{ tag = "Flicker" }
		)
		Kit.light(lamp, Color3.fromRGB(255, 220, 170), 26, 1.4)
	end

	local beacons: { [string]: BasePart } = {}
	local function beacon(key: string, position: Vector3, color: Color3): BasePart
		local pillar = Kit.decor(
			folder,
			"Beacon_" .. key,
			Vector3.new(1.2, 40, 1.2),
			CFrame.new(position + Vector3.new(0, 20, 0)),
			color,
			Enum.Material.Neon,
			{ transparency = 1 }
		)
		beacons[key] = pillar
		return pillar
	end

	-- 1. Déplacement.
	local moveBeacon = at(0, 0, -26)
	Kit.cylinder(folder, "MovePad", 0.3, 8, moveBeacon + Vector3.new(0, 0.15, 0), GRID, Enum.Material.Neon, {
		collide = false,
		query = false,
		transparency = 0.4,
	})
	beacon("move", moveBeacon, GRID)

	-- 2. Pas de tir : trois cibles au fond d'une alcôve.
	local targetSpots = {}
	for index = 1, 3 do
		local x = (index - 2) * 7
		table.insert(targetSpots, CFrame.lookAt(at(x, 3.2, -58), at(x, 3.2, -30)))
	end
	Kit.part(
		folder,
		"ShootingLine",
		Vector3.new(30, 0.06, 0.4),
		CFrame.new(at(0, 0.03, -36)),
		ORANGE,
		Enum.Material.Neon,
		{ collide = false, query = false }
	)
	beacon("shoot", at(0, 0, -58), ORANGE)

	-- 3. Robot d'entraînement (parade).
	local dummySpot = CFrame.lookAt(at(0, 0, -76), at(0, 0, -60))
	beacon("parry", at(0, 0, -76), RED)

	-- 4. Caisse de ravitaillement.
	local crateSpot = CFrame.new(at(8, 0, -94)) * CFrame.Angles(0, math.rad(-25), 0)
	beacon("loot", at(8, 0, -94), GREEN)

	-- 5. Zone d'extraction.
	local extractCenter = at(0, 0, -122)
	Kit.cylinder(
		folder,
		"ExtractRing",
		0.25,
		extractRadius * 2,
		extractCenter + Vector3.new(0, 0.13, 0),
		GREEN,
		Enum.Material.Neon,
		{ collide = false, query = false, transparency = 0.55 }
	)
	beacon("extract", extractCenter, GREEN)

	return {
		folder = folder,
		start = CFrame.lookAt(at(0, 3, 0), at(0, 3, -20)),
		moveBeacon = moveBeacon,
		targetSpots = targetSpots,
		dummySpot = dummySpot,
		crateSpot = crateSpot,
		extractCenter = extractCenter,
		beacons = beacons,
	}
end

return TutorialBuilder
