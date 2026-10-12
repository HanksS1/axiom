--!strict
--[[
	Signal : événement minimal en pur Luau (sans BindableEvent), utilisable
	côté serveur, client et dans les tests hors Roblox.
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

type Listener = {
	callback: (...any) -> (),
	connection: Connection,
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local listeners: { Listener } = {}

	local object = {} :: any

	local function removeListener(target: Listener)
		local index = table.find(listeners, target)
		if index then
			table.remove(listeners, index)
		end
	end

	function object:Connect(callback: (...any) -> ()): Connection
		local listener: Listener
		local connection = {
			Connected = true,
		} :: any
		function connection.Disconnect(_: Connection)
			if not connection.Connected then
				return
			end
			connection.Connected = false
			removeListener(listener)
		end
		listener = { callback = callback, connection = connection }
		table.insert(listeners, listener)
		return connection
	end

	function object:Once(callback: (...any) -> ()): Connection
		local connection: Connection
		connection = self:Connect(function(...)
			connection:Disconnect()
			callback(...)
		end)
		return connection
	end

	function object:Fire(...: any)
		-- Copie : un écouteur peut se déconnecter pendant la diffusion.
		local snapshot = table.clone(listeners)
		for _, listener in snapshot do
			if listener.connection.Connected then
				task.spawn(listener.callback, ...)
			end
		end
	end

	function object:DisconnectAll()
		for _, listener in table.clone(listeners) do
			listener.connection:Disconnect()
		end
	end

	return object :: Signal<T...>
end

return Signal
