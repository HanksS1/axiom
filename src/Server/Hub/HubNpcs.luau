--!strict
--[[
	HubNpcs : les survivants derrière les comptoirs du Terminus.

	Chaque PNJ a une silhouette mystérieuse (capuches, masques, visières
	lumineuses, prothèses) construite en greybox par-dessus un avatar R15.
	Ils sont statiques côté serveur ; le client les fait respirer, regarder
	autour d'eux, suivre le joueur du regard et le saluer (tag HubNpc).

	Le nom et le rôle s'affichent au-dessus de leur tête (textes localisés).
]]

local Players = game:GetService("Players")

local Kit = require(script.Parent.Kit)

local HubNpcs = {}

local DARK = Color3.fromRGB(24, 25, 30)
local METAL = Color3.fromRGB(86, 90, 98)

type Wear = (
	partName: string,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: EnumItem,
	options: Kit.PartOptions?
) -> Part?

export type NpcDef = {
	id: string,
	accent: Color3,
	skin: Color3,
	cloth: Color3,
	pants: Color3,
	build: (wear: Wear, model: Model, accent: Color3) -> (),
}

local DEFS: { [string]: NpcDef } = {
	-- La Gardienne du coffre : capuche profonde, un seul œil lumineux, clés.
	vault = {
		id = "keeper",
		accent = Color3.fromRGB(176, 92, 255),
		skin = Color3.fromRGB(150, 130, 120),
		cloth = Color3.fromRGB(46, 30, 62),
		pants = Color3.fromRGB(30, 24, 40),
		build = function(wear, _model, accent)
			wear(
				"Head",
				"Hood",
				Vector3.new(1.55, 1.5, 1.55),
				CFrame.new(0, 0.15, 0.12),
				Color3.fromRGB(52, 34, 70),
				Enum.Material.Fabric
			)
			wear(
				"Head",
				"Shadow",
				Vector3.new(1.05, 0.95, 0.1),
				CFrame.new(0, -0.05, -0.62),
				DARK,
				Enum.Material.SmoothPlastic
			)
			wear(
				"Head",
				"Eye",
				Vector3.new(0.28, 0.28, 0.28),
				CFrame.new(0.15, 0.05, -0.68),
				accent,
				Enum.Material.Neon,
				{
					shape = Enum.PartType.Ball,
				}
			)
			wear(
				"UpperTorso",
				"Mantle",
				Vector3.new(2.6, 0.6, 1.6),
				CFrame.new(0, 0.7, 0),
				Color3.fromRGB(52, 34, 70),
				Enum.Material.Fabric
			)
			wear(
				"UpperTorso",
				"Coat",
				Vector3.new(2.25, 2.1, 1.35),
				CFrame.new(0, -0.1, 0),
				Color3.fromRGB(40, 28, 54),
				Enum.Material.Fabric
			)
			wear(
				"LowerTorso",
				"CoatSkirt",
				Vector3.new(2.3, 2.9, 1.45),
				CFrame.new(0, -1.3, 0),
				Color3.fromRGB(40, 28, 54),
				Enum.Material.Fabric
			)
			for index = -1, 1 do
				wear(
					"LowerTorso",
					"Key" .. index,
					Vector3.new(0.12, 0.45, 0.25),
					CFrame.new(1.2, -0.3 + index * 0.18, index * 0.15),
					Color3.fromRGB(220, 180, 70),
					Enum.Material.Foil
				)
			end
		end,
	},
	-- Rouille, le ferrailleur : lunettes, masque à gaz, montagne de bric-à-brac.
	merchant = {
		id = "scrap",
		accent = Color3.fromRGB(57, 255, 20),
		skin = Color3.fromRGB(120, 92, 74),
		cloth = Color3.fromRGB(70, 80, 54),
		pants = Color3.fromRGB(54, 50, 44),
		build = function(wear, _model, accent)
			for _, side in { -1, 1 } do
				wear(
					"Head",
					"Goggle",
					Vector3.new(0.2, 0.42, 0.42),
					CFrame.new(side * 0.25, 0.2, -0.58) * CFrame.Angles(0, math.rad(90), 0),
					Color3.fromRGB(255, 160, 40),
					Enum.Material.Glass,
					{
						shape = Enum.PartType.Cylinder,
						transparency = 0.2,
					}
				)
				wear(
					"Head",
					"Filter",
					Vector3.new(0.35, 0.36, 0.36),
					CFrame.new(side * 0.42, -0.35, -0.5) * CFrame.Angles(0, math.rad(side * 30), 0),
					METAL,
					Enum.Material.Metal,
					{
						shape = Enum.PartType.Cylinder,
					}
				)
			end
			wear("Head", "Strap", Vector3.new(1.3, 0.15, 1.3), CFrame.new(0, 0.2, 0), DARK, Enum.Material.Rubber)
			wear(
				"Head",
				"GasMask",
				Vector3.new(0.85, 0.6, 0.35),
				CFrame.new(0, -0.32, -0.55),
				DARK,
				Enum.Material.Rubber
			)
			wear(
				"UpperTorso",
				"Poncho",
				Vector3.new(2.7, 1.9, 1.7),
				CFrame.new(0, 0.1, 0),
				Color3.fromRGB(80, 92, 58),
				Enum.Material.Fabric
			)
			wear(
				"UpperTorso",
				"Pack",
				Vector3.new(2, 2.4, 1.2),
				CFrame.new(0, 0.4, 1.3),
				Color3.fromRGB(96, 74, 52),
				Enum.Material.Fabric
			)
			wear(
				"UpperTorso",
				"Junk1",
				Vector3.new(1, 0.7, 0.8),
				CFrame.new(-0.6, 1.9, 1.3) * CFrame.Angles(0, 0.3, 0.2),
				METAL,
				Enum.Material.CorrodedMetal
			)
			wear(
				"UpperTorso",
				"Junk2",
				Vector3.new(0.7, 0.9, 0.7),
				CFrame.new(0.5, 1.95, 1.4) * CFrame.Angles(0.2, 0, -0.3),
				Color3.fromRGB(120, 60, 40),
				Enum.Material.CorrodedMetal
			)
			wear(
				"UpperTorso",
				"Antenna",
				Vector3.new(0.08, 2.6, 0.08),
				CFrame.new(0.8, 2.6, 1.6),
				METAL,
				Enum.Material.Metal
			)
			wear(
				"UpperTorso",
				"AntennaLight",
				Vector3.new(0.22, 0.22, 0.22),
				CFrame.new(0.8, 3.95, 1.6),
				accent,
				Enum.Material.Neon,
				{
					shape = Enum.PartType.Ball,
					tag = "Flicker",
				}
			)
		end,
	},
	-- Étincelle, l'armurière : masque de soudeur, tablier de cuir, bras mécanique.
	armorer = {
		id = "spark",
		accent = Color3.fromRGB(255, 138, 0),
		skin = Color3.fromRGB(160, 120, 96),
		cloth = Color3.fromRGB(60, 54, 50),
		pants = Color3.fromRGB(44, 40, 38),
		build = function(wear, _model, accent)
			wear(
				"Head",
				"WeldMask",
				Vector3.new(1.35, 1.4, 1.35),
				CFrame.new(0, 0.05, -0.05),
				Color3.fromRGB(40, 40, 44),
				Enum.Material.Metal
			)
			wear("Head", "Slit", Vector3.new(0.95, 0.13, 0.05), CFrame.new(0, 0.12, -0.73), accent, Enum.Material.Neon)
			wear(
				"UpperTorso",
				"Apron",
				Vector3.new(1.9, 1.9, 0.2),
				CFrame.new(0, -0.1, -0.6),
				Color3.fromRGB(100, 66, 42),
				Enum.Material.Leather
			)
			wear(
				"LowerTorso",
				"ApronLow",
				Vector3.new(1.9, 2.2, 0.2),
				CFrame.new(0, -1.2, -0.5),
				Color3.fromRGB(100, 66, 42),
				Enum.Material.Leather
			)
			wear(
				"RightUpperArm",
				"ArmPlate",
				Vector3.new(1.1, 1.3, 1.1),
				CFrame.new(),
				METAL,
				Enum.Material.DiamondPlate
			)
			wear("RightLowerArm", "Forearm", Vector3.new(0.95, 1.2, 0.95), CFrame.new(), METAL, Enum.Material.Metal)
			wear(
				"RightUpperArm",
				"Pauldron",
				Vector3.new(1.4, 0.6, 1.4),
				CFrame.new(0, 0.6, 0),
				Color3.fromRGB(60, 62, 70),
				Enum.Material.Metal
			)
			for _, partName in { "RightUpperArm", "RightLowerArm" } do
				wear(
					partName,
					"Joint",
					Vector3.new(0.45, 0.45, 0.45),
					CFrame.new(0, -0.6, 0),
					accent,
					Enum.Material.Neon,
					{
						shape = Enum.PartType.Ball,
					}
				)
			end
			wear("RightHand", "Torch", Vector3.new(0.3, 0.3, 1.2), CFrame.new(0, -0.2, -0.5), DARK, Enum.Material.Metal)
		end,
	},
	-- L'Actuaire : masque lisse sans visage, long manteau, tablette holographique.
	insurer = {
		id = "actuary",
		accent = Color3.fromRGB(0, 229, 255),
		skin = Color3.fromRGB(200, 200, 205),
		cloth = Color3.fromRGB(22, 24, 30),
		pants = Color3.fromRGB(18, 20, 24),
		build = function(wear, _model, accent)
			wear(
				"Head",
				"Mask",
				Vector3.new(1.3, 1.45, 1.3),
				CFrame.new(0, 0.05, -0.02),
				Color3.fromRGB(235, 236, 240),
				Enum.Material.SmoothPlastic,
				{
					shape = Enum.PartType.Ball,
				}
			)
			for _, side in { -1, 1 } do
				wear(
					"Head",
					"EyeLine",
					Vector3.new(0.32, 0.06, 0.05),
					CFrame.new(side * 0.24, 0.12, -0.66),
					accent,
					Enum.Material.Neon
				)
			end
			wear("UpperTorso", "Collar", Vector3.new(1.9, 0.8, 1.5), CFrame.new(0, 0.95, 0), DARK, Enum.Material.Fabric)
			wear(
				"UpperTorso",
				"Coat",
				Vector3.new(2.15, 2.05, 1.3),
				CFrame.new(0, -0.1, 0),
				Color3.fromRGB(26, 28, 34),
				Enum.Material.Fabric
			)
			wear(
				"LowerTorso",
				"CoatTail",
				Vector3.new(2.2, 3.1, 1.35),
				CFrame.new(0, -1.4, 0),
				Color3.fromRGB(26, 28, 34),
				Enum.Material.Fabric
			)
			wear(
				"LeftHand",
				"Tablet",
				Vector3.new(1.3, 0.95, 0.05),
				CFrame.new(0.2, 0.1, -0.7) * CFrame.Angles(math.rad(-35), 0, 0),
				accent,
				Enum.Material.Neon,
				{
					transparency = 0.45,
					tag = "Hologram",
				}
			)
		end,
	},
	-- Néa, l'hologramme marchand du Holo-Bazar.
	bazaar = {
		id = "nea",
		accent = Color3.fromRGB(255, 46, 196),
		skin = Color3.fromRGB(255, 46, 196),
		cloth = Color3.fromRGB(255, 46, 196),
		pants = Color3.fromRGB(255, 46, 196),
		build = function(wear, model, accent)
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
					descendant.Material = Enum.Material.ForceField
					descendant.Color = accent
				end
			end
			wear(
				"Head",
				"Visor",
				Vector3.new(1.2, 0.25, 0.1),
				CFrame.new(0, 0.15, -0.62),
				Color3.fromRGB(255, 220, 245),
				Enum.Material.Neon
			)
			Kit.tag(model, "Hologram")
		end,
	},
	-- Le Passeur : armure lourde, visière rouge, antenne clignotante.
	deploy = {
		id = "ferryman",
		accent = Color3.fromRGB(255, 59, 59),
		skin = Color3.fromRGB(110, 90, 80),
		cloth = Color3.fromRGB(56, 62, 48),
		pants = Color3.fromRGB(44, 48, 40),
		build = function(wear, _model, accent)
			wear(
				"Head",
				"Helmet",
				Vector3.new(1.4, 1.3, 1.45),
				CFrame.new(0, 0.12, 0),
				Color3.fromRGB(62, 68, 56),
				Enum.Material.Metal
			)
			wear("Head", "Visor", Vector3.new(1.2, 0.35, 0.08), CFrame.new(0, 0.05, -0.74), accent, Enum.Material.Neon)
			wear(
				"Head",
				"HelmetAntenna",
				Vector3.new(0.06, 1.4, 0.06),
				CFrame.new(0.5, 1.2, 0.3),
				METAL,
				Enum.Material.Metal
			)
			wear(
				"Head",
				"AntennaTip",
				Vector3.new(0.18, 0.18, 0.18),
				CFrame.new(0.5, 1.95, 0.3),
				accent,
				Enum.Material.Neon,
				{
					shape = Enum.PartType.Ball,
					tag = "Flicker",
				}
			)
			wear(
				"UpperTorso",
				"ChestPlate",
				Vector3.new(2.2, 1.8, 1.4),
				CFrame.new(0, 0, 0),
				Color3.fromRGB(70, 76, 62),
				Enum.Material.DiamondPlate
			)
			for _, side in { "LeftUpperArm", "RightUpperArm" } do
				wear(
					side,
					"Pad",
					Vector3.new(1.45, 0.65, 1.45),
					CFrame.new(0, 0.55, 0),
					Color3.fromRGB(62, 68, 56),
					Enum.Material.Metal
				)
			end
		end,
	},
	-- Vieux Hertz, l'armurier du stand de tir : casquette, cache-œil à LED.
	range = {
		id = "hertz",
		accent = Color3.fromRGB(255, 176, 32),
		skin = Color3.fromRGB(170, 130, 110),
		cloth = Color3.fromRGB(84, 70, 52),
		pants = Color3.fromRGB(50, 46, 40),
		build = function(wear, _model, accent)
			wear(
				"Head",
				"Cap",
				Vector3.new(1.3, 0.35, 1.3),
				CFrame.new(0, 0.6, 0),
				Color3.fromRGB(70, 60, 44),
				Enum.Material.Fabric
			)
			wear(
				"Head",
				"Brim",
				Vector3.new(1.1, 0.1, 0.7),
				CFrame.new(0, 0.48, -0.75),
				Color3.fromRGB(60, 50, 38),
				Enum.Material.Fabric
			)
			wear(
				"Head",
				"Eyepatch",
				Vector3.new(0.4, 0.35, 0.08),
				CFrame.new(-0.25, 0.12, -0.62),
				DARK,
				Enum.Material.Leather
			)
			wear(
				"Head",
				"PatchLed",
				Vector3.new(0.1, 0.1, 0.05),
				CFrame.new(-0.25, 0.12, -0.67),
				Color3.fromRGB(255, 40, 40),
				Enum.Material.Neon,
				{
					tag = "Flicker",
				}
			)
			wear(
				"Head",
				"Beard",
				Vector3.new(1, 0.55, 0.4),
				CFrame.new(0, -0.45, -0.5),
				Color3.fromRGB(170, 170, 170),
				Enum.Material.Fabric
			)
			wear(
				"UpperTorso",
				"Vest",
				Vector3.new(2.15, 1.9, 1.3),
				CFrame.new(),
				Color3.fromRGB(96, 80, 56),
				Enum.Material.Fabric
			)
			wear(
				"UpperTorso",
				"Rifle",
				Vector3.new(0.3, 0.4, 4),
				CFrame.new(0.3, 0.2, 0.85) * CFrame.Angles(math.rad(70), 0, math.rad(20)),
				DARK,
				Enum.Material.Metal
			)
			wear(
				"UpperTorso",
				"RifleAccent",
				Vector3.new(0.32, 0.1, 1.2),
				CFrame.new(0.3, 0.2, 0.85) * CFrame.Angles(math.rad(70), 0, math.rad(20)) * CFrame.new(0, 0.2, 0),
				accent,
				Enum.Material.Neon
			)
		end,
	},
	-- L'Archiviste : robe à capuche, cubes de données en orbite.
	legends = {
		id = "archivist",
		accent = Color3.fromRGB(0, 229, 255),
		skin = Color3.fromRGB(120, 120, 130),
		cloth = Color3.fromRGB(30, 40, 56),
		pants = Color3.fromRGB(24, 30, 42),
		build = function(wear, model, accent)
			wear(
				"Head",
				"Hood",
				Vector3.new(1.55, 1.55, 1.6),
				CFrame.new(0, 0.2, 0.15),
				Color3.fromRGB(30, 42, 60),
				Enum.Material.Fabric
			)
			wear(
				"Head",
				"Shadow",
				Vector3.new(1.05, 1, 0.1),
				CFrame.new(0, -0.05, -0.62),
				DARK,
				Enum.Material.SmoothPlastic
			)
			for _, side in { -1, 1 } do
				wear(
					"Head",
					"Eye",
					Vector3.new(0.14, 0.14, 0.05),
					CFrame.new(side * 0.2, 0.05, -0.68),
					accent,
					Enum.Material.Neon
				)
			end
			wear(
				"UpperTorso",
				"Robe",
				Vector3.new(2.3, 2.1, 1.4),
				CFrame.new(),
				Color3.fromRGB(30, 42, 60),
				Enum.Material.Fabric
			)
			wear(
				"LowerTorso",
				"RobeSkirt",
				Vector3.new(2.4, 3.2, 1.5),
				CFrame.new(0, -1.45, 0),
				Color3.fromRGB(30, 42, 60),
				Enum.Material.Fabric
			)
			wear(
				"UpperTorso",
				"Trim",
				Vector3.new(0.15, 2.1, 0.05),
				CFrame.new(0, 0, -0.72),
				accent,
				Enum.Material.Neon
			)
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				for index = 1, 3 do
					local cube = Kit.decor(
						model,
						"DataCube" .. index,
						Vector3.new(0.35, 0.35, 0.35),
						root.CFrame * CFrame.new(0, 1.5, 0),
						accent,
						Enum.Material.Neon,
						{
							tag = "Orbit",
							attributes = {
								Center = root.Position + Vector3.new(0, 1.6 + index * 0.35, 0),
								Radius = 1.8 + index * 0.25,
								Speed = 0.25 + index * 0.08,
								Phase = index * 2.1,
							},
						}
					)
					Kit.light(cube, accent, 5, 0.5)
				end
			end
		end,
	},
}

