--!nocheck
-- Terminus : PNJ et textes du décor traduits.

return function(T, H)
	local describe, it, expect = T.describe, T.it, T.expect
	-- Vraies Instances (Lune) : le Terminus est construit pour inspecter ses textes.
	H.useInstances()
	local Localization = H.require("ReplicatedStorage/Shared/Localization")
	-- Services utilisés à la construction uniquement (pas appelés par ces tests).
	H.setService("CollectionService", {
		AddTag = function() end,
		HasTag = function()
			return false
		end,
	})
	H.setService("Players", {})
	local HubNpcs = H.require("ServerScriptService/Server/Hub/HubNpcs")

	describe("Terminus", function()
		it("chaque PNJ a un nom et 3 répliques (FR et EN)", function()
			local count = 0
			for station, id in HubNpcs.ids() do
				count += 1
				for _, lang in { "fr", "en" } do
					expect(Localization.has(lang, `npc.{id}.name`)).toBe(true)
					expect(Localization.has(lang, "station." .. station)).toBe(true)
					for line = 1, 3 do
						expect(Localization.has(lang, `npc.{id}.line.{line}`)).toBe(true)
					end
				end
			end
			expect(count).toBe(8)
		end)

		it("affiches, tags et écrans traduits", function()
			for _, lang in { "fr", "en" } do
				for index = 1, 3 do
					expect(Localization.has(lang, "hub.poster." .. index)).toBe(true)
					expect(Localization.has(lang, "hub.monitor." .. index)).toBe(true)
				end
				for index = 1, 6 do
					expect(Localization.has(lang, "hub.graffiti." .. index)).toBe(true)
				end
			end
		end)

		it("fresques des murs : une par station, traduites", function()
			local HubDress = H.require("ServerScriptService/Server/Hub/HubDress")
			local stations = {}
			for station in HubNpcs.ids() do
				stations[station] = true
			end
			for _, key in HubDress.MURALS do
				-- Chaque fresque correspond à une vraie station du Terminus.
				expect(stations[key]).toBe(true)
				for _, lang in { "fr", "en" } do
					expect(Localization.has(lang, "hub.wall." .. key)).toBe(true)
				end
			end
		end)
	end)

	describe("Textes du décor du Terminus", function()
		local roblox = require("@lune/roblox")
		local Vector3 = roblox.Vector3
		H.setService("Workspace", roblox.Instance.new("Folder"))
		local TerminusBuilder = H.require("ServerScriptService/Server/Hub/TerminusBuilder")
		local built = TerminusBuilder.build(Vector3.new(0, 0, 0))
		local NORMALS = {
			Front = Vector3.new(0, 0, -1),
			Back = Vector3.new(0, 0, 1),
			Left = Vector3.new(-1, 0, 0),
			Right = Vector3.new(1, 0, 0),
			Top = Vector3.new(0, 1, 0),
			Bottom = Vector3.new(0, -1, 0),
		}
		local labels = {}
		for _, descendant in built.folder:GetDescendants() do
			if descendant:IsA("TextLabel") and descendant:GetAttribute("TextKey") ~= nil then
				table.insert(labels, descendant)
			end
		end

		it("enseignes, fresques, affiches, tags et Mur des Légendes ont une clé traduite", function()
			expect(#labels >= 25).toBe(true)
			for _, label in labels do
				local key = label:GetAttribute("TextKey")
				expect(Localization.has("fr", key) and Localization.has("en", key)).toBe(true)
				-- Texte vide côté serveur : c'est le client qui le remplit (UI/TextKeys).
				expect(label.Text).toBe("")
			end
		end)

		it("rien ne masque un texte (aucune pièce collée devant)", function()
			local parts = {}
			for _, descendant in built.folder:GetDescendants() do
				if descendant:IsA("BasePart") and descendant.Transparency < 0.9 then
					table.insert(parts, descendant)
				end
			end
			local hidden = 0
			for _, label in labels do
				local gui = label.Parent
				local part = gui.Parent
				local n = NORMALS[gui.Face.Name]
				local half = math.abs(n.X) * part.Size.X / 2
					+ math.abs(n.Y) * part.Size.Y / 2
					+ math.abs(n.Z) * part.Size.Z / 2
				local front = part.CFrame.Position + part.CFrame:VectorToWorldSpace(n) * (half + 0.05)
				for _, other in parts do
					local p = other.CFrame:PointToObjectSpace(front)
					local h = other.Size / 2
					if other ~= part and math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z then
						hidden += 1
						print("    texte masqué : " .. label:GetAttribute("TextKey") .. " par " .. other.Name)
					end
				end
			end
			expect(hidden).toBe(0)
		end)
	end)
end
