--- @class MotionTrail
--- A rolling record of how one character has been moving. Lookups interpolate between the samples
--- either side of the instant asked for, so replaying a character's movement on a delay comes out
--- continuous rather than stepped at whatever rate it happened to be recorded at.
---
--- What it stores is intent, not physics: a humanoid's `MoveDirection` is the input the player is
--- actually giving, where its assembly velocity carries knockback, slope slide and stair noise that
--- read as a twitching NPC when replayed.

local DEFAULT_DURATION = 4 -- seconds retained; the ceiling on how far back a lookup can reach

--- One instant of a character's movement.
export type Sample = {
	Time: number,
	Position: Vector3,
	Move: Vector3, -- intended movement in studs per second
	Look: Vector3, -- the direction the character is facing
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

--- Takes the parts rather than the character, and never yields: a respawn racing a wait in here would
--- leave the caller holding a trail that never arrives, bound to a body that no longer exists.
--- @param duration number? -- seconds of history to retain
function MotionTrail.new(humanoid: Humanoid, rootPart: BasePart, duration: number?): MotionTrail
	local self = setmetatable({}, MotionTrail)

	self.Humanoid = humanoid
	self.RootPart = rootPart
	self.Duration = duration or DEFAULT_DURATION
	self.Samples = {}

	return self
end

--- Adds this instant to the record and drops anything older than `Duration`. Call once a frame. Does
--- nothing while the character is dead, so a corpse does not flatline the trail into stillness.
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

	while #self.Samples > 0 and now - self.Samples[1].Time > self.Duration do
		table.remove(self.Samples, 1)
	end
end

--- The most recent instant recorded, or nil if nothing has been.
function MotionTrail:Latest(): Sample?
	return self.Samples[#self.Samples]
end

--- How the character was moving `delay` seconds ago, blended between the samples either side of that
--- instant. Nil if nothing has been recorded yet; a delay reaching past the record returns its oldest.
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
