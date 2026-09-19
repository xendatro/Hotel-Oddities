local HttpService = game:GetService("HttpService")
local Settings = require(script.Parent.Parent.Config.Settings)
local Transport = {}
Transport.__index = Transport

function Transport.new(remote, policy)
	local self = setmetatable({ remote = remote, pending = {}, queue = {}, nextSend = 0, policy = policy or Settings },Transport)
	self.connection = remote.OnClientEvent:Connect(function(message)
		if type(message) ~= "table" or message.kind ~= "commandReply" or type(message.token) ~= "string" then return end
		local entry = self.pending[message.token]
		if entry then entry.done = true; entry.message = message end
	end)
	return self
end

function Transport:Request(command, deadline)
	local token = HttpService:GenerateGUID(false)
	local entry = { done = false }
	self.pending[token] = entry
	local ok,err = pcall(function()
		self.nextSend = os.clock()+self.policy.CommandInterval
		self.remote:FireServer({ kind = "command", token = token, command = command })
		while not entry.done and os.clock()<deadline do task.wait(0.01) end
		assert(entry.done,"Profiler server did not reply to " .. tostring(command.action) .. "; reopen the panel to retry")
	end)
	self.pending[token] = nil
	if not ok then error(err,0) end
	return entry.message
end

function Transport:Command(command)
	assert(type(command) == "table","Command must be a table")
	assert(#self.queue < self.policy.CommandQueueLimit,"Profiler command queue is full; wait for pending requests")
	local ticket = {}
	table.insert(self.queue,ticket)
	local deadline = os.clock()+self.policy.CommandTimeout
	local ok,value = pcall(function()
		while self.queue[1] ~= ticket and os.clock()<deadline do task.wait(0.01) end
		while os.clock()<deadline do
			while os.clock()<self.nextSend and os.clock()<deadline do task.wait(0.01) end
			if os.clock()>=deadline then break end
			local reply = self:Request(command,deadline)
			if reply.ok then return reply.value end
			-- Retry only explicit pre-execution rejections. A lost reply may hide a
			-- completed start/import, so timeouts must never replay those commands.
			if reply.retryable ~= true or (reply.code ~= "busy" and reply.code ~= "throttled") then error(tostring(reply.value),0) end
			self.nextSend = math.max(self.nextSend,os.clock()+self.policy.CommandInterval)
		end
		error("Profiler command timed out waiting for the server: " .. tostring(command.action),0)
	end)
	local index = table.find(self.queue,ticket)
	if index then table.remove(self.queue,index) end
	if not ok then error(value,0) end
	return value
end

function Transport:Export(id,format)
	local chunks, offset = {},1
	repeat
		local result = self:Command({ action = "result", id = id, format = format, offset = offset })
		table.insert(chunks,result.text); offset = result.nextOffset
	until not offset
	return table.concat(chunks)
end

return Transport
