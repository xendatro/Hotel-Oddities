local RunService = game:GetService("RunService")

local RigMotion = {}
RigMotion.__index = RigMotion

function RigMotion.extend()
	local class = setmetatable({}, { __index = RigMotion })
	class.__index = class
	return class
end

function RigMotion.FindJoint(rig: Model, partNames: { string }, jointName: string): any?
	for _, partName in partNames do
		local part = rig:FindFirstChild(partName)
		local joint = part and part:FindFirstChild(jointName)
		if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
			return joint
		end
	end
	return nil
end

local function setUpConnections(self)
	self.Connections = {}

	self.Connections.PreAnimation = RunService.PreAnimation:Connect(function()
		self:RemoveApplied()
	end)
	self.Connections.PreSimulation = RunService.PreSimulation:Connect(function(deltaTime: number)
		self:Update(deltaTime)
	end)
end

function RigMotion.new(rig: Model, class: any?)
	local self = setmetatable({}, class or RigMotion)

	self.Rig = rig

	setUpConnections(self)

	return self
end

function RigMotion:RemoveApplied() end

function RigMotion:Update(deltaTime: number) end

function RigMotion:Destroy()
	self:RemoveApplied()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Connections = {}
end

return RigMotion
