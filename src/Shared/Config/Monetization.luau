--!strict
--[[
	Monétisation cosmétique (sections 14.5 à 14.10).

	⚠ Les identifiants de produits (`productId`, `gamePassId`) sont à
	renseigner une fois les produits créés sur le Creator Dashboard.
	Tant qu'ils valent 0, les achats correspondants sont désactivés.
]]

local Freeze = require(script.Parent.Parent.Util.Freeze)

export type CrateDef = {
	id: string,
	price: number, -- en Noyaux
	-- Probabilités (%) par rareté. La somme doit faire exactement 100.
	odds: { [string]: number },
	pity: { threshold: number, minRarity: string },
}

local rarities = { "common", "rare", "epic", "legendary", "mythic" }

local crates: { [string]: CrateDef } = {
	rust = {
		id = "rust",
		price = 50,
		odds = { common = 60, rare = 28, epic = 10, legendary = 2, mythic = 0 },
		pity = { threshold = 10, minRarity = "epic" },
	},
	neon = {
		id = "neon",
		price = 150,
		odds = { common = 45, rare = 30, epic = 18, legendary = 6, mythic = 1 },
		pity = { threshold = 30, minRarity = "legendary" },
	},
	prototype = {
		id = "prototype",
		price = 300,
		odds = { common = 0, rare = 50, epic = 35, legendary = 12, mythic = 3 },
		pity = { threshold = 60, minRarity = "mythic" },
	},
}

return Freeze.deep({
	rarities = rarities,
	rarityColors = {
		common = Color3.fromRGB(154, 160, 166),
		rare = Color3.fromRGB(59, 167, 255),
		epic = Color3.fromRGB(176, 92, 255),
		legendary = Color3.fromRGB(255, 176, 32),
		mythic = Color3.fromRGB(255, 46, 196),
	},

	-- Prix d'achat direct au Holo-Bazar (les Mythiques : caisses uniquement).
	directPrices = { common = 100, rare = 250, epic = 500, legendary = 1000 },

	bazaar = {
		featuredCount = 6,
		rotationPeriod = 24 * 60 * 60, -- renouvellement à 00:00 UTC
	},

	-- Valeur d'un cosmétique par rareté (prix direct ; Mythique : valeur de référence).
	rarityValue = { common = 100, rare = 250, epic = 500, legendary = 1000, mythic = 2000 },
	-- Doublon de caisse : converti en 20 % de la valeur de l'objet, en Noyaux.
	duplicateRefundShare = 0.20,

	crates = crates,

	noyauxPacks = {
		small = { order = 1, robux = 80, noyaux = 100, productId = 0 },
		medium = { order = 2, robux = 400, noyaux = 550, productId = 0 },
		large = { order = 3, robux = 800, noyaux = 1200, productId = 0 },
		huge = { order = 4, robux = 1700, noyaux = 2700, productId = 0 },
	},

	vaultExtension = {
		robux = 199,
		gamePassId = 0,
	},

	-- Nombre de reçus mémorisés dans le profil pour l'idempotence.
	maxRememberedReceipts = 200,
	maxNoyaux = 100_000_000,
})
