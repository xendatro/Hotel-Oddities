local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BreatheConfig = require(ReplicatedStorage.Configs.BreatheConfig)

local Breathe = {}
Breathe.__index = Breathe

local JOINTS = {
	{ Name = "Root", Part = "LowerTorso" },
	{ Name = "Waist", Part = "UpperTorso" },
	{ Name = "Neck", Part = "Head" },
	{ Name = "LeftShoulder", Part = "LeftUpperArm" },
	{ Name = "RightShoulder", Part = "RightUpperArm" },
}

local function findJoint(rig: Model, partName: string, jointName: string): any?
	local part = rig:FindFirstChild(partName)
	local joint = part and part:FindFirstChild(jointName)
	if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
		return joint
	end
	return nil
end

local function curve(phase: number): number
	local inhale = BreatheConfig.InhaleFraction
	local progress = if phase < inhale
		then phase / inhale
		else 1 - (phase - inhale) / (1 - inhale)
	return -math.cos(progress * math.pi)
end

local function listenerPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character.PrimaryPart
	return if root then root.Position else nil
end

function Breathe.new(rig: Model)
	local self = setmetatable({}, Breathe)

	self.Rig = rig
	self.RootPart = nil :: BasePart?
	self.Joints = {} :: { [string]: any }
	self.Applied = {} :: { [any]: CFrame }
	self.Phase = math.random()
	self.Amount = 0

	self.PreAnimationConnection = RunService.PreAnimation:Connect(function()
		self:_removeApplied()
	end)
	self.PreSimulationConnection = RunService.PreSimulation:Connect(function(deltaTime: number)
		self:_update(deltaTime)
	end)

	return self
end

function Breathe:_resolveParts(): boolean
	self.RootPart = self.RootPart or self.Rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not self.RootPart then return false end

	for _, entry in JOINTS do
		self.Joints[entry.Name] = self.Joints[entry.Name] or findJoint(self.Rig, entry.Part, entry.Name)
	end
	return true
end

function Breathe:_removeApplied()
	for joint, offset in self.Applied do
		joint.Transform = offset:Inverse() * joint.Transform
	end
	table.clear(self.Applied)
end

function Breathe:_apply(name: string, offset: CFrame)
	local joint = self.Joints[name]
	if not joint then return end

	self.Applied[joint] = offset
	joint.Transform = offset * joint.Transform
end

function Breathe:_update(deltaTime: number)
	if not self.Rig:IsDescendantOf(workspace) then return end
	if not self:_resolveParts() then return end

	self.Phase = (self.Phase + deltaTime / BreatheConfig.Period) % 1

	local rootPart = self.RootPart :: BasePart
	local listener = listenerPosition()
	local inRange = listener ~= nil
		and (listener - rootPart.Position).Magnitude <= BreatheConfig.MaxDistance

	local target = if inRange then curve(self.Phase) else 0
	self.Amount += (target - self.Amount) * (1 - math.exp(-BreatheConfig.Smoothing * deltaTime))
	if not inRange and math.abs(self.Amount) < 1e-4 then
		self.Amount = 0
		return
	end

	local amount = self.Amount
	self:_apply("Root", CFrame.new(0, BreatheConfig.Root.Rise * amount, 0))
	self:_apply("Waist", CFrame.Angles(BreatheConfig.Waist.Pitch * amount, 0, 0))
	self:_apply("Neck", CFrame.Angles(-BreatheConfig.Neck.Pitch * amount, 0, 0))
	self:_apply("LeftShoulder", CFrame.Angles(0, 0, -BreatheConfig.Shoulder.Roll * amount))
	self:_apply("RightShoulder", CFrame.Angles(0, 0, BreatheConfig.Shoulder.Roll * amount))
end

function Breathe:Destroy()
	self:_removeApplied()
	self.PreAnimationConnection:Disconnect()
	self.PreSimulationConnection:Disconnect()
end

return Breathe
