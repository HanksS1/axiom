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
	- Visuels provisoires : arme tenue en main, casque, gilet et sac portés,
	  postures accroupi / couché. Les skins cosmétiques équipés (P9) en
	  changent les couleurs et la matière (aucun effet sur le jeu).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Freeze = require(Shared.Util.Freeze)
local InventoryLogic = require(Shared.Items.InventoryLogic)

local Fighter = require(script.Parent.Parent.Combat.Fighter)
local ItemFactory = require(script.Parent.Parent.Inventory.ItemFactory)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)

type Fighter = Fighter.Fighter

local Visuals = Config.Visuals
local MovementConfig = Config.Combat.movement

local CharacterService = {}

local rootJointC0: { [Model]: CFrame } = {}
local skinOf: (character: Model, attribute: string) -> any?
local materialOf: (name: string) -> EnumItem

-- Rend une pièce « décorative » : ni collision, ni rayons, ni masse.
local function makeDecorative(part: BasePart)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
end

-- Skin cosmétique porté (attribut du personnage = identifiant du cosmétique).
skinOf = function(character: Model, attribute: string): any?
	local id = character:GetAttribute(attribute)
	return if type(id) == "string" then Config.Cosmetics.byId[id] else nil
end

materialOf = function(name: string): EnumItem
	local ok, material = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and material then material else Enum.Material.Metal
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
	local skin = skinOf(character, "WeaponSkin")

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = shape.size
	body.Color = if skin then skin.color else Visuals.bodyColor
	body.Material = if skin then materialOf(skin.material) else Enum.Material.Metal
	makeDecorative(body)
	body.CFrame = hand.CFrame * shape.gripOffset
	body.Parent = model

	local accent = Instance.new("Part")
	accent.Name = "Accent"
	accent.Size = Vector3.new(shape.size.X + 0.02, shape.size.Y * 0.2, shape.size.Z * 0.8)
	accent.Color = if skin then skin.accent else shape.accent
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

-- Casque, gilet et sac portés (greybox) : couleur par défaut ou skin équipé.
local ARMOR_DEFAULT = Color3.fromRGB(58, 62, 70)
local ARMOR_PIECES = {
	{ attribute = "HelmetId", skin = "HelmetSkin", name = "HelmetVisual", parts = { "Head" } },
	{ attribute = "VestId", skin = "VestSkin", name = "VestVisual", parts = { "UpperTorso", "Torso" } },
	{ attribute = "BackpackId", skin = "BackpackSkin", name = "BackpackVisual", parts = { "UpperTorso", "Torso" } },
}
local BACKPACK_SIZES: { [string]: Vector3 } = {
	backpack_small = Vector3.new(1.2, 1.3, 0.6),
	backpack_medium = Vector3.new(1.5, 1.6, 0.75),
	backpack_large = Vector3.new(1.8, 2.0, 0.9),
}

local function updateArmorVisual(character: Model)
	for _, piece in ARMOR_PIECES do
		local existing = character:FindFirstChild(piece.name)
		if existing then
			existing:Destroy()
		end
		local itemId = character:GetAttribute(piece.attribute)
		if type(itemId) ~= "string" then
			continue
		end
		local anchor: BasePart? = nil
		for _, partName in piece.parts do
			local candidate = character:FindFirstChild(partName)
			if candidate and candidate:IsA("BasePart") then
				anchor = candidate
				break
			end
		end
		if anchor == nil then
			continue
		end
		local base = anchor :: BasePart
		local size, offset
		if piece.name == "HelmetVisual" then
			size = Vector3.new(base.Size.X * 1.12, base.Size.Y * 0.55, base.Size.Z * 1.12)
			offset = CFrame.new(0, base.Size.Y * 0.3, 0)
		elseif piece.name == "VestVisual" then
			size = Vector3.new(base.Size.X * 1.06, base.Size.Y * 0.85, base.Size.Z * 1.2)
			offset = CFrame.new(0, -base.Size.Y * 0.05, 0)
		else
			size = BACKPACK_SIZES[itemId] or BACKPACK_SIZES.backpack_small
			offset = CFrame.new(0, 0, base.Size.Z / 2 + size.Z / 2)
		end
		local skin = skinOf(character, piece.skin)
		local model = Instance.new("Model")
		model.Name = piece.name
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Size = size
		body.CFrame = base.CFrame * offset
		body.Color = if skin then skin.color else ARMOR_DEFAULT
		body.Material = if skin then materialOf(skin.material) else Enum.Material.Fabric
		makeDecorative(body)
		body.Parent = model
		local stripe = Instance.new("Part")
		stripe.Name = "Accent"
		stripe.Size = Vector3.new(size.X + 0.02, math.min(0.15, size.Y * 0.15), size.Z + 0.02)
		stripe.CFrame = body.CFrame
		stripe.Color = if skin then skin.accent else Color3.fromRGB(90, 96, 106)
		stripe.Material = if skin then Enum.Material.Neon else Enum.Material.Metal
		makeDecorative(stripe)
		stripe.Parent = model
		for _, part in { body, stripe } do
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = base
			weld.Part1 = part
			weld.Parent = part
		end
		model.PrimaryPart = body
		model.Parent = character
	end
