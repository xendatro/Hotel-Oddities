-- The arrival elevator's doors part on corridor B and the camera drifts out
-- into the hotel in one continuous move. Door panels are driven locally from
-- their Edit positions.
local Lens = require(script.Parent.Parent.Lens)

local DOOR_SLIDE = 3.25
local OPEN_AT = 0.6
local OPEN_TIME = 2.1

local EYE = -17.75

local function smooth(alpha: number): number
	alpha = math.clamp(alpha, 0, 1)
	return alpha * alpha * alpha * (alpha * (alpha * 6 - 15) + 10)
end

return {
	Duration = 5.6,
	Warmup = 3,
	Park = CFrame.new(589.6, -19.6, -585),
	Stream = { Vector3.new(589.6, -19.6, -560), Vector3.new(589.6, -19.6, -530) },
	Handheld = Lens.Handheld(41, 1),
	Keys = Lens.Unwrap({
		Lens.Key(0, Vector3.new(589.58, EYE, -623.4), Vector3.new(589.6, EYE + 0.2, -560), { Fov = 60, Roll = 0, Handheld = 0.8 }),
		Lens.Key(5.6, Vector3.new(589.52, EYE + 0.08, -611.8), Vector3.new(589.45, EYE + 0.55, -560), { Fov = 57, Roll = -0.5, Handheld = 1 }),
	}),

	Setup = function(stage)
		local doors = workspace.Maze15.StartElevator.Doors
		local left, right = doors:FindFirstChild("Part2") :: BasePart, doors:FindFirstChild("Part1") :: BasePart
		return {
			Left = left,
			Right = right,
			LeftClosed = CFrame.new(587.93, -19.42, -616.21) * left.CFrame.Rotation,
			RightClosed = CFrame.new(591.24, -19.42, -616.21) * right.CFrame.Rotation,
		}
	end,

	Update = function(stage, ctx, time)
		local open = smooth((time - OPEN_AT) / OPEN_TIME) * DOOR_SLIDE
		ctx.Left.CFrame = ctx.LeftClosed + Vector3.new(-open, 0, 0)
		ctx.Right.CFrame = ctx.RightClosed + Vector3.new(open, 0, 0)
	end,

	Cleanup = function(stage, ctx)
		if ctx and ctx.Left then
			ctx.Left.CFrame = ctx.LeftClosed
			ctx.Right.CFrame = ctx.RightClosed
		end
	end,
}
