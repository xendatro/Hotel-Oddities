local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BreatheConfig = require(ReplicatedStorage.Configs.BreatheConfig)
local MathService = require(ReplicatedStorage.Services.MathService)
local RigMotion = require(ReplicatedStorage.Classes.RigMotion)

local RESOLVE_RETRY_INTERVAL = 0.25

local Breathe = RigMotion.extend()

local JOINTS = {
	{ Name = "Root", Part = "LowerTorso" },
	{ Name = "Waist", Part = "UpperTorso" },
	{ Name = "Neck", Part = "Head" },
	{ Name = "LeftShoulder", Part = "LeftUpperArm" },
	{ Name = "RightShoulder", Part = "RightUpperArm" },
}

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
	local self = RigMotion.new(rig, Breathe)

	self.RootPart = nil :: BasePart?
	self.Joints = {} :: { [string]: any }
	self.Applied = {} :: { [any]: CFrame }
	self.Phase = math.random()
	self.Amount = 0
	self.ResolveDone = false
	self.NextResolveAt = 0

	return self
end

function Breathe:_resolveParts(): boolean
	if self.ResolveDone then return true end

	local now = os.clock()
	if now < self.NextResolveAt then
		return self.RootPart ~= nil
	end
	self.NextResolveAt = now + RESOLVE_RETRY_INTERVAL

	self.RootPart = self.RootPart or self.Rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not self.RootPart then return false end

	local complete = true
	for _, entry in JOINTS do
		self.Joints[entry.Name] = self.Joints[entry.Name] or RigMotion.FindJoint(self.Rig, { entry.Part }, entry.Name)
		if not self.Joints[entry.Name] then
			complete = false
		end
	end
	self.ResolveDone = complete
	return true
end

function Breathe:RemoveApplied()
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

function Breathe:Update(deltaTime: number)
	if not self.Rig:IsDescendantOf(workspace) then return end
	if not self:_resolveParts() then return end

	self.Phase = (self.Phase + deltaTime / BreatheConfig.Period) % 1

	local rootPart = self.RootPart :: BasePart
	local listener = listenerPosition()
	local inRange = listener ~= nil
		and (listener - rootPart.Position).Magnitude <= BreatheConfig.MaxDistance

	local target = if inRange then curve(self.Phase) else 0
	self.Amount += (target - self.Amount) * MathService.ExpAlpha(BreatheConfig.Smoothing, deltaTime)
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

return Breathe
