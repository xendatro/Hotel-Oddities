return {
	Tag = "Sisters",

	Remotes = {
		Folder = "Sisters",
		Gaze = "Gaze",
		Gazed = "Gazed",
	},

	Gaze = {
		Range = 45,
		Angle = 10,
		DwellTime = 0.45,
		ServerRangeSlack = 20,
		Cooldown = 20,
		RetryDelay = 1.5,
		ReplyTimeout = 3,
	},

	Vertigo = {
		LeadTime = 1.4,
		Sound = "MimicSting",
		Shake = "Jolt",

		FlashColor = Color3.fromRGB(205, 220, 255),
		FlashTransparency = 0.55,
		FlashOutTime = 0.45,

		Blur = 16,
		BlurOutTime = 0.9,

		FovPull = -12,
		DrainInTime = 0.35,
		ReleaseTime = 1.2,
		StopTime = 0.3,
		Saturation = -0.85,
		Contrast = 0.25,
		TintColor = Color3.fromRGB(190, 205, 235),

		RingCount = 3,
		RingInterval = 0.18,
		RingTime = 1.1,
		RingStartScale = 0.04,
		RingEndScale = 1.7,
		RingThickness = 3,
		RingColor = Color3.fromRGB(235, 240, 255),
		RingOpacity = 0.85,
	},

	Warp = {
		Duration = 30,
	},
}
