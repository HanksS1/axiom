--!strict
--[[
	NameplateController : pseudo, niveau et rang au-dessus de la tête des
	autres joueurs, dans le hub seulement (section 15.1).

	Le niveau et le rang viennent des attributs publics `Level` et `Rank`
	posés par le serveur (LeaderboardService) : rien n'est calculé ici.
	En partie, aucune plaque (information tactique).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ProfileController = require(script.Parent.ProfileController)
local Theme = require(script.Parent.Parent.UI.Theme)

local NameplateController = {}

local t = ProfileController.t
local player = Players.LocalPlayer

local HUB_RADIUS = 260
local REFRESH = 0.5
local LEGEND_COLOR = Color3.fromRGB(255, 196, 64)

type Plate = { gui: BillboardGui, name: TextLabel, info: TextLabel }
local plates: { [Player]: Plate } = {}
local folder: Folder

local function hubCenter(): Vector3?
	local terminus = Workspace:FindFirstChild("Terminus")
	local structure = if terminus then terminus:FindFirstChild("Structure") else nil
	local platform = if structure then structure:FindFirstChild("Platform") else nil
	return if platform and platform:IsA("BasePart") then platform.Position else nil
end

local function label(parent: Instance, y: number, height: number, size: number): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Position = UDim2.fromScale(0, y)
	text.Size = UDim2.fromScale(1, height)
	text.Font = Theme.fontTitle
	text.TextSize = size
	text.TextStrokeTransparency = 0.35
	text.Parent = parent
	return text
end

local function plateFor(other: Player): Plate
	local existing = plates[other]
	if existing then
		return existing
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = `Plate_{other.UserId}`
	gui.Size = UDim2.fromOffset(200, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	gui.Enabled = false
	gui.Parent = folder
	local plate = {
		gui = gui,
		name = label(gui, 0, 0.55, 18),
		info = label(gui, 0.55, 0.45, 14),
	}
	plate.name.TextColor3 = Theme.text
	plates[other] = plate
	return plate
end

local function render(other: Player, plate: Plate)
	local level = other:GetAttribute("Level")
	local rank = other:GetAttribute("Rank")
	plate.name.Text = other.DisplayName
	local parts = {}
	if type(level) == "number" then
		table.insert(parts, t("common.level", { level = level }))
	end
	if type(rank) == "string" then
		table.insert(parts, t("rank." .. rank))
	end
	plate.info.Text = table.concat(parts, "  ·  ")
	plate.info.TextColor3 = if rank == "legend" then LEGEND_COLOR else Theme.orange
end

local function refresh()
	local center = hubCenter()
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local character = other.Character
			local head = if character then character:FindFirstChild("Head") else nil
			local plate = plateFor(other)
			local inHub = center ~= nil
				and head ~= nil
				and head:IsA("BasePart")
				and (head.Position - center).Magnitude < HUB_RADIUS
			plate.gui.Adornee = if inHub then head :: BasePart else nil
			plate.gui.Enabled = inHub
		end
	end
end

function NameplateController.init() end

function NameplateController.start()
	folder = Instance.new("Folder")
	folder.Name = "Nameplates"
	folder.Parent = player:WaitForChild("PlayerGui")

	local function watch(other: Player)
		if other == player then
			return
		end
		local plate = plateFor(other)
		render(other, plate)
		other:GetAttributeChangedSignal("Level"):Connect(function()
			render(other, plate)
		end)
		other:GetAttributeChangedSignal("Rank"):Connect(function()
			render(other, plate)
		end)
	end
	for _, other in Players:GetPlayers() do
		watch(other)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(other)
		local plate = plates[other]
		if plate then
			plate.gui:Destroy()
			plates[other] = nil
		end
	end)
	-- Changement de langue : on retraduit.
	ProfileController.Changed:Connect(function()
		for other, plate in plates do
			render(other, plate)
		end
	end)
	task.spawn(function()
		while true do
			refresh()
			task.wait(REFRESH)
		end
	end)
end

return NameplateController
