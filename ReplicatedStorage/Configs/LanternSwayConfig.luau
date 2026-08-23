return {
	--- Model names (tagged Floor1Light) that swing. Ceiling-hung fixtures only; wall lamps and fans look wrong.
	SwayModelNames = { "HallwayLantern", "CeilingLight" },

	--- Studs from the camera beyond which a lantern holds still. 60-200.
	CameraCullRadius = 110,

	--- Hard cap on lanterns simulating at once; nearest to the camera win. 16-96.
	MaxSimulated = 48,

	--- Swing along the hallway, in degrees. The big visible swing. 10-45.
	AlongAmplitude = 34,

	--- Swing toward the walls, in degrees; auto-clamped tighter per lantern to what fits. 2-12.
	AcrossAmplitude = 6,

	--- Pendulum natural frequency in Hz. Lower = heavier, lazier. 0.5-1.5.
	BaseFrequency = 0.9,

	--- Per-lantern random spread on frequency, as a fraction. 0-0.5.
	FrequencyJitter = 0.3,

	--- Across-axis frequency relative to along. Keep it off 1.0 so swings trace loops, not lines. 1.05-1.3.
	AcrossFrequencyRatio = 1.18,

	--- How fast swings die out. Lower = keeps ringing, higher = sluggish. 0.02-0.35.
	DampingRatio = 0.04,

	--- Strength of the turbulent noise pushing the lantern, relative to amplitude. 0.1-1.2.
	NoiseStrength = 0.85,

	--- Speed the noise wanders, in Hz. Lower = slow gusts, higher = jittery. 0.1-1.
	NoiseScale = 0.5,

	--- Average random jolts per second per lantern. 0-2.
	ImpulseChance = 1.2,

	--- Jolt strength relative to a full-amplitude swing. 0-2.
	ImpulseStrength = 1.5,

	--- Yaw wobble in degrees as it swings. 2-30.
	TwistAmplitude = 18,

	--- Yaw wobble speed in Hz. 0.2-1.
	TwistFrequency = 0.6,

	--- Seconds for a lantern's sway to build in. 0.2-3.
	AttackTime = 0.4,

	--- Seconds to settle back to rest after the oddity clears. 1-5.
	ReleaseTime = 2.5,

	--- Extra start delay per stud along the span, so the disturbance travels down the hall. 0-0.15.
	SpanStagger = 0.05,

	--- Random extra start delay per lantern, in seconds. 0-2.
	StaggerJitter = 0.35,

	--- Studs of air kept between the lantern and a wall when clamping across-swing. 0.2-1.
	WallMargin = 0.4,

	--- How far the one-time wall probe looks, in studs. 4-10.
	ClearanceProbe = 6,

	--- Seconds between camera-distance re-sorts. 0.1-1.
	RecullInterval = 0.25,
}
