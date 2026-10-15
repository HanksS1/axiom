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
	- Visuels provisoires : arme tenue (R15 : montée devant le torse, les
	  clients y posent les mains, voir WeaponPoseController), casque, gilet et
	  sac portés, postures accroupi / couché. Les skins cosmétiques équipés (P9) en
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
local ItemModels = require(Shared.Visuals.ItemModels)
local WeaponPose = require(Shared.Visuals.WeaponPose)
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)

type Fighter = Fighter.Fighter

local Visuals = Config.Visuals
local MovementConfig = Config.Combat.movement

local CharacterService = {}

local rootJointC0: { [Model]: CFrame } = {}
local skinOf: (character: Model, attribute: string) -> any?

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

-- Première pièce du personnage parmi `names` (R15, puis R6).
local function bodyPart(character: Model, names: { string }): BasePart?
	for _, name in names do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

-- Remplace le visuel `name` du personnage par les pièces posées par `fill` (aucune : rien).
local function setVisual(character: Model, name: string, fill: ((model: Model) -> ())?)
	local existing = character:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	if fill == nil then
		return
	end
	local model = Instance.new("Model")
	model.Name = name
	fill(model)
	local body = model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		model.PrimaryPart = body
	end
	if #model:GetChildren() > 0 then
		model.Parent = character
	else
		model:Destroy()
	end
end

--[[
	Arme tenue (même modèle que les icônes : Shared/Visuals/ItemModels), mise à
	jour quand l'arme active ou son skin change.

	Arme à distance sur un avatar R15 : montée devant le haut du torse par un
	joint « WeaponGrip » (position de repos : Shared/Visuals/WeaponPose) ;
	chaque client l'anime et y pose les deux mains. Elle ne suit donc plus le
	balancement des bras.
	Arme de mêlée (et avatar R6) : soudée à la main droite ; le client anime
	le bras pendant un coup.
]]
local function updateWeaponVisual(character: Model)
	local weaponId = character:GetAttribute("WeaponId")
	local torso = bodyPart(character, { "UpperTorso" })
	local hand = bodyPart(character, { "RightHand", "Right Arm" })
	local shape = if type(weaponId) == "string" then Visuals.weapons[weaponId] else nil
	if hand == nil or shape == nil then
		setVisual(character, "WeaponVisual", nil)
		return
	end
	local mounted = torso ~= nil
		and character:FindFirstChild("RightUpperArm") ~= nil
		and WeaponPose.isMounted(weaponId :: string)
	setVisual(character, "WeaponVisual", function(model)
		model:SetAttribute("ItemId", weaponId)
		local skin = skinOf(character, "WeaponSkin")
		if not mounted or torso == nil then
			-- Le cœur de l'arme (« Body ») se place par rapport à la main ; tout le reste suit.
			ItemModels.place(weaponId :: string, model, hand.CFrame * shape.gripOffset, {
				skin = skin,
				weldTo = hand,
			})
			return
		end
		local rest = WeaponPose.rest(weaponId :: string, WeaponPose.scaleOf(torso.Size))
		local parts = ItemModels.place(weaponId :: string, model, torso.CFrame * rest, { skin = skin })
		local body = model:FindFirstChild("Body")
		if body == nil or not body:IsA("BasePart") then
			return
		end
		-- Toutes les pièces suivent le cœur ; le cœur suit le torse par le joint.
		for _, part in parts do
			if part ~= body then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = body
				weld.Part1 = part
				weld.Parent = part
			end
			part.Anchored = false
		end
		local joint = Instance.new("Motor6D")
		joint.Name = "WeaponGrip"
		joint.Part0 = torso
		joint.Part1 = body
		joint.C0 = rest
		joint.C1 = CFrame.identity
		joint.Parent = body
	end)
end

