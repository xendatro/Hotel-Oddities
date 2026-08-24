local DEFAULT_DURATION = 4

export type Sample = {
	Time: number,
	Position: Vector3,
	Move: Vector3,
	Look: Vector3,
	Jumping: boolean,
}

local MotionTrail = {}
MotionTrail.__index = MotionTrail

export type MotionTrail = typeof(setmetatable(
	{} :: {
		Humanoid: Humanoid,
		RootPart: BasePart,
		Duration: number,
		Samples: { Sample },
	},
	MotionTrail
))

function MotionTrail.new(humanoid: Humanoid, rootPart: BasePart, duration: number?): MotionTrail
	local self = setmetatable({}, MotionTrail)

	self.Humanoid = humanoid
	self.RootPart = rootPart
	self.Duration = duration or DEFAULT_DURATION
	self.Samples = {}

	return self
end

function MotionTrail:Record()
	if self.Humanoid.Health <= 0 then return end

	local now = os.clock()
	local state = self.Humanoid:GetState()
	table.insert(self.Samples, {
		Time = now,
		Position = self.RootPart.Position,
		Move = self.Humanoid.MoveDirection * self.Humanoid.WalkSpeed,
		Look = self.RootPart.CFrame.LookVector,
		Jumping = state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall,
	})

	local samples = self.Samples
	local expired = 0
	while expired < #samples and now - samples[expired + 1].Time > self.Duration do
		expired += 1
	end
	if expired > 0 then
		local count = #samples
		table.move(samples, expired + 1, count, 1)
		for index = count - expired + 1, count do
			samples[index] = nil
		end
	end
end

function MotionTrail:Destroy()
	table.clear(self.Samples)
end

function MotionTrail:Latest(): Sample?
	return self.Samples[#self.Samples]
end

function MotionTrail:At(delay: number): Sample?
	local samples = self.Samples
	if #samples == 0 then return nil end

	local wanted = os.clock() - delay
	for index = #samples, 1, -1 do
		local sample = samples[index]
		if sample.Time <= wanted then
			local following = samples[index + 1]
			if not following then return sample end

			local alpha = (wanted - sample.Time) / (following.Time - sample.Time)
			return {
				Time = wanted,
				Position = sample.Position:Lerp(following.Position, alpha),
				Move = sample.Move:Lerp(following.Move, alpha),
				Look = sample.Look:Lerp(following.Look, alpha),
				Jumping = sample.Jumping or following.Jumping,
			}
		end
	end
	return samples[1]
end

return MotionTrail
