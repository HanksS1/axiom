--!strict
--[[
	MovementGuardService : contrôle serveur des déplacements (section 19.4).

	Roblox laisse chaque client simuler son propre personnage : un client
	modifié peut donc se déplacer trop vite ou se téléporter. Le serveur
	compare régulièrement le déplacement horizontal à la vitesse autorisée
	(posture, sprint, effets) et recale le personnage à sa dernière position
	valide en cas d'infractions répétées. La chute n'est pas limitée ; la
	montée l'est (saut, escaliers).

	Les gadgets de déplacement (bottes de saut, grappin) et les poussées
	(gantelet) accordent une tolérance temporaire via `grantAllowance`.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Movement = require(Shared.Combat.Movement)

local CombatService = require(script.Parent.CombatService)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)

local G = Config.Combat.movementGuard

local MovementGuardService = {}

type Track = {
	lastValid: CFrame,
	lastPosition: Vector3,
	strikes: number,
	currentSpeed: number, -- vitesse autorisée actuelle (dernier changement connu)
	-- Vitesse autorisée la plus élevée récente (tolérance de latence).
	recentMaxSpeed: number,
	recentMaxUntil: number,
	allowanceSpeed: number,
	allowanceUntil: number,
	allowanceRise: number, -- montée verticale tolérée par contrôle pendant l'allocation
	resetUntil: number, -- après un recalage ou une téléportation serveur
}

local tracks: { [Player]: Track } = {}

local function newTrack(position: CFrame): Track
	return {
		lastValid = position,
		lastPosition = position.Position,
		strikes = 0,
		currentSpeed = Config.Combat.movement.walkSpeed,
		recentMaxSpeed = Config.Combat.movement.sprintSpeed,
		recentMaxUntil = os.clock() + G.speedGraceTime,
		allowanceSpeed = 0,
		allowanceUntil = 0,
		allowanceRise = 0,
		resetUntil = os.clock() + 1,
	}
end

local function allowedSpeed(player: Player, track: Track, clock: number): number
	local fighter = CombatService.getFighter(player)
	local speed = Config.Combat.movement.sprintSpeed
	if fighter then
		speed = Movement.walkSpeed(fighter.move)
	end
	if clock < track.recentMaxUntil then
		speed = math.max(speed, track.recentMaxSpeed)
	end
	if clock < track.allowanceUntil then
		speed = math.max(speed, track.allowanceSpeed)
	end
	return speed
end

local function check(player: Player, clock: number, dt: number)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		tracks[player] = nil
		return
	end
	local track = tracks[player]
	if track == nil then
		tracks[player] = newTrack(root.CFrame)
		return
	end
	local position = root.Position
	if clock < track.resetUntil or root.Anchored then
		track.lastValid = root.CFrame
		track.lastPosition = position
		track.strikes = 0
		return
	end

	local delta = position - track.lastPosition
	local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
	local maxHorizontal = allowedSpeed(player, track, clock) * dt * G.speedTolerance + G.flatTolerance
	local tooFast = horizontal > maxHorizontal
	local maxRise = if clock < track.allowanceUntil
		then math.max(G.maxVerticalRise, track.allowanceRise)
		else G.maxVerticalRise
	local tooHigh = delta.Y > maxRise
	track.lastPosition = position

	if tooFast or tooHigh then
		track.strikes += 1
		if track.strikes >= G.strikesBeforeCorrection then
			-- Recalage : retour à la dernière position valide.
			root.AssemblyLinearVelocity = Vector3.zero
			root.CFrame = track.lastValid
			track.lastPosition = track.lastValid.Position
			track.strikes = 0
			ServerNet.flag(
				player,
				"Movement",
				if tooHigh then "montée anormale" else `vitesse anormale ({math.floor(horizontal / dt)} studs/s)`
			)
		end
	else
		track.strikes = 0
		track.lastValid = root.CFrame
	end
end

-- Tolérance temporaire (gadgets, poussées, téléportations scriptées).
function MovementGuardService.grantAllowance(player: Player, speed: number, duration: number, rise: number?)
	local track = tracks[player]
	if track then
		local clock = os.clock()
		if clock >= track.allowanceUntil then
			track.allowanceSpeed = 0
			track.allowanceRise = 0
		end
		track.allowanceSpeed = math.max(track.allowanceSpeed, speed)
		track.allowanceRise = math.max(track.allowanceRise, rise or 0)
		track.allowanceUntil = math.max(track.allowanceUntil, clock + duration)
	end
end

-- À appeler après toute téléportation effectuée par le serveur.
function MovementGuardService.reset(player: Player)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		tracks[player] = newTrack(root.CFrame)
	else
		tracks[player] = nil
	end
end

function MovementGuardService.init()
	-- Quand la vitesse autorisée baisse (fin de sprint…), l'ancienne reste
	-- tolérée un court instant (latence du client).
	CombatService.MovementChanged:Connect(function(fighter)
		local player = fighter.player
		local track = if player then tracks[player] else nil
		if track then
			local clock = os.clock()
			local newSpeed = Movement.walkSpeed(fighter.move)
			local stillTolerated = if clock < track.recentMaxUntil then track.recentMaxSpeed else 0
			track.recentMaxSpeed = math.max(stillTolerated, track.currentSpeed, newSpeed)
			track.recentMaxUntil = clock + G.speedGraceTime
			track.currentSpeed = newSpeed
		end
	end)
end

function MovementGuardService.start()
	Players.PlayerRemoving:Connect(function(player)
		tracks[player] = nil
	end)
	-- Repoussement (Gantelet à impulsion) : le vol plané de la victime est toléré.
	CombatService.Knockback:Connect(function(fighter, velocity, duration)
		local player = fighter.player
		if player then
			local horizontal = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
			local rise = velocity.Y * velocity.Y / (2 * Workspace.Gravity) + 3
			MovementGuardService.grantAllowance(player, horizontal * 1.2, duration + 0.6, rise)
		end
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function()
			tracks[player] = nil
		end)
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			tracks[player] = nil
		end)
	end)

	local accumulator = 0
	local lastCheck = os.clock()
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < G.interval then
			return
		end
		accumulator = 0
		local clock = os.clock()
		local elapsed = clock - lastCheck
		lastCheck = clock
		for _, player in Players:GetPlayers() do
			check(player, clock, elapsed)
		end
	end)
end

return MovementGuardService
