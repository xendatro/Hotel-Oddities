local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Race = require(ReplicatedStorage.Classes.Race)

local Deadline = {}
Deadline.__index = Deadline

--[[
example:
Tween:Wait()
vs
task.wait(2)
]]

function Deadline.new(f, n)
	local self = setmetatable({}, Deadline)
	
	self.Function = f
	self.Time = n
	self.Race = Race.new({
		main = f,
		alt = function() task.wait(n) end
	})
	self.State = "Ready"
	
	return self
end

function Deadline:Fire()
	if self.State ~= "Ready" then return end
	self.State = "Active"
	local val = self.Race:Fire() == "main"
	self.State = "Dead"
	return val
end

return Deadline