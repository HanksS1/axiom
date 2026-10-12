--!strict
--[[
	Fighter : état de combat d'un personnage (joueur, et plus tard robot ou
	mercenaire IA). Créé par CombatService à l'apparition du personnage.

	L'inventaire est abstrait (`FighterInventory`) : en P1, une simple
	réserve de cellules ; en P2, le vrai sac de la partie.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local InventoryLogic = require(Shared.Items.InventoryLogic)
local ItemRules = require(Shared.Items.ItemRules)
local Movement = require(Shared.Combat.Movement)
local WeaponLogic = require(Shared.Combat.WeaponLogic)

type ItemInstance = Types.ItemInstance

export type FighterInventory = {
	countCells: (self: FighterInventory, cellId: string) -> number,
	takeCells: (self: FighterInventory, cellId: string, amount: number) -> number,
}

export type WeaponSlot = "ranged" | "melee"

export type RangedWeapon = {
	item: ItemInstance,
	def: any,
	state: WeaponLogic.RangedState,
}

export type MeleeWeapon = {
	item: ItemInstance,
	def: any,
	lastAttackAt: number,
}

export type Fighter = {
	kind: "player" | "bot" | "robot",
	player: Player?,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,

	health: number,
	shield: number,
	maxShield: number,
	helmet: ItemInstance?,
	vest: ItemInstance?,

	ranged: RangedWeapon?,
	melee: MeleeWeapon?,
	activeSlot: WeaponSlot,
	inventory: FighterInventory,
	-- Sac de partie (joueurs, mercenaires IA) ; nil pour les cibles simples.
	bag: InventoryLogic.Inventory?,
	onInventoryChanged: (() -> ())?,

	move: Movement.MoveState,
	sprintEndedAt: number,
	proneUntil: number, -- fin de la transition vers / depuis la position couchée

	parryStartedAt: number,
	parryCooldownUntil: number,
	parryPerfected: boolean, -- une parade parfaite a eu lieu pendant cette garde
	stunnedUntil: number,
	slowUntil: number,
	slowMultiplier: number,
	boostUntil: number, -- Surcharge (+20 % de vitesse)
	boostMultiplier: number,

	usingItemId: string?, -- consommable en cours d'utilisation
	usingUntil: number,
	usingToken: number,
	exoUsed: boolean,

	lastShotTime: number, -- horodatage du dernier tir accepté (anti-retour en arrière)
	dead: boolean,
	lastAttacker: Fighter?,
}

local Fighter = {}

-- État des armes à distance par uid d'objet (chargeur, chaleur), pour la partie en cours.
local weaponStates: { [string]: WeaponLogic.RangedState } = {}

-- Réserve de cellules simple (P1 : stand de tir / arène).
function Fighter.simpleInventory(cells: { [string]: number }): FighterInventory
	local inventory = {} :: any
	function inventory:countCells(cellId: string): number
		return cells[cellId] or 0
	end
	function inventory:takeCells(cellId: string, amount: number): number
		local available = cells[cellId] or 0
		local taken = math.clamp(math.floor(amount), 0, available)
		cells[cellId] = available - taken
		return taken
	end
	return inventory :: FighterInventory
end

-- Compte les cellules d'un sac (liste d'objets) par type.
function Fighter.cellsFromBag(bag: { ItemInstance }): { [string]: number }
	local cells = {}
	for _, item in bag do
		local info = ItemCatalog.get(item.itemId)
		if info and info.category == "cell" then
			cells[item.itemId] = (cells[item.itemId] or 0) + (item.stack or 0)
		end
	end
	return cells
end

export type Equipment = {
	ranged: ItemInstance?,
	melee: ItemInstance?,
	helmet: ItemInstance?,
	vest: ItemInstance?,
}

function Fighter.new(
	kind: "player" | "bot" | "robot",
	player: Player?,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	equipment: Equipment,
	inventory: FighterInventory
): Fighter
	local maxShield = ItemRules.maxShield(equipment.vest)
	local fighter: Fighter = {
		kind = kind,
		player = player,
		character = character,
		humanoid = humanoid,
		root = root,
		health = Config.Combat.maxHealth,
		shield = maxShield,
		maxShield = maxShield,
		helmet = equipment.helmet,
		vest = equipment.vest,
		ranged = nil,
		melee = nil,
		activeSlot = "ranged",
		inventory = inventory,
		move = {
			stance = "stand",
			sprinting = false,
			parrying = false,
			stunned = false,
			speedMultiplier = 1,
			usingConsumable = nil,
		},
		sprintEndedAt = -math.huge,
		proneUntil = 0,
		parryStartedAt = -math.huge,
		parryCooldownUntil = 0,
		parryPerfected = false,
		stunnedUntil = 0,
		slowUntil = 0,
		slowMultiplier = 1,
		boostUntil = 0,
		boostMultiplier = 1,
		usingItemId = nil,
		usingUntil = 0,
		usingToken = 0,
		exoUsed = false,
		bag = nil,
		onInventoryChanged = nil,
		lastShotTime = -math.huge,
		dead = false,
		lastAttacker = nil,
	}
	Fighter.setWeapon(fighter, "ranged", equipment.ranged)
	Fighter.setWeapon(fighter, "melee", equipment.melee)
	if fighter.ranged == nil and fighter.melee ~= nil then
		fighter.activeSlot = "melee"
	end
	return fighter
