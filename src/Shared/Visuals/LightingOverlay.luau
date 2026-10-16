--!strict
--[[
	LightingOverlay : éclairage posé LOCALEMENT par un client au-dessus de celui
	du serveur, puis retiré sans rien abîmer (logique pure, testée).

	Cas d'usage : l'Arène FFA est voisine du Terminus, sur le même serveur. Son
	éclairage (Config.Arena.lighting) ne peut pas être réglé par le serveur
	sans assombrir ou éblouir tout le Terminus : c'est le client du joueur
	présent dans l'arène qui le pose.

	- `enter` mémorise les valeurs du serveur et retourne celles à écrire ;
	- `serverChanged` : pendant la superposition, le serveur peut changer
	  l'éclairage (partie qui démarre ou se termine) ; la réplication écrase la
	  valeur locale. La nouvelle valeur du serveur est mémorisée (pour la
	  restauration) et la valeur de l'arène doit être réécrite ;
	- `exit` retourne les dernières valeurs du serveur à rétablir.

	`properties` traduit un bloc `lighting` de config en propriétés de Lighting
	(mêmes noms que Config.Maps : partagé avec le serveur).
]]

export type Settings = {
	ambient: Color3,
	outdoorAmbient: Color3,
	brightness: number,
	clockTime: number,
	fogColor: Color3,
	fogEnd: number,
	exposure: number?,
}

export type Overlay = {
	target: { [string]: any },
	saved: { [string]: any },
	active: boolean,
}

local LightingOverlay = {}

function LightingOverlay.properties(settings: Settings): { [string]: any }
	return {
		Ambient = settings.ambient,
		OutdoorAmbient = settings.outdoorAmbient,
		Brightness = settings.brightness,
		ClockTime = settings.clockTime,
		FogColor = settings.fogColor,
		FogEnd = settings.fogEnd,
		ExposureCompensation = settings.exposure or 0,
	}
end

function LightingOverlay.new(settings: Settings): Overlay
	return { target = LightingOverlay.properties(settings), saved = {}, active = false }
end

-- Début de la superposition : `read(propriété)` lit la valeur actuelle (celle du serveur).
function LightingOverlay.enter(overlay: Overlay, read: (property: string) -> any): { [string]: any }
	if overlay.active then
		return {}
	end
	overlay.active = true
	table.clear(overlay.saved)
	for property in overlay.target do
		overlay.saved[property] = read(property)
	end
	return table.clone(overlay.target)
end

-- Une propriété vient de changer. Retourne true s'il faut réécrire la valeur de
-- l'arène (le serveur l'a écrasée) ; nos propres écritures sont ignorées.
function LightingOverlay.serverChanged(overlay: Overlay, property: string, value: any): boolean
	local target = overlay.target[property]
	if not overlay.active or target == nil or value == target then
		return false
	end
	overlay.saved[property] = value
	return true
end

-- Fin de la superposition : valeurs du serveur à rétablir.
function LightingOverlay.exit(overlay: Overlay): { [string]: any }
	if not overlay.active then
		return {}
	end
	overlay.active = false
	return table.clone(overlay.saved)
end

return LightingOverlay
