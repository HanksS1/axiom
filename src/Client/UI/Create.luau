--!strict
--[[
	Create : construction déclarative d'instances d'interface.

		Create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, {
			Title = Create("TextLabel", { Text = "…" }),
		})

	Les enfants nommés par une clé chaîne reçoivent ce nom. Les propriétés
	sont appliquées avant le parentage (performances).
]]

local function Create(className: string, properties: { [string]: any }?, children: { [any]: Instance }?): any
	local instance = Instance.new(className)
	if properties then
		for key, value in properties do
			if key ~= "Parent" then
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for key, child in children do
			if type(key) == "string" then
				child.Name = key
			end
			child.Parent = instance
		end
	end
	if properties and properties.Parent then
		instance.Parent = properties.Parent
	end
	return instance
end

return Create
