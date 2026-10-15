--!strict
--[[
	TextKeys : textes localisés posés dans le décor (enseignes, affiches,
	plaques des PNJ, Mur des Légendes, décor du tutoriel…).

	Le serveur crée les TextLabel avec un attribut `TextKey` et sans texte ;
	ici on les remplit. Fiable quel que soit l'ordre d'arrivée : les textes
	déjà présents sont remplis tout de suite, ceux qui arrivent ensuite (PNJ
	créés plus tard, décor reconstruit) dès leur arrivée, et tout est
	re-traduit au changement de langue (`refresh`). Aucune condition de
	distance : un texte est posé une fois pour toutes.
]]

local TextKeys = {}

type Translate = (key: string, params: { [string]: any }?) -> string

local translate: Translate = function(key: string)
	return key
end
local watched: { [Instance]: RBXScriptConnection } = {}

local function apply(instance: Instance)
	if instance:IsA("TextLabel") or instance:IsA("TextButton") then
		local key = instance:GetAttribute("TextKey")
		if type(key) == "string" then
			instance.Text = translate(key)
		end
	end
end

local function applyAll(root: Instance)
	for _, descendant in root:GetDescendants() do
		apply(descendant)
	end
end

-- Fonction de traduction (ProfileController.t) : à donner avant tout `watch`.
function TextKeys.setTranslator(t: Translate)
	translate = t
end

-- Remplit les textes de `root` et de tout ce qui y sera ajouté ensuite.
function TextKeys.watch(root: Instance)
	if watched[root] then
		applyAll(root)
		return
	end
	applyAll(root)
	watched[root] = root.DescendantAdded:Connect(function(descendant)
		-- L'attribut est posé avant le parentage, mais un ancêtre peut arriver
		-- avant ses enfants : chaque ajout est traité à son arrivée.
		apply(descendant)
	end)
	root.Destroying:Connect(function()
		local connection = watched[root]
		if connection then
			connection:Disconnect()
			watched[root] = nil
		end
	end)
end

-- Re-traduit tous les textes suivis (changement de langue).
function TextKeys.refresh()
	for root in watched do
		if root.Parent == nil then
			watched[root]:Disconnect()
			watched[root] = nil
		else
			applyAll(root)
		end
	end
end

return TextKeys
