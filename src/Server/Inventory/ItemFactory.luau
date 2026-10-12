--!strict
--[[
	ItemFactory : SEUL endroit où naissent de nouvelles instances d'objets.
	Chaque objet reçoit un uid unique généré par le serveur.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Types = require(Shared.Types)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local ItemRules = require(Shared.Items.ItemRules)

local Uid = require(script.Parent.Parent.Util.Uid)

type ItemInstance = Types.ItemInstance

local ItemFactory = {}

-- Générateur d'uid injectable (tests).
ItemFactory.generateUid = Uid.new

export type CreateOptions = {
	condition: number?,
	stack: number?,
	isKit: boolean?,
	tempGamesLeft: number?,
}

function ItemFactory.create(itemId: string, options: CreateOptions?): ItemInstance
	local info = ItemCatalog.get(itemId)
	assert(info ~= nil, `itemId inconnu : {itemId}`)
	local opts: CreateOptions = options or {}
	local item: ItemInstance = {
		uid = ItemFactory.generateUid(),
		itemId = itemId,
		isKit = if opts.isKit then true else nil,
		tempGamesLeft = opts.tempGamesLeft,
	}
	if info.hasCondition then
		item.condition = opts.condition or Config.Conditions.GOOD
	end
	if info.stackSize ~= nil then
		item.stack = math.clamp(opts.stack or info.stackSize, 1, info.stackSize)
	end
	local ok, reason = ItemRules.validate(item)
	assert(ok, `objet créé invalide ({itemId}) : {reason}`)
	return item
end

-- Kit de base gratuit (section 8.8) : emplacements + contenu du sac.
function ItemFactory.createBaseKit(): (Types.Loadout, { ItemInstance })
	local kit = Config.Economy.baseKit
	local loadout: Types.Loadout = {
		ranged = ItemFactory.create(kit.ranged.itemId, { condition = kit.ranged.condition, isKit = true }),
		melee = ItemFactory.create(kit.melee.itemId, { condition = kit.melee.condition, isKit = true }),
		backpack = ItemFactory.create(kit.backpack.itemId, { condition = kit.backpack.condition, isKit = true }),
	}
	local bag = {}
	for _, entry in kit.bag do
		table.insert(bag, ItemFactory.create(entry.itemId, { stack = entry.stack, isKit = true }))
	end
	return loadout, bag
end

return ItemFactory
