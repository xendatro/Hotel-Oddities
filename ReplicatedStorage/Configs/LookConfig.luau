return {
	SendInterval = 0.1,
	SendThreshold = math.rad(2),

	MaxPitch = math.rad(55),
	MaxYaw = math.rad(40),

	Neck = { Pitch = 0.6, Yaw = 0.65 },
	Waist = { Pitch = 0.35, Yaw = 0.15 },

	--- Exponential catch-up rate for the rendered tilt chasing the reported one.
	Smoothing = 8,

	--- How often the server refreshes a mirroring Mimic's tilt from its target's.
	MimicUpdateInterval = 0.1,

	Debug = {
		--- Renders the tilt on your own character too, so one person can watch it work.
		IncludeLocalPlayer = false,
	},
}
