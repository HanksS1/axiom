--!strict
--[[
	Sparks : gerbe d'étincelles (Armurier : soudure pendant la réparation).
]]

local TweenService = game:GetService("TweenService")

local Create = require(script.Parent.Create)

local Sparks = {}

local random = Random.new()
local COLORS = { Color3.fromRGB(255, 176, 32), Color3.fromRGB(255, 138, 0), Color3.fromRGB(255, 240, 200) }

-- Gerbe d'étincelles au centre de `parent`.
function Sparks.burst(parent: GuiObject, count: number?)
	for _ = 1, count or 18 do
		local spark = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(random:NextInteger(2, 5), random:NextInteger(2, 5)),
			BackgroundColor3 = COLORS[random:NextInteger(1, #COLORS)],
			BorderSizePixel = 0,
			ZIndex = 40,
			Parent = parent,
		})
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(40, 140)
		local duration = random:NextNumber(0.35, 0.7)
		local tween =
			TweenService:Create(spark, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.5, math.cos(angle) * distance, 0.5, math.sin(angle) * distance + distance * 0.3),
				BackgroundTransparency = 1,
			})
		tween.Completed:Once(function()
			spark:Destroy()
		end)
		tween:Play()
	end
end

return Sparks
