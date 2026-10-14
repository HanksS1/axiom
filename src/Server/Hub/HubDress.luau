--!strict
--[[
	HubDress : habillage des murs du Terminus, en priorité derrière les PNJ.

	- Derrière chaque étal du marché (mur sud) : une fresque à la couleur de
	  la station (slogan localisé, attribut TextKey), encadrée de néons qui
	  grésillent, et un emblème holographique qui tourne au-dessus.
	- Derrière le stand de tir et près de la Porte de déploiement : une
	  fresque sur le mur ouest / est.
	- Un chemin de câbles court le long du mur sud, avec des fuites de vapeur.
	- Entre les étals et dans les coins : décors du catalogue des cartes
	  (Server/Maps/Props : casiers, armoires, terminaux, pupitre, groupe de
	  froid, transformateur), posés contre les murs.

	Tout est purement visuel : ancré, sans collision ni blocage des tirs
	(comme Kit.decor). Les animations (Flicker, Spin, Hologram) sont jouées
	par HubAmbienceController, sans code supplémentaire.
]]

local Kit = require(script.Parent.Kit)
local LayoutBuilder = require(script.Parent.Parent.Maps.LayoutBuilder)
local Props = require(script.Parent.Parent.Maps.Props)

local HubDress = {}

local DARK = Color3.fromRGB(30, 31, 36)
local MURAL = Color3.fromRGB(22, 24, 30)
local RUST = Color3.fromRGB(116, 66, 40)
local STEEL = Color3.fromRGB(96, 100, 108)

-- Fresques : station → clé du slogan (Strings : hub.wall.<station>).
HubDress.MURALS = { "vault", "merchant", "armorer", "insurer", "bazaar", "range", "deploy" }

-- Décors du catalogue posés contre les murs : nom, position locale (x, z), orientation.
-- Le devant d'un décor est son axe -Z : 0 = face au nord (mur sud), -π/2 = face à l'est (mur ouest).
local PROPS: { { name: string, x: number, z: number, yaw: number } } = {
	{ name = "lockers", x = -45, z = 56.5, yaw = 0 },
	{ name = "cabinet", x = -38.5, z = 57, yaw = 0 },
	{ name = "terminal", x = -15, z = 57, yaw = 0 },
	{ name = "cabinet", x = -19, z = 57, yaw = 0 },
	{ name = "controlDesk", x = 15, z = 56.5, yaw = 0 },
	{ name = "lockers", x = 76, z = 56.5, yaw = 0 },
	{ name = "coolingUnit", x = 88, z = 54, yaw = 0 },
	{ name = "transformer", x = -86, z = 52, yaw = 0 },
	{ name = "rack", x = -96.5, z = 51, yaw = -math.pi / 2 },
}

-- Fresque : panneau usé, slogan localisé, cadre néon et éclairage d'appoint.
local function mural(parent: Instance, key: string, cframe: CFrame, size: Vector2, color: Color3)
	local board =
		Kit.decor(parent, "Mural_" .. key, Vector3.new(size.X, size.Y, 0.1), cframe, MURAL, Enum.Material.SmoothPlastic)
	Kit.text(board, Enum.NormalId.Front, "hub.wall." .. key, color, Enum.Font.GothamBlack, MURAL)
	for index, offset in { size.Y / 2 + 0.25, -size.Y / 2 - 0.25 } do
		local bar = Kit.decor(
			parent,
			"MuralNeon",
			Vector3.new(size.X + 0.6, 0.18, 0.12),
			cframe * CFrame.new(0, offset, -0.08),
			color,
			Enum.Material.Neon,
			{ tag = if index == 1 then "Flicker" else nil }
		)
		if index == 2 then
			Kit.light(bar, color, 14, 0.8)
		end
	end
	-- Montants rouillés de part et d'autre.
	for _, side in { -1, 1 } do
		Kit.decor(
			parent,
			"MuralBracket",
			Vector3.new(0.4, size.Y + 1.6, 0.3),
			cframe * CFrame.new(side * (size.X / 2 + 0.5), 0, -0.05),
			RUST,
			Enum.Material.CorrodedMetal
		)
	end
end

-- Emblème holographique : anneau qui tourne et cœur qui grésille.
local function emblem(parent: Instance, position: Vector3, color: Color3)
	Kit.decor(
		parent,
		"EmblemRing",
		Vector3.new(0.15, 3.2, 3.2),
		CFrame.new(position) * CFrame.Angles(0, math.pi / 2, 0),
		color,
		Enum.Material.Neon,
		{
			shape = Enum.PartType.Cylinder,
			transparency = 0.55,
			tag = "Spin",
			attributes = { Speed = 0.12 },
		}
	)
	Kit.decor(
		parent,
		"EmblemCore",
		Vector3.new(1, 1, 1),
		CFrame.new(position) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
		color,
		Enum.Material.Neon,
		{ transparency = 0.3, tag = "Hologram" }
	)
end

