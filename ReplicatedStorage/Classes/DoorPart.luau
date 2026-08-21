local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DoorConfig = require(ReplicatedStorage.Configs.DoorConfig)
local AudioService = require(ReplicatedStorage.Services.AudioService)

local DoorPart = {}
DoorPart.__index = DoorPart

local OPEN_ANGLE = DoorConfig.OpenAngle
local STIFFNESS = DoorConfig.Stiffness
local DAMPING = DoorConfig.DampingRatio * 2 * math.sqrt(DoorConfig.Stiffness)

local function horizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function findDoorModel(part: BasePart): Model?
	local instance: Instance? = part.Parent
	while instance and instance ~= workspace do
		if instance:IsA("Model") and instance.Name == "Door" then
			return instance
		end
		instance = instance.Parent
	end
	return nil
end

function DoorPart.new(part: BasePart)
	local self = setmetatable({}, DoorPart)

	self.Part = part
	self.ClosedPivot = part:GetPivot()
	self.ClosedCanCollide = part.CanCollide
	self.Hinge = self.ClosedPivot.Position
	self.Center = part.Position

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
	self.OddityClaims = {}

	local doorModel = findDoorModel(part)
	local outward = doorModel and horizontal(doorModel:GetPivot().LookVector)
	self.Outward = if outward and outward.Magnitude > 1e-3 then outward.Unit else nil

	return self
end

function DoorPart:IsOpen(): boolean
	return self.Target ~= 0
end

function DoorPart:_swingSign(from: Vector3): number
	local radians = math.rad(OPEN_ANGLE)
	local plus = self.Hinge + CFrame.Angles(0, radians, 0):VectorToWorldSpace(self.Arm)
	local minus = self.Hinge + CFrame.Angles(0, -radians, 0):VectorToWorldSpace(self.Arm)
	return (plus - from).Magnitude >= (minus - from).Magnitude and 1 or -1
end

function DoorPart:_swingSignAlong(direction: Vector3): number
	local radians = math.rad(OPEN_ANGLE)
	local plus = CFrame.Angles(0, radians, 0):VectorToWorldSpace(self.Arm)
	local minus = CFrame.Angles(0, -radians, 0):VectorToWorldSpace(self.Arm)
	return plus:Dot(direction) >= minus:Dot(direction) and 1 or -1
end

function DoorPart:_oddityClaim(): { Blocked: boolean, Speed: number, Chaos: boolean? }?
	for _, claim in self.OddityClaims do
		if not claim.Blocked then return claim end
	end
	return nil
end

function DoorPart:_hasOtherOddity(token: number): boolean
	for otherToken, claim in self.OddityClaims do
		if otherToken ~= token and not claim.Blocked then return true end
	end
	return false
end

function DoorPart:_applyOddity()
	local claim = self:_oddityClaim()
	if claim and not claim.Chaos then
		self:_setOpen(true, nil, claim.Speed, self.Outward)
	elseif not claim then
		self:_setOpen(false, nil, nil, nil)
	end
end

function DoorPart:_setOpen(
	open: boolean,
	from: Vector3?,
	playbackSpeed: number?,
	preferredDirection: Vector3?
)
	if open and self.Forced then return end

	local wasOpen = self:IsOpen()

	if open and not wasOpen and from and math.abs(self.Angle) <= DoorConfig.ResideAngle then
		self.Sign = self:_swingSign(from)
	elseif open and not wasOpen and preferredDirection and math.abs(self.Angle) <= DoorConfig.ResideAngle then
		self.Sign = self:_swingSignAlong(preferredDirection)
	end
	self.Target = open and OPEN_ANGLE * self.Sign or 0

	if wasOpen ~= open then
		local settings = if playbackSpeed then { PlaybackSpeed = playbackSpeed } else nil
		local player = AudioService:Play3DSound(open and "DoorOpen" or "DoorClose", self.Part, false, "SFX", settings)
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

function DoorPart:SetOpen(open: boolean, from: Vector3?)
	if next(self.OddityClaims) then
		if not self:_oddityClaim() or not self:_oddityClaim().Chaos then
			self:_applyOddity()
		end
		return
	end
	self:_setOpen(open, from, nil, nil)
end

function DoorPart:SetOddityOpen(token: number, playbackSpeed: number)
	self.OddityClaims[token] = {
		Blocked = self.Forced,
		Speed = playbackSpeed,
		Chaos = false,
	}
	if not self.Forced then
		if self.Outward then
			self.Sign = self:_swingSignAlong(self.Outward)
		end
		self:_applyOddity()
	end
end

function DoorPart:SetOddityChaos(
	token: number,
	openSpeed: number,
	closeSpeed: number,
	intervalMin: number,
	intervalMax: number
)
	local claim = {
		Blocked = self.Forced,
		Speed = openSpeed,
		CloseSpeed = closeSpeed,
		IntervalMin = math.min(intervalMin, intervalMax),
		IntervalMax = math.max(intervalMin, intervalMax),
		Chaos = true,
	}
	self.OddityClaims[token] = claim

	task.spawn(function()
		task.wait(math.random() * (claim.IntervalMax - claim.IntervalMin) + claim.IntervalMin)
		while self.OddityClaims[token] == claim do
			if not claim.Blocked and not self:_hasOtherOddity(token) then
				local opening = not self:IsOpen()
				if opening then
					if self.Outward then
						self.Sign = self:_swingSignAlong(self.Outward)
					end
				end
				self:_setOpen(opening, nil, if opening then claim.Speed else claim.CloseSpeed, nil)
			end
			task.wait(math.random() * (claim.IntervalMax - claim.IntervalMin) + claim.IntervalMin)
		end
	end)
end

function DoorPart:ClearOddity(token: number)
	self.OddityClaims[token] = nil
	if next(self.OddityClaims) then
		self:_applyOddity()
	elseif not self.Forced then
		self:_setOpen(false, nil, nil, nil)
	end
end

function DoorPart:SetForced(forced: boolean)
	if self.Forced == forced then return end
	self.Forced = forced

	self.Part.CanCollide = forced or self.ClosedCanCollide
	if forced then
		for _, claim in self.OddityClaims do
			claim.Blocked = true
		end
		self:_setOpen(false, nil, nil, nil)
	elseif next(self.OddityClaims) then
		for _, claim in self.OddityClaims do
			claim.Blocked = false
		end
		self:_applyOddity()
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

		if self.Angle * self.Sign < 0 then
			self.Angle = 0
			self.Velocity = 0
		end
	end

	self:_Apply()
end

function DoorPart:_Apply()
	local rotation = CFrame.Angles(0, math.rad(self.Angle), 0)
	self.Part:PivotTo(CFrame.new(self.Hinge) * rotation * CFrame.new(-self.Hinge) * self.ClosedPivot)
end

function DoorPart:Destroy()
	table.clear(self.OddityClaims)
	if self.Part.Parent then
		self.Part.CanCollide = self.ClosedCanCollide
		self.Part:PivotTo(self.ClosedPivot)
	end
end

return DoorPart
