local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AudioService = require(ReplicatedStorage.Services.AudioService)

local Create = ReplicatedStorage.Communication.Hole.Create
local Delete = ReplicatedStorage.Communication.Backpack.Delete

local Other = ReplicatedStorage.Props.Other

local DIG_DEPTH = 100 -- how far down to look for ground before giving up
local HOLE_START_SCALE = 0.1
local HOLE_END_SCALE = 0.792
local HOLE_GROW_TIME = 2

--- @class Shovel
--- Digs an escape hole. The player is rooted for the length of the dig animation while a widening
--- placeholder opens under them; when it finishes the server is asked to cut the real hole pair.
--- Digging in midair is refused outright, so the dig cannot be started off a ledge.
local Shovel = {}
Shovel.__index = Shovel

local function setUpConnections(self)
	self.Connections = {}

	self.Connections.Equipped = self.Shovel.Equipped:Connect(function()
		self.Character = self.Shovel.Parent
		self.Humanoid = self.Character:FindFirstChildOfClass("Humanoid")

		self.EquipTrack = self.Humanoid.Animator:LoadAnimation(self.Shovel.Animations.Equip)
		self.EquipTrack.Priority = Enum.AnimationPriority.Action
		self.EquipTrack:Play(0.25)
	end)

	self.Connections.Unequipped = self.Shovel.Unequipped:Connect(function()
		if self.EquipTrack then
			self.EquipTrack:Stop()
		end
	end)

	self.Connections.Activated = self.Shovel.Activated:Connect(function()
		self:Activated()
	end)
end

function Shovel.new(shovel: Tool)
	local self = setmetatable({}, Shovel)

	self.Shovel = shovel
	self.Playing = false

	setUpConnections(self)

	return self
end

-- Grows the placeholder hole in place. Model:ScaleTo is a method rather than a property, so the
-- tween drives a NumberValue and the scale follows it.
local function growHole(hole: Model)
	local scale = Instance.new("NumberValue")
	scale.Value = HOLE_START_SCALE

	local connection = scale:GetPropertyChangedSignal("Value"):Connect(function()
		hole:ScaleTo(scale.Value)
	end)

	local tween = TweenService:Create(scale, TweenInfo.new(HOLE_GROW_TIME, Enum.EasingStyle.Linear), {
		Value = HOLE_END_SCALE,
	})
	tween.Completed:Once(function()
		connection:Disconnect()
		scale:Destroy()
	end)
	tween:Play()
end

function Shovel:Activated()
	if self.Playing or not self.Character or not self.Humanoid then return end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self.Character }

	local ground = workspace:Raycast(self.Character:GetPivot().Position, Vector3.new(0, -DIG_DEPTH, 0), params)
	if not ground then return end -- midair: nothing to dig into

	local entry = ground.Position + Vector3.new(0, 0.5, 0)

	self.Playing = true
	AudioService:Play3DSound("Shovel", self.Character.PrimaryPart, false, "SFX")

	local dummy = Other.DummyHole:Clone()
	local x, y, z = dummy:GetPivot():ToOrientation()
	dummy:PivotTo(CFrame.new(entry) * CFrame.fromOrientation(x, y, z))
	dummy:ScaleTo(HOLE_START_SCALE)
	dummy.Parent = workspace

	local speed = self.Humanoid.WalkSpeed
	self.Humanoid.WalkSpeed = 0

	local track = self.Humanoid.Animator:LoadAnimation(self.Shovel.Animations.Dig)
	track.Priority = Enum.AnimationPriority.Action2
	track:Play()

	growHole(dummy)
	track.Ended:Wait()

	if self.Humanoid then
		self.Humanoid.WalkSpeed = speed
	end

	-- Digging the last shovel out of the stack ends the equip pose with it.
	if self.Shovel:GetAttribute("quantity") <= 1 and self.EquipTrack then
		self.EquipTrack:Stop()
	end

	Delete:FireServer(self.Shovel.Name, 1)
	Create:InvokeServer(entry)

	dummy:Destroy()
	self.Playing = false
end

function Shovel:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
end

return Shovel
