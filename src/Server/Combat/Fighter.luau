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

	move: Movement.MoveState,
	sprintEndedAt: number,
	proneUntil: number, -- fin de la transition vers / depuis la position couchée

	parryStartedAt: number,
	parryCooldownUntil: number,
	parryPerfected: boolean, -- une parade parfaite a eu lieu pendant cette garde
	stunnedUntil: number,
	slowUntil: number,
	slowMultiplier: number,

	lastShotTime: number, -- horodatage du dernier tir accepté (anti-retour en arrière)
	dead: boolean,
	lastAttacker: Fighter?,
}

local Fighter = {}

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
		-- L'arme apparaît chargée (le chargeur n'est pas modélisé dans le sac).
		fighter.ranged = { item = item, def = info.def, state = WeaponLogic.new(info.def) }
	else
		fighter.melee = { item = item, def = info.def, lastAttackAt = -math.huge }
	end
end

-- Met à jour les états temporaires (étourdissement, ralentissement).
function Fighter.refresh(fighter: Fighter, now: number)
	fighter.move.stunned = now < fighter.stunnedUntil
	local slow = if now < fighter.slowUntil then fighter.slowMultiplier else 1
	fighter.move.speedMultiplier = slow
end

function Fighter.isAlive(fighter: Fighter): boolean
	return not fighter.dead and fighter.health > 0
end

return Fighter
