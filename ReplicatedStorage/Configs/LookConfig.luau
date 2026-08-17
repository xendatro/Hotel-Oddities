--- Every tunable of look replication: other players' torsos and heads tilting toward whatever
--- their camera is aimed at, and the Mimic borrowing the same tilt from whoever it is copying.

return {
	--- How often a client reports its own look direction, and how much it must have moved since the
	--- last report to be worth sending. Radians.
	SendInterval = 0.1,
	SendThreshold = math.rad(2),

	--- Hard clamps on what a character will visibly do, server-enforced. Kept modest on purpose:
	--- an owl-necked character reads as broken, not observant.
	MaxPitch = math.rad(55),
	MaxYaw = math.rad(40),

	--- How the total tilt is split between the two joints. The head carries most of it; the torso
	--- leans just enough to sell the posture.
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
