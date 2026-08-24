local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WatchConfig = require(ReplicatedStorage.Configs.WatchConfig)
local MathService = require(ReplicatedStorage.Services.MathService)
local RigMotion = require(ReplicatedStorage.Classes.RigMotion)

local MINIMUM_DIRECTION = 1e-3
local RESOLVE_RETRY_INTERVAL = 0.25

local Watch = RigMotion.extend()

local function directionAngles(basis: CFrame, direction: Vector3): (number, number)
	local localDirection = basis:VectorToObjectSpace(direction)
	local horizontal = math.sqrt(localDirection.X ^ 2 + localDirection.Z ^ 2)
	return math.atan2(localDirection.Y, horizontal), math.atan2(-localDirection.X, -localDirection.Z)
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
	local self = RigMotion.new(rig, Watch)

	self.Head = nil :: BasePart?
	self.RootPart = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	self.Neck = nil
	self.Waist = nil
	self.Pitch = 0
	self.Yaw = 0
	self.AppliedNeck = CFrame.identity
	self.AppliedWaist = CFrame.identity
	self.ResolveDone = false
	self.NextResolveAt = 0

	return self
end

function Watch:_resolveParts(): boolean
	if self.ResolveDone then return true end

	local now = os.clock()
	if now < self.NextResolveAt then
		return self.Head ~= nil
	end
	self.NextResolveAt = now + RESOLVE_RETRY_INTERVAL

	if not self.Head then
		local head = self.Rig:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			self.Head = head
		end
	end
	if not self.Head then return false end

	self.RootPart = self.RootPart or self.Rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	self.Neck = self.Neck or RigMotion.FindJoint(self.Rig, { "Head", "Torso" }, "Neck")
	self.Waist = self.Waist or RigMotion.FindJoint(self.Rig, { "UpperTorso" }, "Waist")
	self.ResolveDone = self.RootPart ~= nil and self.Neck ~= nil and self.Waist ~= nil
	return true
end

function Watch:RemoveApplied()
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

function Watch:Update(deltaTime: number)
	if not self.Rig:IsDescendantOf(workspace) then return end
	if not self:_resolveParts() then return end

	local playerPosition = targetPosition(Players.LocalPlayer)
	local targetPitch, targetYaw = 0, 0
	local head = self.Head :: BasePart
	if playerPosition and (playerPosition - head.Position).Magnitude <= WatchConfig.TrackRange then
		targetPitch, targetYaw = self:_targetCorrection(playerPosition)
	end

	local alpha = MathService.ExpAlpha(WatchConfig.Smoothing, deltaTime)
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

return Watch
