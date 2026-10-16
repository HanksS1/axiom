--!strict
--[[
	SpaceCheck : « est-ce que ça rentre, et sinon de combien ça dépasse ? »
	(logique pure, testée). Sert à l'INTERFACE pour signaler un refus avant
	toute tentative ; le serveur garde ses propres contrôles (l'état peut
	changer entre-temps) et ces fonctions reprennent exactement ses règles :

	- `intoBag` : ramassage dans le sac de partie (InventoryLogic.canStore :
	  les piles fusionnent d'abord avec les piles entamées) ;
	- `intoVault` : achat chez le Marchand (EconomyRules.buy : une pile achetée
	  complète d'abord les piles entamées du coffre) ;
	- `keepInVault` : objet entier rangé au coffre, sans fusion de piles
	  (EconomyRules.keepPending, bagToVault) ;
	- `vaultToBag` : coffre → sac préparé (EconomyRules.vaultToBag).

	`missing` : UP à libérer pour que ça rentre (0 si ça rentre).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local InventoryLogic = require(Shared.Items.InventoryLogic)
local ItemCatalog = require(Shared.Items.ItemCatalog)
local ItemRules = require(Shared.Items.ItemRules)
local Types = require(Shared.Types)

type ItemInstance = Types.ItemInstance

export type Fit = { fits: boolean, missing: number }

local SpaceCheck = {}

local FITS: Fit = table.freeze({ fits = true, missing = 0 })

local function short(needed: number, free: number): Fit
	if free >= needed then
		return FITS
	end
	return { fits = false, missing = needed - free }
end

function SpaceCheck.intoBag(inventory: InventoryLogic.Inventory, item: ItemInstance): Fit
	if InventoryLogic.canStore(inventory, item) then
		return FITS
	end
	return short(ItemRules.up(item), InventoryLogic.free(inventory))
end

--[[
	Objet `itemId` (pile de `amount`, sinon pile entière) reçu par un coffre
	qui contient `vault` pour `capacity` UP.
]]
function SpaceCheck.intoVault(vault: { ItemInstance }, capacity: number, itemId: string, amount: number?): Fit
	local info = ItemCatalog.get(itemId)
	if info == nil then
		return FITS
	end
	local free = capacity - ItemRules.totalUp(vault)
	local stackSize = info.stackSize
	if stackSize then
		local wanted = math.clamp(amount or stackSize, 1, stackSize)
		local room = 0
		for _, owned in vault do
			if owned.itemId == itemId then
				room += math.max(0, stackSize - (owned.stack or 1))
			end
		end
		if wanted <= room then
			return FITS
		end
	end
	return short(info.up, free)
end

-- Objet entier rangé au coffre (tri d'après-partie, sac préparé → coffre).
function SpaceCheck.keepInVault(vault: { ItemInstance }, capacity: number, item: ItemInstance): Fit
	return short(ItemRules.up(item), capacity - ItemRules.totalUp(vault))
end

-- Coffre → sac préparé (le sac porté fixe la capacité).
function SpaceCheck.vaultToBag(bag: { ItemInstance }, backpack: ItemInstance?, item: ItemInstance): Fit
	return short(ItemRules.up(item), ItemRules.bagCapacity(backpack) - ItemRules.totalUp(bag))
end

return SpaceCheck
