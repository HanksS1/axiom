--!strict
--[[
	ClientNet : accès client aux remotes déclarées dans Shared/Net/Remotes.
	Le client n'envoie que des INTENTIONS ; le serveur décide de tout.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Net.Remotes)

local ClientNet = {}

local folder = ReplicatedStorage:WaitForChild("Remotes")

local function getInstance(name: string): Instance
	assert(Remotes[name] ~= nil, `remote inconnue : {name}`)
	return folder:WaitForChild(name)
end

function ClientNet.fire(name: string, ...: any)
	assert(Remotes[name].toServer, `{name} n'accepte pas d'appel client`)
	local remote = getInstance(name) :: RemoteEvent
	remote:FireServer(...)
end

function ClientNet.invoke(name: string, ...: any): ...any
	assert(Remotes[name].kind == "function", `{name} n'est pas une RemoteFunction`)
	return (getInstance(name) :: RemoteFunction):InvokeServer(...)
end

function ClientNet.on(name: string, callback: (...any) -> ()): RBXScriptConnection
	assert(
		Remotes[name].kind ~= "function" and not Remotes[name].toServer,
		`{name} n'est pas un événement serveur → client`
	)
	return (getInstance(name) :: any).OnClientEvent:Connect(callback)
end

return ClientNet
