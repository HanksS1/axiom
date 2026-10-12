--!strict
--[[
	Flicker : néons défaillants (section 17.1). Certains éléments DÉCORATIFS
	(titres, enseignes) grésillent ou s'éteignent à moitié de temps en temps,
	pour évoquer la rareté de l'énergie. Jamais sur une information
	importante (PV, chrono, prix, boutons).

	Un seul planificateur pour tous les éléments enregistrés.
]]

local RunService = game:GetService("RunService")

local Flicker = {}

type Entry = { label: TextLabel, nextAt: number, untilAt: number, base: number }

local entries: { [TextLabel]: Entry } = {}
local random = Random.new()
local connection: RBXScriptConnection? = nil

local MIN_DELAY, MAX_DELAY = 5, 14
local DURATION = 0.35

local function step()
	local now = os.clock()
	for label, entry in entries do
		if label.Parent == nil then
			entries[label] = nil
			continue
		end
		if now >= entry.nextAt then
			entry.untilAt = now + DURATION
			entry.nextAt = now + random:NextNumber(MIN_DELAY, MAX_DELAY)
		end
		if now < entry.untilAt and label.Visible then
			-- Grésillement : extinctions brèves et irrégulières.
			label.TextTransparency = if random:NextNumber() < 0.5 then 0.65 else entry.base
		elseif label.TextTransparency ~= entry.base then
			label.TextTransparency = entry.base
		end
	end
	if next(entries) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

-- Fait grésiller un texte décoratif.
function Flicker.attach(label: TextLabel)
	entries[label] = {
		label = label,
		nextAt = os.clock() + random:NextNumber(MIN_DELAY, MAX_DELAY),
		untilAt = 0,
		base = label.TextTransparency,
	}
	if connection == nil then
		connection = RunService.Heartbeat:Connect(step)
	end
end

return Flicker
