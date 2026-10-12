--!strict
--[[
	Écran de chargement / titre (section 17.3, écran 1).

	Logo néon qui grésille, messages d'AXIOM et astuces, barre de chargement
	en forme de jauge d'énergie. Affiché dès la connexion (ReplicatedFirst),
	retiré quand le client a reçu le profil (attribut AxiomReady), ou après
	un délai de sécurité.
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local CYAN = Color3.fromRGB(0, 229, 255)
local ORANGE = Color3.fromRGB(255, 138, 0)
local DIM = Color3.fromRGB(150, 158, 170)
local CELLS = 12
local TIMEOUT = 45
local AXIOM_MESSAGES = 5
local TIPS = 8

local function new(className: string, properties: { [string]: any }): any
	local instance = Instance.new(className)
	for key, value in properties do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	instance.Parent = properties.Parent
	return instance
end

local gui = new("ScreenGui", {
	Name = "AxiomLoading",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	DisplayOrder = 1000,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})
local background = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(8, 10, 16),
	Parent = gui,
})
local logo = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.36),
	Size = UDim2.new(0.9, 0, 0, 70),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = CYAN,
	Text = "AXIOM WAR",
	Parent = background,
})
new("UISizeConstraint", { MaxSize = Vector2.new(700, 70), Parent = logo })
local subtitle = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.36, 40),
	Size = UDim2.new(0.6, 0, 0, 32),
	BackgroundTransparency = 1,
	Font = Enum.Font.Code,
	TextSize = 26,
	TextColor3 = ORANGE,
	Text = "E X T R A C T I O N",
	Parent = background,
})
local message = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.58, 0),
	Size = UDim2.new(0.8, 0, 0, 26),
	BackgroundTransparency = 1,
	Font = Enum.Font.Code,
	TextSize = 18,
	TextColor3 = Color3.fromRGB(255, 59, 59),
	TextWrapped = true,
	Text = "",
	Parent = background,
})
local tip = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.58, 34),
	Size = UDim2.new(0.8, 0, 0, 44),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	TextSize = 16,
	TextColor3 = DIM,
	TextWrapped = true,
	Text = "",
	Parent = background,
})
-- Jauge d'énergie : cellules qui s'allument.
local gauge = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.8, 0),
	Size = UDim2.fromOffset(CELLS * 26, 22),
	BackgroundTransparency = 1,
	Parent = background,
})
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 4),
	Parent = gauge,
})
local cells = {}
for index = 1, CELLS do
	local cell = new("Frame", {
		LayoutOrder = index,
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = Color3.fromRGB(30, 34, 44),
		BorderSizePixel = 0,
		Parent = gauge,
	})
	new("UIStroke", { Color = CYAN, Transparency = 0.6, Parent = cell })
	table.insert(cells, cell)
end

-- Textes localisés dès que le code partagé est disponible.
local translate: ((key: string) -> string)? = nil
task.spawn(function()
	local shared = ReplicatedStorage:WaitForChild("Shared", 15)
	if shared == nil then
		return
	end
	local ok, Localization = pcall(require, shared:WaitForChild("Localization") :: ModuleScript)
	if ok then
		local lang = (Localization :: any).resolve(nil, player.LocaleId)
		translate = function(key: string): string
			return (Localization :: any).get(lang, key)
		end
	end
end)

local random = Random.new()
local start = os.clock()
local shown = 0
local nextText = 0
local finished = false

local function progress(): number
	local target = 0.15
	if game:IsLoaded() then
		target = 0.5
	end
	if ReplicatedStorage:FindFirstChild("Shared") then
		target = math.max(target, 0.7)
	end
	if player:GetAttribute("AxiomReady") == true then
		target = 1
	end
	return target
end

local connection: RBXScriptConnection
connection = RunService.RenderStepped:Connect(function(dt: number)
	local now = os.clock()
	-- Logo néon qui grésille de temps en temps.
	logo.TextTransparency = if random:NextNumber() < 0.03 then 0.6 else 0
	subtitle.TextTransparency = if random:NextNumber() < 0.015 then 0.7 else 0

	local target = if now - start > TIMEOUT then 1 else progress()
	shown += (target - shown) * math.min(1, dt * 3)
	local lit = math.floor(shown * CELLS + 0.001)
	for index, cell in cells do
		cell.BackgroundColor3 = if index <= lit then CYAN else Color3.fromRGB(30, 34, 44)
	end

	local t = translate
	if t and now >= nextText then
		nextText = now + 3.5
		message.Text = t("loading.axiom." .. random:NextInteger(1, AXIOM_MESSAGES))
		tip.Text = t("loading.tip." .. random:NextInteger(1, TIPS))
	end

	if target >= 1 and shown > 0.97 and not finished then
		finished = true
		connection:Disconnect()
		local fade = TweenInfo.new(0.6)
		TweenService:Create(background, fade, { BackgroundTransparency = 1 }):Play()
		for _, label in { logo, subtitle, message, tip } do
			TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		end
		for _, cell in cells do
			TweenService:Create(cell, fade, { BackgroundTransparency = 1 }):Play()
		end
		task.delay(0.7, function()
			gui:Destroy()
		end)
	end
end)
