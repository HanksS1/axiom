--!strict
--[[
	RangeController : le Stand de tir côté client (section 16.4).

	- Ouvre l'écran du stand (station « range »).
	- Défi : compte à rebours, chrono et score en haut de l'écran, puis
	  résultat. Tout vient du serveur (RangeState) : le client n'envoie
	  jamais de score.
	- Dégâts flottants au-dessus des cibles touchées (RangeHit).
	- Pendant un défi : les cibles d'entraînement et le PNJ du stand sont
	  masqués POUR CE JOUEUR SEULEMENT (LocalTransparencyModifier, rien n'est
	  modifié sur le serveur), puis rétablis à la fin de la séance, quelle
	  qu'en soit la raison (fin, arrêt, éloignement, mort, départ en partie).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local Create = require(script.Parent.Parent.UI.Create)
local Theme = require(script.Parent.Parent.UI.Theme)
local RangeScreen = require(script.Parent.Parent.Screens.RangeScreen)
local HUDController = require(script.Parent.HUDController)
local NotificationController = require(script.Parent.NotificationController)
local ProfileController = require(script.Parent.ProfileController)
local TerminusController = require(script.Parent.TerminusController)

local RangeController = {}

local t = ProfileController.t
local player = Players.LocalPlayer

local screen: RangeScreen.Screen
local banner: Frame
local bannerTitle: TextLabel
local bannerValue: TextLabel
local state: { [string]: any }? = nil
local startsAt = 0
local endsAt = 0

-- Éléments masqués pendant le défi, et leur état d'origine (pour tout rétablir).
type Hidden = {
	models: { Instance },
	parts: { [BasePart]: boolean },
	decals: { Decal },
	guis: { [Instance]: boolean },
}
local hidden: Hidden? = nil

local function hideModel(model: Instance, into: Hidden, query: boolean)
	-- Attribut posé par le client : local, jamais répliqué (le PNJ se tait, voir HubAmbienceController).
	model:SetAttribute("LocallyHidden", true)
	table.insert(into.models, model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			into.parts[descendant] = descendant.CanQuery
			descendant.LocalTransparencyModifier = 1
			-- Une cible masquée ne doit pas non plus arrêter les tirs du joueur.
			if not query then
				descendant.CanQuery = false
			end
		elseif descendant:IsA("Decal") then
			table.insert(into.decals, descendant)
			descendant.LocalTransparencyModifier = 1
		elseif descendant:IsA("BillboardGui") or descendant:IsA("SurfaceGui") then
			into.guis[descendant] = descendant.Enabled
			descendant.Enabled = false
		end
	end
end

-- Vue du défi : seules les cibles orange du défi restent visibles.
local function setChallengeView(active: boolean)
	local current = hidden
	if current then
		hidden = nil
		for _, model in current.models do
			model:SetAttribute("LocallyHidden", nil)
		end
		for part, query in current.parts do
			if part.Parent then
				part.LocalTransparencyModifier = 0
				part.CanQuery = query
			end
		end
		for _, decal in current.decals do
			if decal.Parent then
				decal.LocalTransparencyModifier = 0
			end
		end
		for gui, enabled in current.guis do
			if gui.Parent then
				(gui :: any).Enabled = enabled
			end
		end
	end
	if not active then
		return
	end
	local terminus = Workspace:FindFirstChild("Terminus")
	if terminus == nil then
		return
	end
	local into: Hidden = { models = {}, parts = {}, decals = {}, guis = {} }
	for _, descendant in terminus:GetDescendants() do
		if descendant:IsA("Model") then
			if Config.Range.challenge.hidePractice and descendant:GetAttribute("Practice") == true then
				hideModel(descendant, into, false)
			elseif Config.Range.challenge.hideNpc and descendant:GetAttribute("Station") == "range" then
				hideModel(descendant, into, true)
			end
		end
	end
	hidden = into
end

local function renderBanner()
	local current = state
	if current == nil or current.mode ~= "challenge" then
		banner.Visible = false
		return
	end
	banner.Visible = true
	local now = os.clock()
	if now < startsAt then
		bannerTitle.Text = t("range.getReady", { weapon = t("item." .. tostring(current.itemId)) })
		bannerValue.Text = tostring(math.ceil(startsAt - now))
		bannerValue.TextColor3 = Theme.orange
	else
		bannerTitle.Text = t("range.timeLeft", { seconds = math.max(0, math.ceil(endsAt - now)) })
		bannerValue.Text = t("range.score", { score = current.score or 0 })
		bannerValue.TextColor3 = Theme.cyan
	end
end

local function onState(next: { [string]: any })
	-- Temps du serveur ramenés à l'horloge locale.
	local offset = os.clock() - (next.serverTime or os.clock())
	if next.mode == "challenge" then
		startsAt = (next.startsAt or 0) + offset
		endsAt = (next.endsAt or 0) + offset
	end
	state = if next.mode then next else nil
	screen.setSession(next.mode)
	-- Toute fin de séance (résultat, arrêt, éloignement, mort…) rétablit la vue.
	setChallengeView(next.mode == "challenge")
	if next.finished then
		NotificationController.show(t("range.result", { score = next.score or 0, hits = next.hits or 0 }), Theme.orange)
	elseif next.ended == "left" then
		NotificationController.show(t("range.ended"), Theme.textDim)
	end
	renderBanner()
end

-- Dégâts flottants (petite étiquette qui monte et s'efface).
local function onHit(position: Vector3, points: number)
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position + Vector3.new(0, 1, 0)
	anchor.Parent = Workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(90, 34)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = anchor
	local label = Create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Theme.fontNumbers,
		TextSize = 24,
		TextColor3 = Theme.orange,
		TextStrokeTransparency = 0.3,
		Text = tostring(points),
		Parent = gui,
	})
	gui.Parent = anchor
	local rise = TweenService:Create(gui, TweenInfo.new(0.8), { StudsOffsetWorldSpace = Vector3.new(0, 2, 0) })
	local fade = TweenService:Create(label, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 })
	rise:Play()
	fade:Play()
	task.delay(0.85, function()
		anchor:Destroy()
	end)
end

function RangeController.init() end

function RangeController.start()
	local root = HUDController.root()
	screen = RangeScreen.create(root, t)
	screen.onLeaderboard = function()
		TerminusController.openBoard("range")
	end
	TerminusController.register("range", screen :: any)

	banner = Create("Frame", {
		Name = "RangeBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(320, 78),
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = Theme.panelTransparency,
		Visible = false,
		Parent = root,
	}, {
		Stroke = Create("UIStroke", { Color = Theme.orange, Thickness = 2 }),
	})
	bannerTitle = Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		Font = Theme.fontTitle,
		TextSize = 16,
		TextColor3 = Theme.text,
		Parent = banner,
	})
	bannerValue = Create("TextLabel", {
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		Font = Theme.fontNumbers,
		TextSize = 34,
		TextColor3 = Theme.cyan,
		Parent = banner,
	})

	ClientNet.on("RangeState", onState)
	ClientNet.on("RangeHit", onHit)
	RunService.Heartbeat:Connect(function()
		if state then
			renderBanner()
		end
	end)
	-- Un changement de personnage (réapparition, départ en partie) clôt la séance côté serveur.
	player.CharacterAdded:Connect(function()
		state = nil
		screen.setSession(nil)
		setChallengeView(false)
		renderBanner()
	end)
end

return RangeController
