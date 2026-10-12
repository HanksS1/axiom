--!strict
--[[
	DragDrop : glisser-déposer à la souris (PC, section 17.3, écran 4).
	Sur mobile et à la manette, les boutons des cartes restent la voie normale.

	- `DragDrop.attach(card, payload)` rend une carte déplaçable ;
	- `DragDrop.target(frame, name)` déclare une zone de dépôt ;
	- `DragDrop.Dropped` : (payload, nom de la zone) au relâchement.
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Signal = require(ReplicatedStorage:WaitForChild("Shared").Util.Signal)

local DragDrop = {}

DragDrop.Dropped = Signal.new() :: Signal.Signal<any, string>

local THRESHOLD = 8 -- px avant que le glissement commence

local targets: { [GuiObject]: string } = {}
local pressed: { card: GuiObject, payload: any, start: Vector2 }? = nil
local ghost: GuiObject? = nil

function DragDrop.target(frame: GuiObject, name: string)
	targets[frame] = name
	frame.Destroying:Connect(function()
		targets[frame] = nil
	end)
end

local function inside(frame: GuiObject, point: Vector2): boolean
	local position, size = frame.AbsolutePosition, frame.AbsoluteSize
	return point.X >= position.X
		and point.X <= position.X + size.X
		and point.Y >= position.Y
		and point.Y <= position.Y + size.Y
end

local function clear()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	pressed = nil
end

function DragDrop.attach(card: GuiObject, payload: any)
	card.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			pressed = { card = card, payload = payload, start = Vector2.new(input.Position.X, input.Position.Y) }
		end
	end)
end

UserInputService.InputChanged:Connect(function(input: InputObject)
	local current = pressed
	if current == nil or input.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	end
	local point = Vector2.new(input.Position.X, input.Position.Y)
	if ghost == nil then
		if (point - current.start).Magnitude < THRESHOLD then
			return
		end
		local screen = current.card:FindFirstAncestorWhichIsA("ScreenGui")
		if screen == nil then
			return
		end
		local copy = current.card:Clone()
		copy.AnchorPoint = Vector2.new(0.5, 0.5)
		copy.Size = UDim2.fromOffset(current.card.AbsoluteSize.X, current.card.AbsoluteSize.Y)
		copy.ZIndex = 50
		if copy:IsA("Frame") then
			copy.BackgroundTransparency = 0.4
		end
		copy.Parent = screen
		ghost = copy
	end
	local inset = if (current.card:FindFirstAncestorWhichIsA("ScreenGui") :: ScreenGui).IgnoreGuiInset
		then GuiService:GetGuiInset().Y
		else 0
	(ghost :: GuiObject).Position = UDim2.fromOffset(point.X, point.Y + inset)
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	local current = pressed
	if current == nil or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	local dragged = ghost ~= nil
	clear()
	if not dragged then
		return
	end
	local point = Vector2.new(input.Position.X, input.Position.Y)
	for frame, name in targets do
		if frame.Visible and inside(frame, point) then
			DragDrop.Dropped:Fire(current.payload, name)
			return
		end
	end
end)

return DragDrop
