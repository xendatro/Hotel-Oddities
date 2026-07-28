local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Race = {}
Race.__index = Race

--[[
functions dict:
{
	id = function() end,
	id2 = function() end
}
]]

function Race.new(functions)
	local self = setmetatable({}, Race)
	
	self.Functions = functions
	self.MainThread = nil
	self.Threads = {}
	self.State = "Ready"
	
	return self
end

function Race:Fire()
	if self.State ~= "Ready" then return end
	if not self.Functions or not next(self.Functions) then
		error("Race:Fire requires a non-empty functions table", 2)
	end
	self.State = "Active"
	self.MainThread = coroutine.running()
	local finishedId = nil
	local threads = self.Threads
	for id, f in self.Functions do
		local thread: thread = nil	
		thread = task.defer(function()
			local success, err = pcall(f)
			table.remove(threads, table.find(threads, thread))
			if not success then
				error(err, 0)
			end
			finishedId = id
			coroutine.resume(self.MainThread)
		end)
		table.insert(threads, thread)
	end
	coroutine.yield(self.MainThread)
	self.State = "Dead"
	for _, thread in threads do
		task.cancel(thread)
	end
	return finishedId
end

function Race:Cancel()
	if self.State ~= "Active" then return end
	if table.find(self.Threads, coroutine.running()) then
		error("Race:Cancel cannot be called from within the Race's own functions", 2)
	end
	coroutine.resume(self.MainThread)
end

return Race
