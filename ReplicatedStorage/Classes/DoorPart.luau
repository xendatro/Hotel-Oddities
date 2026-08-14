local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DoorConfig = require(ReplicatedStorage.Configs.DoorConfig)
local AudioService = require(ReplicatedStorage.Services.AudioService)

--- @class DoorPart
--- One swinging slab: a `DoorPart`-tagged part inside a `Door` model. Only the slab moves, never the
--- model around it, so frames and trim stay put. Its PivotOffset is authored at the hinge, so the
--- whole animation is a rotation about the world vertical running through that point.
---
--- The side it swings to is picked once, on the way open, as the side away from whoever opened it,
--- and then held. Someone walking around the door does not flip it -- the choice is only revisited
--- after the slab has swung shut again.
local DoorPart = {}
DoorPart.__index = DoorPart

local OPEN_ANGLE = DoorConfig.OpenAngle
local STIFFNESS = DoorConfig.Stiffness
local DAMPING = DoorConfig.DampingRatio * 2 * math.sqrt(DoorConfig.Stiffness)

function DoorPart.new(part: BasePart)
	local self = setmetatable({}, DoorPart)

	self.Part = part
	self.ClosedPivot = part:GetPivot()
	self.ClosedCanCollide = part.CanCollide
	self.Hinge = self.ClosedPivot.Position
	self.Center = part.Position

	-- Hinge to the middle of the slab, flattened to horizontal. Both candidate swings carry this arm
	-- somewhere; comparing where they land is what "away" means.
	local arm = self.Center - self.Hinge
	self.Arm = Vector3.new(arm.X, 0, arm.Z)

	self.Angle = 0
	self.Velocity = 0
	self.Sign = 1
	self.Target = 0
	self.Forced = false
	self.AnimationPlayer = nil
	self.AnimationEnded = false
	self.AnimationStartAngle = 0
	self.AnimationStartPosition = 0

	return self
end

function DoorPart:IsOpen(): boolean
	return self.Target ~= 0
end

-- Which rotation direction carries the slab further from `from`.
function DoorPart:_swingSign(from: Vector3): number
	local radians = math.rad(OPEN_ANGLE)
	local plus = self.Hinge + CFrame.Angles(0, radians, 0):VectorToWorldSpace(self.Arm)
	local minus = self.Hinge + CFrame.Angles(0, -radians, 0):VectorToWorldSpace(self.Arm)
	return (plus - from).Magnitude >= (minus - from).Magnitude and 1 or -1
end

--- @param open boolean -- whether someone is close enough to hold it open
--- @param from Vector3? -- the nearest such player, used to choose a side
function DoorPart:SetOpen(open: boolean, from: Vector3?)
	if open and self.Forced then return end

	local wasOpen = self:IsOpen()

	if open and not wasOpen and from and math.abs(self.Angle) <= DoorConfig.ResideAngle then
		self.Sign = self:_swingSign(from)
	end
	self.Target = open and OPEN_ANGLE * self.Sign or 0

	if wasOpen ~= open then
		local player = AudioService:Play3DSound(open and "DoorOpen" or "DoorClose", self.Part, false, "SFX")
		self.AnimationPlayer = player
		self.AnimationEnded = false
		self.AnimationStartAngle = self.Angle
		self.AnimationStartPosition = AudioService:GetPlaybackBounds(player)

		player.Ended:Once(function()
			if self.AnimationPlayer == player then
				self.AnimationEnded = true
			end
		end)
	end
end

--- Holds the slab shut against something standing in the doorway, ignoring every player who would
--- otherwise push it open. It also goes solid while held, so the doorway reads as a barred way out
--- rather than one that simply refuses to animate.
function DoorPart:SetForced(forced: boolean)
	if self.Forced == forced then return end
	self.Forced = forced

	self.Part.CanCollide = forced or self.ClosedCanCollide
	if forced then
		self:SetOpen(false)
	end
end

function DoorPart:Step(deltaTime: number)
	local animationPlayer = self.AnimationPlayer
	if animationPlayer then
		local _, endPosition = AudioService:GetPlaybackBounds(animationPlayer)
		local progress
		if self.AnimationEnded then
			progress = 1
		elseif endPosition <= self.AnimationStartPosition then
			return
		else
			progress = math.clamp(
				(animationPlayer.TimePosition - self.AnimationStartPosition)
					/ (endPosition - self.AnimationStartPosition),
				0,
				1
			)
		end

		local easedProgress = progress * progress * (3 - 2 * progress)
		self.Angle = self.AnimationStartAngle + (self.Target - self.AnimationStartAngle) * easedProgress
		self.Velocity = 0
		self:_Apply()

		if progress >= 1 then
			self.AnimationPlayer = nil
			self.Angle = self.Target
			self:_Apply()
		end
		return
	end

	local target = self.Target
	if target == 0 and math.abs(self.Velocity) <= DoorConfig.SettleVelocity and math.abs(self.Angle) <= DoorConfig.SettleAngle then
		if self.Angle ~= 0 then
			self.Angle = 0
			self.Velocity = 0
			self:_Apply()
		end
		return
	end

	local remaining = math.min(deltaTime, 0.1)
	while remaining > 0 do
		local step = math.min(remaining, DoorConfig.MaxStep)
		remaining -= step

		self.Velocity += (-STIFFNESS * (self.Angle - target) - DAMPING * self.Velocity) * step
		self.Angle += self.Velocity * step

		-- The frame stops the slab. Without this the settle at the end of a close would carry it
		-- through the doorway and swing it open on the other side.
		if self.Angle * self.Sign < 0 then
			self.Angle = 0
			self.Velocity = 0
		end
	end

	self:_Apply()
end

function DoorPart:_Apply()
	-- About the world vertical through the hinge, not the pivot's own Y: a slab's local axes are not
	-- guaranteed to stand upright, and rotating in pivot space tips it over instead of swinging it.
	local rotation = CFrame.Angles(0, math.rad(self.Angle), 0)
	self.Part:PivotTo(CFrame.new(self.Hinge) * rotation * CFrame.new(-self.Hinge) * self.ClosedPivot)
end

function DoorPart:Destroy()
	if self.Part.Parent then
		self.Part.CanCollide = self.ClosedCanCollide
		self.Part:PivotTo(self.ClosedPivot)
	end
end

return DoorPart