-- Ajoute une pièce soudée sur une partie du corps.
local function makeWear(model: Model): Wear
	return function(partName, name, size, offset, color, material, options)
		local base = model:FindFirstChild(partName)
		if base == nil or not base:IsA("BasePart") then
			return nil
		end
		local part = Kit.decor(model, name, size, (base :: BasePart).CFrame * offset, color, material, options)
		Kit.weld(base :: BasePart, part)
		return part
	end
end

-- Nom et rôle au-dessus de la tête (localisés côté client).
local function nameplate(model: Model, def: NpcDef, station: string)
	local head = model:FindFirstChild("Head")
	if head == nil or not head:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Nameplate"
	gui.Size = UDim2.fromOffset(220, 54)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 40
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Parent = head
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0.58, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = def.accent
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel:SetAttribute("TextKey", `npc.{def.id}.name`)
	nameLabel.Parent = gui
	local role = Instance.new("TextLabel")
	role.Position = UDim2.fromScale(0, 0.6)
	role.Size = UDim2.new(1, 0, 0.4, 0)
	role.BackgroundTransparency = 1
	role.Font = Enum.Font.Code
	role.TextScaled = true
	role.TextColor3 = Color3.fromRGB(200, 205, 215)
	role.TextStrokeTransparency = 0.5
	role:SetAttribute("TextKey", "station." .. station)
	role.Parent = gui
