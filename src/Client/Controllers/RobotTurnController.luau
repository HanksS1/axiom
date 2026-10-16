--!strict
--[[
	RobotTurnController : rotation fluide des robots ancrés (tourelles, bras de
	Forge-7), jouée côté client.

	Le serveur tourne leur cap logique à chaque image mais ne réplique la pièce
	qu'à basse fréquence (Config.Robots.ai.turretReplicateInterval) : écrire un
	CFrame ancré à chaque image côté serveur donnait une rotation saccadée et un
	flux de réplication continu. Ici, chaque client fait tourner la pièce vers le
	cap visé (attribut TurnYaw, posé par le serveur) avec le même calcul
	(Shared/Robots/Turning). Les mises à jour du serveur sont recouvertes à
	l'image suivante : aucune saccade.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Turning = require(ReplicatedStorage:WaitForChild("Shared").Robots.Turning)

local RobotTurnController = {}

-- Au-delà (studs), la rotation n'est plus animée (invisible de si loin).
local MAX_DISTANCE = 300

local yaws: { [BasePart]: number } = {} -- cap affiché de chaque tourelle

local function track(instance: Instance)
	if instance:IsA("BasePart") then
		yaws[instance] = Turning.yawOf(instance.CFrame.Rotation)
	end
end

local function untrack(instance: Instance)
	if instance:IsA("BasePart") then
		yaws[instance] = nil
	end
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	if camera == nil or next(yaws) == nil then
		return
	end
	local from = camera.CFrame.Position
	for part, yaw in yaws do
		local target = part:GetAttribute("TurnYaw")
		if type(target) ~= "number" or (part.Position - from).Magnitude > MAX_DISTANCE then
			continue
		end
		local turned = Turning.step(yaw, target, dt)
		yaws[part] = turned
		part.CFrame = CFrame.new(part.Position) * CFrame.Angles(0, turned, 0)
	end
end

function RobotTurnController.init() end

function RobotTurnController.start()
	for _, instance in CollectionService:GetTagged("TurretRoot") do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal("TurretRoot"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("TurretRoot"):Connect(untrack)
	RunService.RenderStepped:Connect(step)
end

return RobotTurnController
