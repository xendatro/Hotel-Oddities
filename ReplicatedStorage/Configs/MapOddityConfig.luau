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
		HallwayVoid = {
			RollInterval = 300,
			InitialDelay = 120,
			TriggerChance = 0.15,
			MinDuration = 60,
			MaxDuration = 120,

			SpanPadding = 0,
			WidthPadding = 0.25,
			IntersectionInset = 0.5,
			PickAttempts = 96,

			GazeCone = 120,
			GazeDistance = 1000000,

			WallThickness = 0.8,
			WallTransparency = 0,
			WallColor = Color3.fromRGB(18, 18, 18),
			WallMaterial = Enum.Material.Slate,

			PlankThickness = 0.35,
			PlankWidth = 1.2,
			PlankOverhang = 0.25,
			PlankLift = 0.04,
			PlankColor = Color3.fromRGB(111, 70, 38),
			PlankMaterial = Enum.Material.WoodPlanks,

			VoidDepth = 36,
			VoidLayerCount = 12,
			VoidLayerThickness = 0.3,
			VoidLayerGap = 2.5,
			VoidTopOffset = 3,
			VoidEdgeInset = 0,
			VoidTopTransparency = 0.82,
			VoidBottomTransparency = 0.08,
			KillDepth = 1.25,
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
