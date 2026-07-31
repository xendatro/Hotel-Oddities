local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientTool = require(ReplicatedStorage.Classes.ClientTool)
local TagService = require(ReplicatedStorage.Services.TagService)

local Hit = ReplicatedStorage.Communication.Ball.Hit
local Other = ReplicatedStorage.Props.Other

--- @class Ball
--- The paper ball: a thrown stun. Aiming is a raycast filtered to enemies only, so the throw either
--- connects or never leaves the player's hand -- there is no wasted ball. Flight and impact are
--- simulated on the thrower's client; the server re-checks the hit before it counts.
local Ball = ClientTool.extend("Ball")

function Ball.new(tool: Tool)
	return ClientTool.new(tool, Ball)
end

function Ball:OnEquipped()
	local animations = self.Tool:FindFirstChild("Animations")
	local animation = animations and animations:FindFirstChild("Throw")
	if animation and self.Humanoid then
		self.ThrowTrack = self.Humanoid.Animator:LoadAnimation(animation)
	end
end

-- The enemy model under the crosshair, or nil if the player is not aiming at one.
function Ball:_findTarget(): Model?
	if not self.Mouse then return nil end

	local start = self.Tool:GetPivot().Position
	local direction = (self.Mouse.Hit.Position - start)
	if direction.Magnitude < 1e-3 then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = TagService:GetTaggedOfAncestor(workspace, "Enemy")

	local result = workspace:Raycast(start, direction.Unit * self.Config.Range, params)
	if not result then return nil end

	local enemy = result.Instance
	while enemy and not enemy:HasTag("Enemy") do
		enemy = enemy.Parent
	end
	return enemy
end

function Ball:OnActivated()
	local enemy = self:_findTarget()
	if not enemy or not self.ThrowTrack then return end

	local character = self.Character
	self.ThrowTrack:Play()

	-- Face the target for the length of the throw. Stops on its own via the flag, and bails the
	-- moment the enemy leaves the world -- pivoting toward a destroyed model would throw.
	self.Facing = true
	task.spawn(function()
		while self.Facing do
			if not enemy.Parent or not character.Parent then break end
			character:PivotTo(CFrame.lookAt(character:GetPivot().Position, enemy:GetPivot().Position))
			RunService.Heartbeat:Wait()
		end
	end)

	-- Bounded, so a missing "Throw" marker cannot strand the player mid-animation.
	local reached = self:WaitForMarker(self.ThrowTrack, "Throw", 5)
	if not reached or not enemy.Parent or not self:IsAlive() then return end

	-- Only spend once the throw is actually committed. The old version spent the ball the instant
	-- a target was found, so a throw interrupted before release still cost one.
	self:Consume(1)
	self:PlaySound(self.Config.Sound, self.Tool:FindFirstChild("Ball"))

	self:_throw(self.Tool:GetPivot(), enemy)

	-- The last of the stack takes the visible ball with it.
	if self:GetQuantity() <= 0 then
		local visible = self.Tool:FindFirstChild("Ball")
		if visible then
			visible:Destroy()
		end
	end

	self:WaitForTrack(self.ThrowTrack, 5)
end

--- Flies a cloned ball to the enemy's head, then reports the hit for the server to validate.
function Ball:_throw(origin: CFrame, enemy: Model)
	local template = Other:FindFirstChild("Ball")
	local head = enemy:FindFirstChild("Head")
	if not template or not head then return end

	task.spawn(function()
		local clone = template:Clone()
		clone.Parent = workspace

		local duration = (head.CFrame.Position - origin.Position).Magnitude / self.Config.FlightSpeed
		for step = 1, self.Config.FlightSteps do
			if not enemy.Parent then break end
			clone.CFrame = origin:Lerp(head.CFrame, step / self.Config.FlightSteps)
			task.wait(duration / self.Config.FlightSteps)
		end

		clone:Destroy()
		if enemy.Parent then
			Hit:FireServer(enemy)
		end
	end)
end

function Ball:OnCleanup()
	self.Facing = false
end

function Ball:OnDestroy()
	self.Facing = false
end

return Ball
