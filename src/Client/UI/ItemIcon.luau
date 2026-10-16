--!strict
--[[
	ItemIcon : vignette 3D d'un objet (même modèle que l'arme tenue en main,
	voir Shared/Visuals/ItemModels).

	- Fond sombre, liseré et lueur à la couleur de l'ÉTAT de l'objet (la
	  couleur n'est jamais seule : les pastilles et le nom de l'état restent
	  sur la carte).
	- Image fixe : une vignette n'est rendue qu'une fois (peu coûteux, même
	  avec un coffre plein). `spin = true` la fait tourner (aperçu mis en avant).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local ItemModels = require(Shared.Visuals.ItemModels)

local Create = require(script.Parent.Create)
local Theme = require(script.Parent.Theme)

local ItemIcon = {}

local FIELD_OF_VIEW = 30
local spinning: { [Camera]: { angle: number, distance: number, target: Vector3 } } = {}

-- Direction de la caméra autour de l'objet (angle 0 : de profil, bouche à droite).
local function viewFrom(angle: number): Vector3
	return Vector3.new(math.cos(angle), 0.32, math.sin(angle)).Unit
end

-- Une arme se montre de profil, la bouche un peu vers nous ; le reste (armure, sac,
-- gadget, consommable) de trois quarts face.
local WEAPON_ANGLE = math.rad(-18)
local OBJECT_ANGLE = math.rad(-58)

--[[
	Vignette de l'objet `itemId`. `condition` (1 à 5) colore le liseré ;
	`skin` applique un cosmétique. Retourne un cadre vide si l'objet n'a pas
	de modèle (objet inconnu).
]]
function ItemIcon.create(itemId: string, size: UDim2, condition: number?, skin: ItemModels.Skin?, spin: boolean?): Frame
	local conditionDef = if condition then Config.Conditions.list[condition] else nil
	local accent = if conditionDef then conditionDef.color else Theme.textDim
	local blueprint = ItemModels.blueprint(itemId)

	local viewport = Create("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(150, 156, 170),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-0.6, -1, -0.4),
	})
	local frame = Create("Frame", {
		Name = "Icon",
		Size = size,
		BackgroundColor3 = Theme.background,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
	}, {
		Corner = Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
		Stroke = Create("UIStroke", { Color = accent, Transparency = 0.45 }),
		-- Lueur de l'état, en bas de la vignette.
		Glow = Create("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 3),
			BackgroundColor3 = accent,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
		}),
		View = viewport,
	})
	if blueprint == nil then
		return frame
	end
	local model = ItemModels.build(itemId, skin)
	if model == nil then
		return frame
	end
	model.Parent = viewport

	local center, extent = ItemModels.bounds(blueprint)
	local radius = math.max(extent.X, extent.Y, extent.Z) / 2
	local distance = radius / math.tan(math.rad(FIELD_OF_VIEW / 2)) * 1.15
	local info = ItemCatalog.get(itemId)
	local weapon = info ~= nil and (info.category == "ranged" or info.category == "melee")
	local angle = if weapon then WEAPON_ANGLE else OBJECT_ANGLE
	local camera = Instance.new("Camera")
	camera.FieldOfView = FIELD_OF_VIEW
	camera.CFrame = CFrame.lookAt(center + viewFrom(angle) * distance, center)
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	if spin then
		spinning[camera] = { angle = angle, distance = distance, target = center }
		camera.Destroying:Connect(function()
			spinning[camera] = nil
		end)
	end
	return frame
end

-- Vignette estompée en silhouette (emplacement vide : « ici va un casque »).
function ItemIcon.silhouette(frame: Frame, transparency: number)
	local view = frame:FindFirstChild("View")
	if view and view:IsA("ViewportFrame") then
		view.ImageTransparency = transparency
		view.ImageColor3 = Theme.textDim
	end
end

RunService.RenderStepped:Connect(function(dt: number)
	for camera, state in spinning do
		state.angle += dt * 0.9
		camera.CFrame = CFrame.lookAt(state.target + viewFrom(state.angle) * state.distance, state.target)
	end
end)

return ItemIcon
