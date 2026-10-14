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

	-- Ouverture d'une caisse du Holo-Bazar (14.10), en secondes : des lasers
	-- assemblent la caisse en gros pixels, puis en pixels de plus en plus fins
	-- jusqu'à la caisse complète ; un scanner la balaie ; elle s'ouvre et
	-- l'objet obtenu en sort et flotte au-dessus. « Passer » saute à la fin.
	crateOpening = {
		phases = {
			{ name = "coarse", duration = 0.9 }, -- gros pixels
			{ name = "fine", duration = 1.2 }, -- pixels fins
			{ name = "solidify", duration = 0.45 }, -- la caisse se solidifie
			{ name = "scan", duration = 1.4 }, -- scanner, aller-retour
			{ name = "open", duration = 0.8 }, -- secousse, couvercle
			{ name = "rise", duration = 0.9 }, -- l'objet sort et monte
		},
		crateSize = Vector3.new(4, 2.4, 2.6),
		coarseCell = 1.25, -- taille des gros pixels (studs)
		fineCell = 0.6,
		itemSize = 3.2, -- plus grande dimension de l'objet flottant (studs)
		floatHeight = 4.6, -- hauteur de l'objet au-dessus du sol de la scène
	},

	-- Valeur d'un cosmétique par rareté (prix direct ; Mythique : valeur de référence).
	rarityValue = { common = 100, rare = 250, epic = 500, legendary = 1000, mythic = 2000 },
	-- Doublon de caisse : converti en 20 % de la valeur de l'objet, en Noyaux.
	duplicateRefundShare = 0.20,

	crates = crates,

	noyauxPacks = {
		small = { order = 1, robux = 80, noyaux = 100, productId = 3718226486 },
		medium = { order = 2, robux = 400, noyaux = 550, productId = 3718226650 },
		large = { order = 3, robux = 800, noyaux = 1200, productId = 3718226747 },
		huge = { order = 4, robux = 1700, noyaux = 2700, productId = 3718226827 },
	},

	vaultExtension = {
		robux = 199,
		gamePassId = 2030534275,
	},

	-- Nombre de reçus mémorisés dans le profil pour l'idempotence.
	maxRememberedReceipts = 200,
	maxNoyaux = 100_000_000,
})