end

function Fighter.setWeapon(fighter: Fighter, slot: WeaponSlot, item: ItemInstance?)
	if item == nil then
		if slot == "ranged" then
			fighter.ranged = nil
		else
			fighter.melee = nil
		end
		return
	end
	local info = ItemCatalog.get(item.itemId)
	assert(info and info.category == slot, `objet {item.itemId} incompatible avec l'emplacement {slot}`)
	if slot == "ranged" then
		-- L'état (chargeur, chaleur) suit l'objet : jeter puis reprendre une
		-- arme ne la recharge pas. Une arme jamais utilisée apparaît chargée.
		local state = weaponStates[item.uid]
		if state == nil then
			state = WeaponLogic.new(info.def)
			weaponStates[item.uid] = state
		end
		WeaponLogic.cancelReload(state)
		fighter.ranged = { item = item, def = info.def, state = state }
	else
		fighter.melee = { item = item, def = info.def, lastAttackAt = -math.huge }
	end
end

-- Met à jour les états temporaires (étourdissement, ralentissement, surcharge, consommable).
function Fighter.refresh(fighter: Fighter, now: number)
	fighter.move.stunned = now < fighter.stunnedUntil
	local slow = if now < fighter.slowUntil then fighter.slowMultiplier else 1
	local boost = if now < fighter.boostUntil then fighter.boostMultiplier else 1
	fighter.move.speedMultiplier = slow * boost
	if fighter.usingItemId ~= nil and now >= fighter.usingUntil then
		fighter.usingItemId = nil
	end
	if fighter.usingItemId then
		local info = ItemCatalog.get(fighter.usingItemId)
		fighter.move.usingConsumable = if info then info.def.moveSpeedMultiplierWhileUsing else nil
	else
		fighter.move.usingConsumable = nil
	end
end

-- Inventaire « sac de partie » : cellules prélevées dans les vraies piles.
function Fighter.bagInventory(fighter: Fighter): FighterInventory
	local inventory = {} :: any
	function inventory:countCells(cellId: string): number
		local bag = fighter.bag
		return if bag then InventoryLogic.count(bag, cellId) else 0
	end
	function inventory:takeCells(cellId: string, amount: number): number
		local bag = fighter.bag
		if bag == nil then
			return 0
		end
		local taken = InventoryLogic.consume(bag, cellId, amount)
		if taken > 0 and fighter.onInventoryChanged then
			fighter.onInventoryChanged()
		end
		return taken
	end
	return inventory :: FighterInventory
end

--[[
	Aligne armes, casque, gilet et bouclier max sur les emplacements équipés
	du sac (après un ramassage, un échange, un objet jeté…).
]]
function Fighter.syncEquipment(fighter: Fighter)
	local bag = fighter.bag
	if bag == nil then
		return
	end
	local equipped = bag.equipped
	local ranged = equipped.ranged
	if ranged == nil or fighter.ranged == nil or fighter.ranged.item.uid ~= ranged.uid then
		Fighter.setWeapon(fighter, "ranged", ranged)
	end
	local melee = equipped.melee
	if melee == nil or fighter.melee == nil or fighter.melee.item.uid ~= melee.uid then
		Fighter.setWeapon(fighter, "melee", melee)
	end
	if fighter.activeSlot == "ranged" and fighter.ranged == nil and fighter.melee ~= nil then
		fighter.activeSlot = "melee"
	elseif fighter.activeSlot == "melee" and fighter.melee == nil and fighter.ranged ~= nil then
		fighter.activeSlot = "ranged"
	end
	fighter.helmet = equipped.helmet
	fighter.vest = equipped.vest
	fighter.maxShield = ItemRules.maxShield(equipped.vest)
	-- Le bouclier ne se recharge qu'avec une batterie : un nouveau gilet ne
	-- remplit pas la barre, on se contente de la borner.
	fighter.shield = math.min(fighter.shield, fighter.maxShield)
end

-- Oublie l'état des armes (fin de partie).
function Fighter.clearWeaponStates()
	table.clear(weaponStates)
end

function Fighter.isAlive(fighter: Fighter): boolean
	return not fighter.dead and fighter.health > 0
end

return Fighter
