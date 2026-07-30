local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AudioService = require(ReplicatedStorage.Services.AudioService)
local TagService = require(ReplicatedStorage.Services.TagService)

local Delete = ReplicatedStorage.Communication.Backpack.Delete
local Hit = ReplicatedStorage.Communication.Ball.Hit

local Other = ReplicatedStorage.Props.Other

local THROW_RANGE = 60
local FLIGHT_SPEED = 90 -- studs per second
local FLIGHT_STEPS = 50

--- @class Ball
--- The paper ball: a thrown stun. Aiming is a raycast filtered to enemies only, so the throw
--- either connects or never leaves the player's hand -- there is no wasted ball. Flight and
--- impact are simulated here on the thrower's client; the server re-checks the hit before it
--- counts (see StunService).
local Ball = {}
Ball.__index = Ball

local function setUpConnections(self)
	self.Connections = {}

	self.Connections.Equipped = self.Ball.Equipped:Connect(function(mouse: Mouse)
		local humanoid = self.Ball.Parent:FindFirstChildOfClass("Humanoid")
		self.ThrowTrack = humanoid.Animator:LoadAnimation(self.Ball.Animations.Throw)
		self.Mouse = mouse
	end)

	self.Connections.Activated = self.Ball.Activated:Connect(function()
		self:Activate()
	end)
end

function Ball.new(ball: Tool)
	local self = setmetatable({}, Ball)

	self.Ball = ball
	self.Playing = false

	setUpConnections(self)

	return self
end

-- The enemy model under the crosshair, or nil if the player is not aiming at one.
function Ball:_findTarget(): Model?
	local start = self.Ball:GetPivot().Position
	local direction = (self.Mouse.Hit.Position - start).Unit * THROW_RANGE

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = TagService:GetTaggedOfAncestor(workspace, "Enemy")

	local result = workspace:Raycast(start, direction, params)
	if not result then return nil end

	local enemy = result.Instance
	while enemy and not enemy:HasTag("Enemy") do
		enemy = enemy.Parent
	end
	return enemy
end

function Ball:Activate()
	if self.Playing or not self.Mouse then return end

	local enemy = self:_findTarget()
	if not enemy then return end

	self.Playing = true
	Delete:FireServer(self.Ball.Name, 1)

	local character = self.Ball.Parent
	self.ThrowTrack:Play()

	-- Hold the throw facing the target for as long as the animation runs.
	local face = task.spawn(function()
		while RunService.Heartbeat:Wait() do
			character:PivotTo(CFrame.lookAt(character:GetPivot().Position, enemy:GetPivot().Position))
		end
	end)

	self.ThrowTrack:GetMarkerReachedSignal("Throw"):Wait()
	if self.Ball:FindFirstChild("Ball") then
		AudioService:Play3DSound("Ball", self.Ball.Ball, false, "SFX")
	end

	self:Throw(self.Ball:GetPivot(), enemy)

	-- Last one out of the stack takes the visible ball with it.
	if self.Ball:GetAttribute("quantity") == 0 and self.Ball:FindFirstChild("Ball") then
		self.Ball.Ball:Destroy()
	end

	self.ThrowTrack.Ended:Wait()
	task.cancel(face)
	self.Playing = false
end

--- Flies a cloned ball from `origin` to the enemy's head and reports the hit to the server.
function Ball:Throw(origin: CFrame, enemy: Model)
	task.spawn(function()
		local head = enemy:FindFirstChild("Head")
		if not head then return end

		local clone = Other.Ball:Clone()
		clone.Parent = workspace

		local duration = (head.CFrame.Position - origin.Position).Magnitude / FLIGHT_SPEED
		for step = 1, FLIGHT_STEPS do
			clone.CFrame = origin:Lerp(head.CFrame, step / FLIGHT_STEPS)
			task.wait(duration / FLIGHT_STEPS)
		end

		clone:Destroy()
		Hit:FireServer(enemy)
	end)
end

function Ball:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
end

return Ball
