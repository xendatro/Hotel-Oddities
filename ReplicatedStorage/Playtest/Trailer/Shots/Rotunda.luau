-- Walk onto the rotunda's bridge and tilt up the shaft while the frame rolls,
-- so the rings and portraits spiral into the dark above. One continuous crane
-- move: the tilt gathers speed as the walk slows and settles near vertical.
local Lens = require(script.Parent.Parent.Lens)

local X = 316.7
local EYE = -17.6

return {
	Duration = 5.6,
	Warmup = 3,
	Park = CFrame.new(X, -19.6, 112),
	Stream = { Vector3.new(X, 20, 126), Vector3.new(X, 60, 126) },
	Handheld = Lens.Handheld(7, 0.9),
	Keys = {
		{ Time = 0, Position = Vector3.new(X, EYE, 99.5), Yaw = 180, Pitch = 2, Roll = 0, Fov = 60, Handheld = 0.8 },
		{ Time = 1.9, Position = Vector3.new(X, EYE + 0.05, 105.2), Pitch = 9 },
		{ Time = 5.6, Position = Vector3.new(X, EYE + 0.2, 112), Yaw = 180, Pitch = 80, Roll = -26, Fov = 74, Handheld = 0.5 },
	},
}