end

-- Reliage des visuels aux attributs publiés par CombatService.
local function watchVisuals(character: Model, onWeaponChanged: (() -> ())?)
	updateWeaponVisual(character)
	updateArmorVisual(character)
	character:GetAttributeChangedSignal("WeaponId"):Connect(function()
		if onWeaponChanged then
			onWeaponChanged()
		end
		updateWeaponVisual(character)
	end)
	character:GetAttributeChangedSignal("WeaponSkin"):Connect(function()
		updateWeaponVisual(character)
	end)
	for _, piece in ARMOR_PIECES do
		character:GetAttributeChangedSignal(piece.attribute):Connect(function()
			updateArmorVisual(character)
		end)
		character:GetAttributeChangedSignal(piece.skin):Connect(function()
			updateArmorVisual(character)
		end)
	end
end

--[[
	Skins cosmétiques équipés par le joueur → attributs de son personnage
	(arme active, casque, gilet, sac). Appelé à l'apparition, au changement
	d'arme et quand le joueur équipe un cosmétique.
]]
function CharacterService.applySkins(player: Player)
	local character = player.Character
	local profile = DataService.getProfile(player)
	if character == nil or profile == nil then
		return
	end
	local equipped = profile.cosmeticsEquipped
	local weaponId = character:GetAttribute("WeaponId")
	character:SetAttribute("WeaponSkin", if type(weaponId) == "string" then equipped["weapon:" .. weaponId] else nil)
	character:SetAttribute("HelmetSkin", equipped.helmet)
	character:SetAttribute("VestSkin", equipped.vest)
	character:SetAttribute("BackpackSkin", equipped.backpack)
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

--[[
	Sac de partie de départ. Par défaut (arène de test, stand de tir) : une
	COPIE de l'équipement du profil (bac à sable : rien n'est perdu), ou le
	kit de base si le joueur n'a pas d'arme. Le déroulé de partie (P3)
	remplace ce fournisseur par le vrai sac de la partie.
]]
local function defaultLoadout(player: Player): InventoryLogic.Inventory?
	local profile = DataService.waitForProfile(player, 10)
	if profile and (profile.loadout.ranged or profile.loadout.melee) then
		return InventoryLogic.new(Freeze.copy(profile.loadout), Freeze.copy(profile.bag))
	end
	local kitLoadout, kitBag = ItemFactory.createBaseKit()
	return InventoryLogic.new(kitLoadout, kitBag)
end

local loadoutProvider: (player: Player) -> InventoryLogic.Inventory? = defaultLoadout

function CharacterService.setLoadoutProvider(provider: ((player: Player) -> InventoryLogic.Inventory?)?)
	loadoutProvider = provider or defaultLoadout
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

	local bag = loadoutProvider(player)
	if bag == nil or character.Parent == nil or player.Character ~= character then
		return
	end
	local equipped = bag.equipped
	local fighter = Fighter.new("player", player, character, humanoid, root, {
		ranged = equipped.ranged,
		melee = equipped.melee,
		helmet = equipped.helmet,
		vest = equipped.vest,
	}, Fighter.simpleInventory({}))
	CombatService.register(fighter)
	InventoryService.attach(fighter, bag)
	CharacterService.applySkins(player)
	watchVisuals(character, function()
		CharacterService.applySkins(player)
	end)
	applyStance(fighter)
	character.Destroying:Connect(function()
		rootJointC0[character] = nil
	end)
end

-- Visuels d'un combattant non joueur (mercenaire IA) : arme en main et posture.
function CharacterService.attachVisuals(fighter: Fighter)
	local character = fighter.character
	watchVisuals(character, nil)
	applyStance(fighter)
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