-- Chemin de câbles le long d'un mur, avec ses supports et quelques fuites de vapeur.
local function cableRun(parent: Instance, from: Vector3, to: Vector3, leaks: { number })
	local length = (to - from).Magnitude
	local middle = (from + to) / 2
	local direction = (to - from).Unit
	local along = CFrame.lookAt(middle, middle + direction)
	for index, offset in { Vector3.new(0, 0, 0), Vector3.new(0, 1.3, 0) } do
		local pipe = Kit.decor(
			parent,
			"CablePipe" .. index,
			Vector3.new(length, 0.7, 0.7),
			along * CFrame.new(offset) * CFrame.Angles(0, math.pi / 2, 0),
			if index == 1 then RUST else STEEL,
			if index == 1 then Enum.Material.CorrodedMetal else Enum.Material.Metal,
			{ shape = Enum.PartType.Cylinder }
		)
		if index == 1 then
			for _, ratio in leaks do
				local leak = Kit.decor(
					parent,
					"Leak",
					Vector3.new(0.4, 0.4, 0.4),
					CFrame.new(from:Lerp(to, ratio) - Vector3.new(0, 0.4, 0)),
					DARK,
					Enum.Material.Metal
				)
				Kit.emitter(leak, "Steam", {
					color = ColorSequence.new(Color3.fromRGB(220, 225, 230)),
					rate = 8,
					lifetime = NumberRange.new(1, 1.8),
					speed = NumberRange.new(3, 6),
					size = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0.4),
						NumberSequenceKeypoint.new(1, 2.4),
					}),
					transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0.5),
						NumberSequenceKeypoint.new(1, 1),
					}),
					spread = Vector2.new(20, 20),
					direction = Enum.NormalId.Bottom,
				})
			end
		end
		local _ = pipe
	end
	for step = 0, math.floor(length / 12) do
		local point = from + direction * math.min(length, step * 12)
		Kit.decor(
			parent,
			"CableBracket",
			Vector3.new(0.3, 2.4, 0.9),
			CFrame.lookAt(point + Vector3.new(0, 0.65, 0), point + Vector3.new(0, 0.65, 0) + direction),
			DARK,
			Enum.Material.Metal
		)
	end
end

-- Décors du catalogue des cartes, rendus comme décor pur (ni collision ni tirs).
local function props(parent: Instance, origin: Vector3)
	local builder = LayoutBuilder.new()
	local rng = LayoutBuilder.random(2077)
	for _, spec in PROPS do
		Props.put(builder, spec.name, spec.x, 0, spec.z, spec.yaw, rng)
	end
	local layout = builder:finish()
	for _, spec in layout.parts do
		spec.collide = false
		spec.query = false
	end
	local folder = Instance.new("Folder")
	folder.Name = "WallProps"
	folder.Parent = parent
	-- Chargé ici seulement : le rendu crée des instances (inutile aux tests de ce module).
	local MapRenderer = require(script.Parent.Parent.Maps.MapRenderer) :: any
	MapRenderer.renderParts(layout.parts, folder, origin, nil)
end

export type Station = { key: string, counter: CFrame }

--[[
	Habille les murs du Terminus construit à `origin` (repère de TerminusBuilder :
	mur sud à z = 59, ouest à x = -99, est à x = 99). `stations` : comptoirs.
]]
function HubDress.build(parent: Instance, origin: Vector3, stations: { Station }, neon: { [string]: Color3 })
	local folder = Instance.new("Folder")
	folder.Name = "WallDress"
	folder.Parent = parent
	local function at(x: number, y: number, z: number): Vector3
		return origin + Vector3.new(x, y, z)
	end

	for _, station in stations do
		local color = neon[station.key]
		local x = station.counter.Position.X - origin.X
		if station.key == "range" then
			-- Mur ouest, au-dessus du pare-balles, face aux tireurs.
			mural(
				folder,
				"range",
				CFrame.new(at(-98.85, 17.5, 18)) * CFrame.Angles(0, -math.pi / 2, 0),
				Vector2.new(12, 4.5),
				color
			)
			emblem(folder, at(-97.6, 23.5, 18), color)
		elseif station.key == "deploy" then
			-- Mur est, au nord de la porte blindée.
			mural(
				folder,
				"deploy",
				CFrame.new(at(98.85, 15, 16)) * CFrame.Angles(0, math.pi / 2, 0),
				Vector2.new(11, 4.5),
				color
			)
		elseif
			table.find(HubDress.MURALS, station.key) and math.abs(station.counter.Position.Z - origin.Z - 42) < 1
		then
			-- Étal du marché : mur sud, au-dessus des étagères (au-delà de la bâche).
			mural(folder, station.key, CFrame.new(at(x, 17, 58.85)), Vector2.new(9, 4.5), color)
			emblem(folder, at(x, 23, 57.4), color)
		end
	end

	cableRun(folder, at(-97, 26.5, 58), at(97, 26.5, 58), { 0.22, 0.61, 0.86 })
	props(folder, origin)
end

return HubDress