--[[
	Casque, gilet et sac portés : les mêmes modèles que dans les caisses, mis à
	l'échelle du personnage, aux couleurs du skin équipé.
]]
local function updateArmorVisual(character: Model)
	local head = bodyPart(character, { "Head" })
	local torso = bodyPart(character, { "UpperTorso", "Torso" })

	local helmetId = character:GetAttribute("HelmetId")
	setVisual(
		character,
		"HelmetVisual",
		if type(helmetId) == "string" and head
			then function(model)
				local base = head :: BasePart
				-- Le casque coiffe la tête : échelle sur sa plus petite dimension.
				local scale = math.min(base.Size.X, base.Size.Y, base.Size.Z) * 1.12 / 1.25
				ItemModels.place(helmetId, model, base.CFrame * CFrame.new(0, base.Size.Y * 0.12, 0), {
					skin = skinOf(character, "HelmetSkin"),
					scale = scale,
					weldTo = base,
				})
			end
			else nil
	)

	local vestId = character:GetAttribute("VestId")
	local hasVest = type(vestId) == "string" and torso ~= nil
	setVisual(
		character,
		"VestVisual",
		if hasVest
			then function(model)
				local base = torso :: BasePart
				ItemModels.place(vestId :: string, model, base.CFrame * CFrame.new(0, -base.Size.Y * 0.04, 0), {
					skin = skinOf(character, "VestSkin"),
					scale = base.Size.X / 2 * 1.02,
					weldTo = base,
				})
			end
			else nil
	)

	local backpackId = character:GetAttribute("BackpackId")
	setVisual(
		character,
		"BackpackVisual",
		if type(backpackId) == "string" and torso
			then function(model)
				local base = torso :: BasePart
				local scale = base.Size.X / 2
				local blueprint = ItemModels.blueprint(backpackId)
				local depth = if blueprint then blueprint.parts[1].size.Z * scale else 0.75
				-- Dans le dos (par-dessus le gilet), bretelles contre le corps.
				local behind = base.Size.Z / 2 + depth / 2 + (if hasVest then 0.16 else 0.04)
				ItemModels.place(
					backpackId,
					model,
					base.CFrame * CFrame.new(0, 0, behind) * CFrame.Angles(0, math.pi, 0),
					{
						skin = skinOf(character, "BackpackSkin"),
						scale = scale,
						weldTo = base,
					}
				)
			end
			else nil
	)
end

-- Emplacement de chaque gadget sur le corps : pièce porteuse, position, échelle.
local GADGET_MOUNTS: { [string]: { parts: { string }, scale: number, offset: (base: BasePart) -> CFrame } } = {
	-- Lanceur le long de l'avant-bras gauche, griffe vers la main.
	grappling_hook = {
		parts = { "LeftLowerArm", "Left Arm" },
		scale = 0.7,
		offset = function(base)
			return CFrame.new(-(base.Size.X / 2 + 0.14), 0, 0) * CFrame.Angles(math.rad(-90), 0, 0)
		end,
	},
	-- Drone replié sur la cuisse droite.
	recon_drone = {
		parts = { "RightUpperLeg", "Right Leg" },
		scale = 0.5,
		offset = function(base)
			return CFrame.new(base.Size.X / 2 + 0.14, 0, 0) * CFrame.Angles(0, 0, math.rad(-90))
		end,
	},
	-- Panneaux du mur repliés sur la cuisse gauche.
	deployable_wall = {
		parts = { "LeftUpperLeg", "Left Leg" },
		scale = 0.5,
		offset = function(base)
			return CFrame.new(-(base.Size.X / 2 + 0.14), 0, 0) * CFrame.Angles(0, math.rad(90), 0)
		end,
	},
	-- Fumigène à la ceinture, à droite.
	smoke_deployer = {
		parts = { "LowerTorso", "Torso" },
		scale = 0.5,
		offset = function(base)
			return CFrame.new(base.Size.X / 2 - 0.15, -0.05, -(base.Size.Z / 2 + 0.2))
		end,
	},
}

local function placeGadget(character: Model, model: Model, itemId: string)
	if itemId == "jump_boots" then
		-- Une botte par pied (les pieds bougent séparément).
		for _, side in
			{ { parts = { "LeftFoot", "Left Leg" }, sign = -1 }, { parts = { "RightFoot", "Right Leg" }, sign = 1 } }
		do
			local foot = bodyPart(character, side.parts)
			if foot then
				local isFoot = foot.Name == "LeftFoot" or foot.Name == "RightFoot"
				-- R6 : au bas de la jambe.
				local at = if isFoot then CFrame.new(0, 0.04, 0) else CFrame.new(0, -foot.Size.Y / 2 + 0.2, 0)
				ItemModels.place(itemId, model, foot.CFrame * at, {
					scale = foot.Size.X * 1.12 / 0.5,
					weldTo = foot,
					shift = Vector3.new(-side.sign * 0.4, 0, 0),
					filter = function(spec)
						return spec.cframe.Position.X * side.sign > 0
					end,
				})
			end
		end
		return
	end
	local mount = GADGET_MOUNTS[itemId]
	local base = if mount then bodyPart(character, mount.parts) else nil
	if mount and base then
		ItemModels.place(itemId, model, base.CFrame * mount.offset(base), { scale = mount.scale, weldTo = base })
	end
