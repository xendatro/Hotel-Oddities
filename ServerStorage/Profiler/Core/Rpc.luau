local HttpService = game:GetService("HttpService")
local Rpc = {}
Rpc.__index = Rpc

function Rpc.new(remote)
	local self = setmetatable({ remote = remote, pending = {}, ready = setmetatable({}, {__mode="k"}) }, Rpc)
	remote.OnServerEvent:Connect(function(player, message)
		if type(message) == "table" and message.kind == "ready" then self.ready[player] = true; return end
		if type(message) ~= "table" or message.kind ~= "reply" then return end
		local entry = self.pending[message.token]
		if not entry or entry.player ~= player then return end
		entry.done = true; entry.ok = message.ok; entry.value = message.value
	end)
	return self
end

-- Never InvokeClient: a missing client must time out, not strand the server run.
function Rpc:Call(ctx, action, payload, timeout)
	local token = HttpService:GenerateGUID(false)
	local entry = { player = ctx.Player, done = false }
	self.pending[token] = entry
	self.remote:FireClient(ctx.Player,{ kind = "rpc", token = token, action = action, payload = payload })
	local deadline = os.clock() + timeout
	while not entry.done and os.clock() < deadline and not ctx.Cancelled and ctx.Player.Parent do task.wait(0.05) end
	self.pending[token] = nil
	assert(entry.done, "Client " .. action .. " timed out or cancelled")
	assert(entry.ok, "Client " .. action .. ": " .. tostring(entry.value))
	return entry.value
end

return Rpc
