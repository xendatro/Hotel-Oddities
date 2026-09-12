return {
	Enabled = true,

	MinDuration = 45,
	MaxDuration = 120,
	MinimumPlayerDistance = 32,
	Effects = {
		Transparency = {
			SpawnIntervalMin = 180,
			SpawnIntervalMax = 420,
		},
		MapLightsOut = {
			SpawnIntervalMin = 240,
			SpawnIntervalMax = 480,
			MinDuration = 60,
			MaxDuration = 120,
			MinimumPlayerDistance = 48,
			ChunkSize = 215,
			ChunkHeight = 56,
			ChunkBelow = 4,
			MinimumLights = 2,
			PickAttempts = 96,
		},
		DoorsOpen = {
			SpawnIntervalMin = 180,
			SpawnIntervalMax = 420,
			OpeningSpeed = 0.75,
		},
		HallwayChaos = {
			SpawnIntervalMin = 300,
			SpawnIntervalMax = 300,

			OccupiedChance = 0.7,

			OpeningSpeed = 1.2,
			ClosingSpeed = 1.2,
			DoorIntervalMin = 0.3,
			DoorIntervalMax = 1.1,
			LightIntervalMin = 0.06,
			LightIntervalMax = 0.24,
		},
		HallwayBlocker = {
			SpawnIntervalMin = 180,
			SpawnIntervalMax = 270,
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
			SpawnIntervalMin = 1500,
			SpawnIntervalMax = 2500,
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
			PlankWidth = 1.8,
			PlankOverhang = 0.25,
			PlankLift = 0.04,
			PlankAngle = 8,
			PlankColor = Color3.fromRGB(111, 70, 38),
			PlankMaterial = Enum.Material.Wood,

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
		HallwayCrush = {
			SpawnIntervalMin = 240,
			SpawnIntervalMax = 360,
			MinDuration = 26,
			MaxDuration = 40,

			OccupiedChance = 0.55,
			OccupiedChanceReferencePlayers = 10, --scales down the chance as more players join
			PickAttempts = 64,
			-- Longest run that closes at once.
			MaxLength = 130,

			-- Seconds the walls take to meet, and to slide back on stop.
			CloseTime = 9,
			OpenTime = 4,
			StepInterval = 1 / 30,
			-- Studs the two sides overlap by once they have met.
			SealOverlap = 0.3,
			-- Clear corridor width at which anyone still inside is crushed.
			KillWidth = 2.2,
			MinimumHRPOverlap = 0.55,
			-- Studs trimmed off each end of a lethal stretch, so standing at the
			-- mouth of an intersection is never counted as being crushed.
			SafeMargin = 2,
			-- Studs past each edge of a doorway that still count as standing in it,
			-- so being off to one side of a door is not lethal.
			DoorwayMargin = 2,
			-- Extra width allowed when validating a client's own crush report.
			KillTolerance = 0.75,
			-- Seconds a sealed corridor waits before the server kills without a report.
			BackstopDelay = 1.5,
			-- Studs the wooden trim is pushed past the end of a closing run, so it
			-- does not z-fight the wall it was never meant to sit flush against.
			TrimOvershoot = 0.12,
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
