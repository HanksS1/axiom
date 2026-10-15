--!strict
--[[
	CapacityGauge : jauge de place (UP) du sac ou du coffre, bien visible.

	- Libellé « SAC  6 / 8 UP » (ou COFFRE), barre colorée selon le remplissage :
	  cyan, orange à partir de Config.Equipment.capacityWarning (« Presque
	  plein »), rouge quand c'est plein (« PLEIN », cadre qui pulse).
	- Message sous la jauge quand c'est plein (ce qu'on peut faire), facultatif.
	La couleur n'est jamais seule : l'état est aussi écrit.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ItemRules = require(ReplicatedStorage:WaitForChild("Shared").Items.ItemRules)

local Create = require(script.Parent.Create)
local Theme = require(script.Parent.Theme)

local CapacityGauge = {}

export type Gauge = {
	frame: Frame,
	set: (used: number, capacity: number) -> (),
}

type Translate = (key: string, params: { [string]: any }?) -> string

local COLORS: { [string]: Color3 } = { ok = Theme.cyan, high = Theme.orange, full = Theme.red }

-- Cadres pleins qui pulsent (un seul battement pour toutes les jauges).
local pulsing: { [UIStroke]: boolean } = {}
RunService.RenderStepped:Connect(function()
	if next(pulsing) == nil then
		return
	end
	local transparency = 0.15 + 0.45 * (0.5 + 0.5 * math.sin(os.clock() * 5))
	for stroke in pulsing do
		if stroke.Parent == nil then
			pulsing[stroke] = nil
		else
			stroke.Transparency = transparency
		end
	end
end)

-- `kind` : "bag" | "vault" (libellé et message) ; `showHint` : message sous la jauge quand c'est plein.
function CapacityGauge.create(t: Translate, kind: "bag" | "vault", showHint: boolean): Gauge
	local label = Create("TextLabel", {
		Position = UDim2.fromOffset(8, 2),
		Size = UDim2.new(1, -16, 0, 20),
		BackgroundTransparency = 1,
		Font = Theme.fontNumbers,
		TextSize = 16,
		TextColor3 = Theme.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		RichText = true,
		Text = "",
	})
	local fill = Create("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0 })
	local bar = Create("Frame", {
		Position = UDim2.fromOffset(8, 24),
		Size = UDim2.new(1, -16, 0, 8),
		BackgroundColor3 = Theme.background,
		BorderSizePixel = 0,
	}, { Fill = fill, Corner = Create("UICorner", { CornerRadius = UDim.new(0, 3) }) })
	local hint = Create("TextLabel", {
		Position = UDim2.fromOffset(8, 36),
		Size = UDim2.new(1, -16, 0, 18),
		BackgroundTransparency = 1,
		Font = Theme.fontText,
		TextSize = 13,
		TextColor3 = Theme.red,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Visible = false,
		Text = "",
	})
	local stroke = Create("UIStroke", { Color = Theme.cyan, Transparency = 0.7 })
	local frame = Create("Frame", {
		Name = "CapacityGauge",
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = Theme.panel,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}, {
		Corner = Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
		Stroke = stroke,
		Label = label,
		Bar = bar,
		Hint = hint,
	})

	local function set(used: number, capacity: number)
		local level = ItemRules.fillLevel(used, capacity)
		local color = COLORS[level]
		fill.Size = UDim2.fromScale(if capacity > 0 then math.clamp(used / capacity, 0, 1) else 1, 1)
		fill.BackgroundColor3 = color
		stroke.Color = color
		local status = if level == "full"
			then `  <font color="#FF3B3B"><b>{t("capacity.full")}</b></font>`
			elseif level == "high" then `  <font color="#FF8A00">{t("capacity.high")}</font>`
			else ""
		label.Text = t("capacity." .. kind, { used = used, capacity = capacity }) .. status
		local full = level == "full"
		hint.Visible = showHint and full
		hint.Text = if full then t("capacity." .. kind .. "FullHint") else ""
		-- La hauteur suit le message ; la largeur reste celle choisie par l'écran.
		frame.Size = UDim2.new(frame.Size.X.Scale, frame.Size.X.Offset, 0, if hint.Visible then 58 else 38)
		if full then
			pulsing[stroke] = true
		else
			pulsing[stroke] = nil
			stroke.Transparency = if level == "high" then 0.3 else 0.7
		end
	end

	return { frame = frame, set = set }
end

return CapacityGauge
