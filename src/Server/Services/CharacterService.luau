--!strict
--[[
	CharacterService : préparation des personnages des joueurs.

	- Humanoïde : PV gérés par le serveur (pas de régénération), saut en
	  hauteur, mort sans démembrement (désintégration côté client).
	- Hitbox : seules les pièces du corps sont touchables (HumanoidRootPart
	  et accessoires exclus des rayons), pour que la posture réduise
	  réellement la silhouette.
	- Création du combattant à partir de l'équipement du profil (ou du kit
	  de base s'il est vide).
	- Visuels provisoires : arme tenue en main, postures accroupi / couché.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Types = require(Shared.Types)

local Fighter = require(script.Parent.Parent.Combat.Fighter)
local ItemFactory = require(script.Parent.Parent.Inventory.ItemFactory)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)

type Fighter = Fighter.Fighter

local Visuals = Config.Visuals
local MovementConfig = Config.Combat.movement

local CharacterService = {}

local rootJointC0: { [Model]: CFrame } = {}

-- Rend une pièce « décorative » : ni collision, ni rayons, ni masse.
local function makeDecorative(part: BasePart)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
end

-- Arme tenue en main (greybox), mise à jour quand l'arme active change.
local function updateWeaponVisual(character: Model)
	local existing = character:FindFirstChild("WeaponVisual")
	if existing then
		existing:Destroy()
	end
	local weaponId = character:GetAttribute("WeaponId")
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if type(weaponId) ~= "string" or hand == nil or not hand:IsA("BasePart") then
		return
	end
	local shape = Visuals.weapons[weaponId]
	if shape == nil then
		return
	end
	local model = Instance.new("Model")
	model.Name = "WeaponVisual"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = shape.size
	body.Color = Visuals.bodyColor
	body.Material = Enum.Material.Metal
	makeDecorative(body)
	body.CFrame = hand.CFrame * shape.gripOffset
	body.Parent = model

	local accent = Instance.new("Part")
	accent.Name = "Accent"
	accent.Size = Vector3.new(shape.size.X + 0.02, shape.size.Y * 0.2, shape.size.Z * 0.8)
	accent.Color = shape.accent
	accent.Material = Enum.Material.Neon
	makeDecorative(accent)
	accent.CFrame = body.CFrame * CFrame.new(0, shape.size.Y * 0.25, 0)
	accent.Parent = model

	for _, part in { body, accent } do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand
		weld.Part1 = part
		weld.Parent = part
	end
	model.PrimaryPart = body
	model.Parent = character
end

-- Postures (provisoire, sans animation) : on abaisse les hanches, et en
-- position couchée on bascule le corps à l'horizontale.
local function applyStance(fighter: Fighter)
	local character = fighter.character
	local humanoid = fighter.humanoid
	local lowerTorso = character:FindFirstChild("LowerTorso")
	local rootJoint = if lowerTorso then lowerTorso:FindFirstChild("Root") else nil
	local stance = fighter.move.stance
	local baseHip = MovementConfig.standHipHeight

	if stance == "stand" or fighter.dead then
		humanoid.HipHeight = baseHip
	elseif stance == "crouch" then
		humanoid.HipHeight = baseHip + MovementConfig.crouchHipOffset
	else
		humanoid.HipHeight = 0.6
	end

	if rootJoint and rootJoint:IsA("Motor6D") then
		local original = rootJointC0[character]
		if original == nil then
			original = rootJoint.C0
			rootJointC0[character] = original
		end
		if stance == "prone" and not fighter.dead then
			rootJoint.C0 = original * CFrame.new(0, -0.6, 0) * CFrame.Angles(math.rad(-90), 0, 0)
		else
			rootJoint.C0 = original
		end
	end
end

-- Équipement de combat : profil du joueur, sinon kit de base.
local function equipmentFor(player: Player): (Fighter.Equipment, { [string]: number })
	local profile = DataService.waitForProfile(player, 10)
	if profile and (profile.loadout.ranged or profile.loadout.melee) then
		local loadout = profile.loadout
		return {
			ranged = loadout.ranged,
			melee = loadout.melee,
			helmet = loadout.helmet,
			vest = loadout.vest,
		},
			Fighter.cellsFromBag(profile.bag)
	end
	local kitLoadout: Types.Loadout, kitBag = ItemFactory.createBaseKit()
	return {
		ranged = kitLoadout.ranged,
		melee = kitLoadout.melee,
	}, Fighter.cellsFromBag(kitBag)
end

local function setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if humanoid == nil or root == nil or character.Parent == nil then
		return
	end

	-- Pas de régénération automatique des PV (section 6.2).
	local healthScript = character:FindFirstChild("Health")
	if healthScript and healthScript:IsA("Script") then
		healthScript:Destroy()
	end
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.UseJumpPower = false
	humanoid.MaxHealth = Config.Combat.maxHealth
	humanoid.Health = Config.Combat.maxHealth
	humanoid.HipHeight = MovementConfig.standHipHeight
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	-- Hitbox : seul le corps est touchable.
	root.CanQuery = false
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:FindFirstAncestorOfClass("Accessory") then
			makeDecorative(descendant)
		end
	end
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") and descendant:FindFirstAncestorOfClass("Accessory") then
			makeDecorative(descendant)
		end
	end)

	local equipment, cells = equipmentFor(player)
	if character.Parent == nil or player.Character ~= character then
		return
	end
	local fighter = Fighter.new("player", player, character, humanoid, root, equipment, Fighter.simpleInventory(cells))
	CombatService.register(fighter)
	updateWeaponVisual(character)
	applyStance(fighter)

	character:GetAttributeChangedSignal("WeaponId"):Connect(function()
		updateWeaponVisual(character)
	end)
	character.Destroying:Connect(function()
		rootJointC0[character] = nil
	end)
end

function CharacterService.init()
	CombatService.MovementChanged:Connect(function(fighter)
		if fighter.character.Parent ~= nil then
			applyStance(fighter)
		end
	end)
end

function CharacterService.start()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			setupCharacter(player, character)
		end)
		if player.Character then
			task.spawn(setupCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

-- Exposé pour les mannequins de l'arène (même rendu que les joueurs).
CharacterService.updateWeaponVisual = updateWeaponVisual
CharacterService.makeDecorative = makeDecorative

return CharacterService
