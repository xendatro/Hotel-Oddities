return {
	Enabled = true,

	RollInterval = 45,
	InitialDelay = 45,
	TriggerChance = 0.15,

	MinDuration = 45,
	MaxDuration = 120,
	MinimumPlayerDistance = 32,
	Effects = {
		Transparency = {
			SpawnIntervalMin = 180,
			SpawnIntervalMax = 420,
		},
		DoorsOpen = {
			OpeningSpeed = 0.75,
		},
		HallwayChaos = {
			RollInterval = 300,
			InitialDelay = 120,
			TriggerChance = 1,

			OccupiedChance = 0.7,

			OpeningSpeed = 1.2,
			ClosingSpeed = 1.2,
			DoorIntervalMin = 0.3,
			DoorIntervalMax = 1.1,
			LightIntervalMin = 0.06,
			LightIntervalMax = 0.24,
		},
		HallwayBlocker = {
			TriggerChance = 0.2,
			DangerWeight = 0.35,
			SplitClearance = 12,
			GazeCone = 100,
			GazeDistance = 300,
			MinDuration = 45,
			MaxDuration = 90,
			BlockerHeight = 24,
			BlockerThickness = 1.5,
			BlockerTransparency = 0.18,
			BlockerColor = Color3.fromRGB(18, 23, 28),
			BlockerMaterial = Enum.Material.Glass,
		},
		ChaosWarning = {
			Ambient = false,
			OpeningSpeed = 1.2,
			ClosingSpeed = 1.2,
			DoorIntervalMin = 0.3,
			DoorIntervalMax = 1.1,
		},
	},

	HallwayTransparency = 0.02,
	HallwayHeightWindow = 24,
	HallwayBelowWindow = 4,
	SpatialPadding = 0.5,
	MinimumPartHallwayFraction = 0.5,
}