end

-- Gadgets équipés, visibles sur le personnage (on sait ce que porte un adversaire).
local function updateGadgetVisual(character: Model)
	for index = 1, 2 do
		local itemId = character:GetAttribute(`Gadget{index}Id`)
		setVisual(
			character,
			`Gadget{index}Visual`,
			if type(itemId) == "string"
				then function(model)
					placeGadget(character, model, itemId)
				end
				else nil
		)
	end
end

-- Consommable en cours d'utilisation, dans la main gauche.
local function updateUsingVisual(character: Model)
	local itemId = character:GetAttribute("UsingId")
	local hand = bodyPart(character, { "LeftHand", "Left Arm" })
	setVisual(
		character,
		"UsingVisual",
		if type(itemId) == "string" and hand
			then function(model)
				local base = hand :: BasePart
				local low = if base.Name == "LeftHand" then 0 else -base.Size.Y / 2
				ItemModels.place(
					itemId,
					model,
					base.CFrame * CFrame.new(0, low - 0.1, -0.3),
					{ scale = 0.8, weldTo = base }
				)
			end
			else nil
	)
end

-- Reliage des visuels aux attributs publiés par CombatService.
local function watchVisuals(character: Model, onWeaponChanged: (() -> ())?)
	updateWeaponVisual(character)
	updateArmorVisual(character)
	updateGadgetVisual(character)
	updateUsingVisual(character)
	character:GetAttributeChangedSignal("WeaponId"):Connect(function()
		if onWeaponChanged then
			onWeaponChanged()
		end
		updateWeaponVisual(character)
	end)
	character:GetAttributeChangedSignal("WeaponSkin"):Connect(function()
		updateWeaponVisual(character)
	end)
	for _, attribute in { "HelmetId", "HelmetSkin", "VestId", "VestSkin", "BackpackId", "BackpackSkin" } do
		character:GetAttributeChangedSignal(attribute):Connect(function()
			updateArmorVisual(character)
		end)
	end
	for _, attribute in { "Gadget1Id", "Gadget2Id" } do
		character:GetAttributeChangedSignal(attribute):Connect(function()
			updateGadgetVisual(character)
		end)
	end
	character:GetAttributeChangedSignal("UsingId"):Connect(function()
		updateUsingVisual(character)
	end)
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
local function profileLoadout(profile: any?): InventoryLogic.Inventory
	if profile and (profile.loadout.ranged or profile.loadout.melee) then
		return InventoryLogic.new(Freeze.copy(profile.loadout), Freeze.copy(profile.bag))
	end
	local kitLoadout, kitBag = ItemFactory.createBaseKit()
	return InventoryLogic.new(kitLoadout, kitBag)
end

local function defaultLoadout(player: Player): InventoryLogic.Inventory?
	return profileLoadout(DataService.waitForProfile(player, 10))
end

local loadoutProvider: (player: Player) -> InventoryLogic.Inventory? = defaultLoadout

--[[
	Hors partie : l'équipement porté suit le profil dès qu'il change (arme équipée
	au coffre, achat, réparation), sans attendre une réapparition ni une partie.
	Sans effet en partie : le sac de partie fait foi (et le coffre y est fermé).
]]
function CharacterService.refreshLoadout(player: Player)
	if loadoutProvider ~= defaultLoadout then
		return
	end
	local fighter = CombatService.getFighter(player)
	local profile = DataService.getProfile(player)
	if fighter == nil or profile == nil or not Fighter.isAlive(fighter) or fighter.bag == nil then
		return
	end
	InventoryService.attach(fighter, profileLoadout(profile))
	CombatService.publish(fighter)
	CharacterService.applySkins(player)
end

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
