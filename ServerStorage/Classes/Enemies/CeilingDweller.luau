--- @class CeilingDweller
--- A Chaser delivered by a ceiling vent. It uses the Chaser state machine unchanged, but a vent can
--- hand it the player who opened the ambush so its initial state is Chase rather than Idle.

local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local Chaser = require(ServerStorage.Classes.Enemies.Chaser)
local NPC = require(ServerStorage.Classes.NPC)

local DROP_SPEED = 22
local DROP_TIME_MIN = 0.2
local DROP_TIME_MAX = 1.25

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

function CeilingDweller:Start()
	local target = self.InitialTarget
	self.InitialTarget = nil

	if target then
		-- NPC:Start starts the state machine on a spawned task. Seed Chase before that task exists so
		-- the first state it ever runs is pursuit; interrupting Idle afterward can lose the race.
		self.Target = target
		self.StateMachine.State = "Chase"
		self.StateMachine.Parameters = table.pack("Chase", self, target)
	end

	if not dropToFloor(self) then return end
	NPC.Start(self)
end

return CeilingDweller
