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

local MovementCheck = require(script.Parent.Parent.Combat.MovementCheck)
local CombatService = require(script.Parent.CombatService)
local ServerNet = require(script.Parent.Parent.Net.ServerNet)

local G = Config.Combat.movementGuard

local MovementGuardService = {}

local tracks: { [Player]: MovementCheck.Track } = {}

local function check(player: Player, clock: number, dt: number)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		tracks[player] = nil
		return
	end
	local track = tracks[player]
	if track == nil then
		tracks[player] = MovementCheck.newTrack(root.CFrame, clock)
		return
	end
	local fighter = CombatService.getFighter(player)
	local baseSpeed = if fighter then Movement.walkSpeed(fighter.move) else Config.Combat.movement.sprintSpeed
	local verdict, reason = MovementCheck.step(track, root.CFrame, clock, dt, baseSpeed, root.Anchored)
	if verdict == "correct" then
		-- Recalage : retour à la dernière position valide.
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = track.lastValid
		ServerNet.flag(player, "Movement", reason or "")
	end
end

-- Tolérance temporaire (gadgets, poussées, téléportations scriptées).
function MovementGuardService.grantAllowance(player: Player, speed: number, duration: number, rise: number?)
	local track = tracks[player]
	if track then
		MovementCheck.grant(track, speed, duration, rise, os.clock())
	end
end

-- À appeler après toute téléportation effectuée par le serveur.
function MovementGuardService.reset(player: Player)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		tracks[player] = MovementCheck.newTrack(root.CFrame, os.clock())
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
			MovementCheck.speedChanged(track, Movement.walkSpeed(fighter.move), os.clock())
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
			local speed, allowed, rise = MovementCheck.knockbackAllowance(velocity, duration, Workspace.Gravity)
			MovementGuardService.grantAllowance(player, speed, allowed, rise)
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
