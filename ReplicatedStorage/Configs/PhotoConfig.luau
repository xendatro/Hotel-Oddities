return {
	Tag = "PlacedCamera",
	ModelName = "PlacedCamera",

	Attributes = {
		SnapAt = "SnapAt",
		Snapped = "Snapped",
		Owner = "Owner",
	},

	Place = {
		Range = 14,
		MinDistance = 3,
		MinFloorNormal = 0.7,
		BodyHeight = 4.06,
		ModelYaw = math.pi,

		Preview = {
			Material = Enum.Material.ForceField,
			Color = Color3.fromRGB(180, 226, 255),
			Transparency = 0.35,
		},
	},

	Countdown = 8,

	Lens = {
		-- relative to the model's own pivot, which is turned by Place.ModelYaw
		Offset = CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0.05, -0.5),
		FieldOfView = 68,
		Cone = 78,
		MaxDistance = 120,
	},

	Figure = {
		Name = "ShadowFigure",
		BehindSubjects = 18,
		MinDepth = 28,
		MaxDepth = 65,
		MinStandoff = 14,
		SideOffset = 5,
		FloorDrop = 24,
		PivotHeight = 3,
		Clearance = 3,
		ForcedDepth = 34,
		ForcedSide = 3.5,
		MaxFloorRise = 8,
	},

	Capture = {
		FlashIn = 0.09,
		FlashHold = 0.05,
		FlashOut = 0.45,
		WarmupFrames = 6,
		HoldFrames = 1,
		FrameTimeout = 0.25,
		Timeout = 3,
	},

	Despawn = {
		UnseenFor = 2.5,
		MinLifetime = 4,
		MaxLifetime = 180,
		PollInterval = 0.3,
		Cone = 110,
		MaxDistance = 250,
	},

	Timer = {
		WarnAt = 3,
		PulseScale = 1.35,
		PulseTime = 0.25,
		SnapText = "SNAP",
		SnapHold = 1.2,
	},

	Develop = {
		Fullscreen = {
			Hold = 0.55,
			TravelTime = 0.85,
		},

		Expanded = {
			TravelTime = 0.42,
		},

		SlideTime = 0.6,
		SheenTime = 2.2,
		FadeTime = 0.8,
	},
}
