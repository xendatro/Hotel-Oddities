return {
	Enabled = true,

	ForceLowestLevel = true,

	FogEndByLevel = {
		[1] = 110,
		[2] = 130,
		[3] = 150,
		[4] = 170,
		[5] = 190,
		[6] = 205,
		[7] = 215,
		[8] = 225,
		[9] = 230,
		[10] = 230,
	},

	FogStartRatio = 0.45,

	FogColor = Color3.new(0, 0, 0),

	Cage = {
		Enabled = true,

		RadiusRatio = 1.05,
		Thickness = 4,
	},

	HighestFoggedLevel = 10,

	FogEndBlendSpeed = 2,

	ReleaseDistance = 3000,

	Automatic = {
		StartingLevel = {
			Desktop = 6,
			Console = 5,
			Mobile = 3,
		},

		LevelRange = {
			Desktop = { Min = 3, Max = 10 },
			Console = { Min = 3, Max = 8 },
			Mobile = { Min = 1, Max = 6 },
		},

		SampleWindow = 5,
		StepCooldown = 12,

		LowFpsThreshold = 35,
		HighFpsThreshold = 55,
	},
}
