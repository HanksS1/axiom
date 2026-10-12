--!strict
--[[
	PanelState : suivi des panneaux ouverts (sac, conteneur, menus).

	Tant qu'un panneau est ouvert : la souris est libérée, les actions de
	combat sont relâchées et le tir est bloqué.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage:WaitForChild("Shared").Util.Signal)

local PanelState = {}

PanelState.Changed = Signal.new() :: Signal.Signal<boolean>

local open: { [string]: boolean } = {}

function PanelState.set(name: string, isOpen: boolean)
	local before = PanelState.anyOpen()
	if isOpen then
		open[name] = true
	else
		open[name] = nil
	end
	local after = PanelState.anyOpen()
	if before ~= after then
		PanelState.Changed:Fire(after)
	end
end

function PanelState.isOpen(name: string): boolean
	return open[name] == true
end

function PanelState.anyOpen(): boolean
	return next(open) ~= nil
end

return PanelState
