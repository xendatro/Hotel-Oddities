return {
	--- Model names (tagged Floor1Light) that swing.
	SwayModelNames = { "HallwayLantern" },

	--- Studs from the camera beyond which a lantern stays still. 60-200.
	CameraCullRadius = 110,

	--- Hard cap on lanterns simulating at once; nearest to the camera win. 16-96.
	MaxSimulated = 48,

	--- Max swing from vertical along the hallway, in degrees; clamped tighter per lantern to fit the hall. 15-60.
	SwingLimit = 55,

	--- Fraction of Roblox gravity the pendulum feels. Roblox default gravity is arcade-fast;
	--- 0.15 gives an earth-like slow heavy sway, 1 is quick and jittery. 0.05-1.
	GravityScale = 1,

	--- Bounce kept when a swing slams into its limit. 0-1.
	LimitBounce = 0.45,

	--- Wind push strength, in rad/s^2 at a full gust. 1-8.
	WindStrength = 40,

	--- Speed the wind gusts wander, in Hz. Lower = slow gusts. 0.1-1.
	WindSpeed = 0.55,

	--- Average random jolts per second per lantern. 0-2.
	ImpulseChance = 2,

	--- Angular speed a jolt adds, in rad/s. 0.2-2.
	ImpulseStrength = 5,

	--- Fraction of swing speed lost per second while red. 0.05-1.
	Damping = 0.12,

	--- Fraction of swing speed lost per second while settling after red clears. 1-6.
	SettleDamping = 3,

	--- Swing degrees below which a settling lantern snaps back to rest. 1-6.
	SettleAngle = 3,

	--- Studs of air kept between the lantern and a wall when clamping the swing. 0.2-1.
	WallMargin = 0.4,

	--- How far the one-time wall probe looks, in studs. 4-10.
	ClearanceProbe = 6,

	--- Seconds between camera-distance re-sorts. 0.1-1.
	RecullInterval = 0.25,
}
