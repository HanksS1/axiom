--!strict
--[[
	ClickShield : un menu ouvert n'est pas « cliquable à travers ».

	Sous le menu, un bouton plein écran (et non un simple cadre : un cadre
	laisse passer les clics) absorbe les clics, touchers et appuis qui
	tombent à côté du menu ou dans ses zones vides : rien de ce qui est en
	dessous (HUD, autre écran, bouton de la station) ne réagit par erreur.
	C'est le principe déjà en place pour l'ouverture des caisses du Holo-Bazar.

	- Le bouclier suit le menu : visible avec lui, même parent, juste sous lui
	  (ZIndex − 1), détruit avec lui. Deux menus ouverts ensemble au même niveau
	  (sac et conteneur en partie) restent utilisables tous les deux.
	- Un clic sur le bouclier ne fait rien (il ne ferme pas le menu : fermer se
	  fait par le bouton ✕ ou la touche du menu, jamais par un clic égaré).
	- Ignoré par la navigation à la manette (`Selectable = false`).
	- Le joystick et le bouton de saut de Roblox (écran tactile) sont dans leur
	  propre ScreenGui : ils ne sont pas couverts.
]]

local Create = require(script.Parent.Create)
local Theme = require(script.Parent.Theme)

local ClickShield = {}

--[[
	Pose un bouclier sous `menu`. `transparency` : voile (1 = invisible, par
	défaut Theme.shieldTransparency : léger assombrissement de ce qui est
	derrière). Retourne le bouclier.
]]
function ClickShield.attach(menu: GuiObject, transparency: number?): TextButton
	local shield = Create("TextButton", {
		Name = menu.Name .. "Shield",
		AnchorPoint = Vector2.zero,
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.background,
		BackgroundTransparency = transparency or Theme.shieldTransparency,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = true,
		Selectable = false,
		Text = "",
		ZIndex = math.max(1, menu.ZIndex - 1),
		Visible = menu.Visible,
		Parent = menu.Parent,
	})
	menu:GetPropertyChangedSignal("Visible"):Connect(function()
		shield.Visible = menu.Visible
	end)
	menu:GetPropertyChangedSignal("Parent"):Connect(function()
		if menu.Parent then
			shield.Parent = menu.Parent
		end
	end)
	menu:GetPropertyChangedSignal("ZIndex"):Connect(function()
		shield.ZIndex = math.max(1, menu.ZIndex - 1)
	end)
	menu.Destroying:Connect(function()
		shield:Destroy()
	end)
	return shield
end

return ClickShield