end

-- Fait apparaître le PNJ d'une station (peut céder la main : à appeler dans une tâche).
function HubNpcs.spawn(parent: Instance, station: string, cframe: CFrame): Model?
	local def = DEFS[station]
	if def == nil then
		return nil
	end
	-- La création d'avatar passe par le réseau : elle peut échouer ponctuellement.
	local ok, model = false, nil :: any
	for attempt = 1, 3 do
		ok, model = pcall(function()
			local description = Instance.new("HumanoidDescription")
			description.HeadColor = def.skin
			description.LeftArmColor = def.cloth
			description.RightArmColor = def.cloth
			description.TorsoColor = def.cloth
			description.LeftLegColor = def.pants
			description.RightLegColor = def.pants
			return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
		end)
		if ok and model then
			break
		end
		warn(`[HubNpcs] PNJ {def.id} non créé (essai {attempt}/3) : {model}`)
		task.wait(2)
	end
	if not ok or model == nil then
		return nil
	end
	local npc = model :: Model
	npc.Name = "Npc_" .. def.id
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid == nil or root == nil then
		npc:Destroy()
		return nil
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	local animate = npc:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	-- Posé derrière le comptoir, pieds au sol.
	npc:PivotTo(cframe * CFrame.new(0, humanoid.HipHeight + root.Size.Y / 2, 0))
	root.Anchored = true
	def.build(makeWear(npc), npc, def.accent)
	nameplate(npc, def, station)
	npc:SetAttribute("NpcId", def.id)
	npc:SetAttribute("Station", station)
	Kit.tag(npc, "HubNpc")
	npc.Parent = parent
	return npc
end

function HubNpcs.ids(): { [string]: string }
	local result = {}
	for station, def in DEFS do
		result[station] = def.id
	end
	return result
end

return HubNpcs
