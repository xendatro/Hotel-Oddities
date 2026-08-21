return {
	Enabled = true,

	RollInterval = 45,
	InitialDelay = 45,
	TriggerChance = 0.15,

	MinDuration = 45,
	MaxDuration = 120,
	MinimumPlayerDistance = 32,
	Effects = {
		Transparency = {},
		DoorsOpen = {
			OpeningSpeed = 0.75,
		},
		HallwayChaos = {
			OpeningSpeed = 1.2,
			ClosingSpeed = 1.2,
			DoorIntervalMin = 0.3,
			DoorIntervalMax = 1.1,
			LightIntervalMin = 0.06,
			LightIntervalMax = 0.24,
		},
	},

	HallwayTransparency = 0.02,
	HallwayHeightWindow = 24,
	HallwayBelowWindow = 4,
	SpatialPadding = 0.5,
	MinimumPartHallwayFraction = 0.5,
}
