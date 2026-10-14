--!strict
--[[
	MapThumbnail : vignette d'une carte (Porte de déploiement).

	Par défaut, le plan vu de dessus de la carte (Shared/Match/MapThumbnails,
	généré à partir des cartes elles-mêmes) dans les couleurs de la carte
	(Config.Maps.*.card). Si une capture est renseignée (`card.image`), elle
	est affichée à la place.

	Une vignette compte quelques centaines de cadres : elle est créée une fois
	et réutilisée (voir DeployScreen).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MapPlan = require(Shared.Match.MapPlan)
local MapThumbnails = require(Shared.Match.MapThumbnails)

local Create = require(script.Parent.Create)

local MapThumbnail = {}

function MapThumbnail.create(mapId: string): Frame
	local def = (Config.Maps.byId :: any)[mapId]
	local card = if def then def.card else nil
	local ground = if card then card.ground else Color3.fromRGB(20, 22, 28)
	local wall = if card then card.wall else Color3.fromRGB(120, 130, 140)
	local frame = Create("Frame", {
		Name = "Thumbnail_" .. mapId,
		BackgroundColor3 = ground,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, {
		Corner = Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
	})
	if card and type(card.image) == "string" and card.image ~= "" then
		Create("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = card.image,
			ScaleType = Enum.ScaleType.Crop,
			Parent = frame,
		})
		return frame
	end
	local plan = MapPlan.decode((MapThumbnails :: any)[mapId])
	if plan then
		-- Plan carré centré dans la vignette (rapport largeur / hauteur libre).
		local square = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Parent = frame,
		}, {
			Ratio = Create("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }),
		})
		local cells = plan.cells
		for _, rect in plan.rects do
			Create("Frame", {
				Position = UDim2.fromScale(rect.x / cells, rect.z / cells),
				Size = UDim2.fromScale(rect.w / cells, rect.d / cells),
				BackgroundColor3 = wall,
				BorderSizePixel = 0,
				Parent = square,
			})
		end
	end
	return frame
end

return MapThumbnail
