local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local WatchConfig = require(game:GetService("ReplicatedStorage").Configs.WatchConfig)

local MINIMUM_DIRECTION = 1e-3

local Watch = {}
Watch.__index = Watch

local function directionAngles(basis: CFrame, direction: Vector3): (number, number)
	local localDirection = basis:VectorToObjectSpace(direction)
	local horizontal = math.sqrt(localDirection.X ^ 2 + localDirection.Z ^ 2)
	return math.atan2(localDirection.Y, horizontal), math.atan2(-localDirection.X, -localDirection.Z)
end

local function findJoint(rig: Model, partNames: { string }, jointName: string): any?
	for _, partName in partNames do
		local part = rig:FindFirstChild(partName)
		local joint = part and part:FindFirstChild(jointName)
		if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
			return joint
		end
	end
	return nil
end

local function targetPosition(player: Player): Vector3?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head")
	if not (humanoid and humanoid.Health > 0 and head and head:IsA("BasePart")) then
		return nil
	end
	return head.Position
end

function Watch.new(rig: Model)
	local self = setmetatable({}, Watch)

	self.Rig = rig
	self.Head = nil :: BasePart?
	self.RootPart = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	self.Neck = nil
	self.Waist = nil
	self.Pitch = 0
	self.Yaw = 0
	self.AppliedNeck = CFrame.identity
	self.AppliedWaist = CFrame.identity

	self.PreAnimationConnection = RunService.PreAnimation:Connect(function()
		self:_removeApplied()
	end)
	self.PreSimulationConnection = RunService.PreSimulation:Connect(function(deltaTime: number)
		self:_update(deltaTime)
	end)

	return self
end

function Watch:_resolveParts(): boolean
	if not self.Head then
		local head = self.Rig:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			self.Head = head
		end
	end
	if not self.Head then return false end

	self.RootPart = self.RootPart or self.Rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	self.Neck = self.Neck or findJoint(self.Rig, { "Head", "Torso" }, "Neck")
	self.Waist = self.Waist or findJoint(self.Rig, { "UpperTorso" }, "Waist")
	return true
end

function Watch:_removeApplied()
	if self.Neck then
		self.Neck.Transform = self.AppliedNeck:Inverse() * self.Neck.Transform
	end
	if self.Waist then
		self.Waist.Transform = self.AppliedWaist:Inverse() * self.Waist.Transform
	end
	self.AppliedNeck = CFrame.identity
	self.AppliedWaist = CFrame.identity
end

function Watch:_targetCorrection(position: Vector3): (number, number)
	local head = self.Head :: BasePart
	local origin = head.Position
	local direction = position - origin
	if direction.Magnitude <= MINIMUM_DIRECTION then
		return 0, 0
	end

	local basis = self.RootPart or self.Head
	local targetPitch, targetYaw = directionAngles(basis.CFrame, direction)
	local currentPitch, currentYaw = directionAngles(basis.CFrame, head.CFrame.LookVector)

	targetPitch = math.clamp(targetPitch, -WatchConfig.MaxPitchDown, WatchConfig.MaxPitchUp)
	targetYaw = math.clamp(
		targetYaw,
		-WatchConfig.MaxYaw,
		WatchConfig.MaxYaw
	)

	return targetPitch - currentPitch, targetYaw - currentYaw
end

function Watch:_update(deltaTime: number)
	if not self.Rig:IsDescendantOf(workspace) then return end
	if not self:_resolveParts() then return end

	local playerPosition = targetPosition(Players.LocalPlayer)
	local targetPitch, targetYaw = 0, 0
	local head = self.Head :: BasePart
	if playerPosition and (playerPosition - head.Position).Magnitude <= WatchConfig.TrackRange then
		targetPitch, targetYaw = self:_targetCorrection(playerPosition)
	end

	local alpha = 1 - math.exp(-WatchConfig.Smoothing * deltaTime)
	self.Pitch += (targetPitch - self.Pitch) * alpha
	self.Yaw += (targetYaw - self.Yaw) * alpha

	local neck = self.Neck
	if neck then
		local pitchWeight = if self.Waist then WatchConfig.Neck.Pitch else 1
		local yawWeight = if self.Waist then WatchConfig.Neck.Yaw else 1
		self.AppliedNeck = CFrame.Angles(
			self.Pitch * pitchWeight,
			self.Yaw * yawWeight,
			0
		)
		neck.Transform = self.AppliedNeck * neck.Transform
	end

	local waist = self.Waist
	if waist then
		local pitchWeight = if self.Neck then WatchConfig.Waist.Pitch else 1
		local yawWeight = if self.Neck then WatchConfig.Waist.Yaw else 1
		self.AppliedWaist = CFrame.Angles(
			self.Pitch * pitchWeight,
			self.Yaw * yawWeight,
			0
		)
		waist.Transform = self.AppliedWaist * waist.Transform
	end
end

function Watch:Destroy()
	self:_removeApplied()
	self.PreAnimationConnection:Disconnect()
	self.PreSimulationConnection:Disconnect()
end

return Watch
