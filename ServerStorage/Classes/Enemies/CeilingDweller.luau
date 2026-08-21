local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Chaser = require(ServerStorage.Classes.Enemies.Chaser)
local NPC = require(ServerStorage.Classes.NPC)

local DROP_SPEED = 22
local DROP_TIME_MIN = 0.2
local DROP_TIME_MAX = 1.25

local function getCameraEvent(): RemoteEvent
	local communication = ReplicatedStorage:FindFirstChild("Communication")
	if not communication then
		communication = Instance.new("Folder")
		communication.Name = "Communication"
		communication.Parent = ReplicatedStorage
	end
	local enemies = communication:FindFirstChild("Enemies")
	if not enemies then
		enemies = Instance.new("Folder")
		enemies.Name = "Enemies"
		enemies.Parent = communication
	end
	local event = enemies:FindFirstChild("CeilingDwellerCamera")
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = "CeilingDwellerCamera"
		event.Parent = enemies
	end
	return event :: RemoteEvent
end

local CameraEvent = getCameraEvent()

local CeilingDweller = NPC.extend("Ceiling Dweller")

function CeilingDweller.new(
	model: Model,
	config,
	initialTarget: Player?,
	dropFloorPosition: Vector3?,
	dropFloorNormal: Vector3?
)
	local self = NPC.new(model, config, CeilingDweller)
	self.InitialTarget = initialTarget
	self.DropFloorPosition = dropFloorPosition
	self.DropFloorNormal = dropFloorNormal
	return self
end

function CeilingDweller:BuildStateMachine()
	return Chaser.BuildStateMachine(self)
end

local function dropToFloor(self)
	local floorPosition = self.DropFloorPosition
	local floorNormal = self.DropFloorNormal or Vector3.yAxis
	self.DropFloorPosition = nil
	self.DropFloorNormal = nil
	if not floorPosition then return true end

	local collisionStates: { [BasePart]: boolean } = {}
	for _, descendant in self.Model:GetDescendants() do
		if descendant:IsA("BasePart") then
			collisionStates[descendant] = descendant.CanCollide
			descendant.CanCollide = false
		end
	end

	local root = self.RootPart
	local humanoid = self.Humanoid
	local pivotToRoot = self.Model:GetPivot():ToObjectSpace(root.CFrame)
	local standingHeight = humanoid.HipHeight + root.Size.Y / 2
	local desiredRootPosition = floorPosition + floorNormal.Unit * standingHeight
	local desiredRootCFrame = CFrame.new(desiredRootPosition) * root.CFrame.Rotation
	local target = desiredRootCFrame * pivotToRoot:Inverse()

	local autoRotate = humanoid.AutoRotate
	local platformStand = humanoid.PlatformStand
	local fallingDownEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.FallingDown)
	local ragdollEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Ragdoll)

	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	root.Anchored = true
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	local start = self.Model:GetPivot()
	local duration = math.clamp((start.Position - target.Position).Magnitude / DROP_SPEED, DROP_TIME_MIN, DROP_TIME_MAX)
	local dropTarget = self.DropTarget
	if dropTarget and dropTarget.Parent == Players then
		CameraEvent:FireClient(dropTarget, "Drop", duration)
	end
	local value = Instance.new("CFrameValue")
	value.Value = start
	local changed = value:GetPropertyChangedSignal("Value"):Connect(function()
		if self.Model.Parent then
			self.Model:PivotTo(value.Value)
		end
	end)
	local tween = TweenService:Create(
		value,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Value = target }
	)
	tween:Play()
	tween.Completed:Wait()
	changed:Disconnect()
	value:Destroy()

	if not self.Model.Parent then return false end
	self.Model:PivotTo(target)
	for part, canCollide in collisionStates do
		if part.Parent then
			part.CanCollide = canCollide
		end
	end

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = false
	humanoid.PlatformStand = platformStand
	humanoid.AutoRotate = autoRotate
	humanoid:ChangeState(Enum.HumanoidStateType.Running)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, fallingDownEnabled)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, ragdollEnabled)
	return true
end

local function getNearestPlayer(self): Player?
	local nearest, nearestDistance = nil, math.huge
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local distance = (root.Position - self.RootPart.Position).Magnitude
			if distance < nearestDistance then
				nearest, nearestDistance = player, distance
			end
		end
	end
	return nearest
end

function CeilingDweller:Start()
	local target = self.InitialTarget or getNearestPlayer(self)
	self.InitialTarget = nil
	self.DropTarget = target

	self.Animator:Start()
	self.Animator:SetMovementTrack("Run")
	self.Animator:SetMovementSpeed(self.Config.ChaseSpeed)

	if target then
		self.Target = target
		self.StateMachine.State = "Chase"
		self.StateMachine.Parameters = table.pack("Chase", self, target)
	end

	if not dropToFloor(self) then return end
	if target and target.Parent == Players then
		CameraEvent:FireClient(target, "Scream")
	end
	self.DropTarget = nil

	self.Animator.MovementSpeedOverride = nil
	self.Animator:SetMovementTrack(nil)

	local character = target and target.Character
	local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
	if targetRoot then
		self.Humanoid:MoveTo(targetRoot.Position)
	end
	NPC.Start(self)
end

return CeilingDweller
