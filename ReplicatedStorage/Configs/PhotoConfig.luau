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
		Size = UDim2.fromScale(4, 2),
		Offset = Vector3.new(0, 2.6, 0),
		Font = Enum.Font.Code,
		Color = Color3.fromRGB(255, 236, 214),
		WarnColor = Color3.fromRGB(255, 96, 72),
		WarnAt = 3,
		StrokeColor = Color3.fromRGB(0, 0, 0),
		PulseScale = 1.35,
		PulseTime = 0.25,
		SnapText = "SNAP",
		SnapHold = 1.2,
	},

	Develop = {
		Fullscreen = {
			Size = UDim2.fromScale(1.15, 1.15),
			Hold = 0.55,
			TravelTime = 0.85,
		},

		Expanded = {
			Size = UDim2.fromScale(0.74, 0.74),
			TravelTime = 0.42,
			BackdropColor = Color3.fromRGB(8, 5, 4),
			BackdropTransparency = 0.35,
			Rotation = -1,
		},

		Close = {
			Size = UDim2.fromOffset(26, 26),
			Color = Color3.fromRGB(28, 20, 17),
			TextColor = Color3.fromRGB(238, 231, 214),
			Transparency = 0.15,
			FadeTime = 0.35,
		},

		Size = UDim2.fromScale(0.28, 0.28),
		Position = UDim2.new(1, -30, 1, -30),
		SlideFrom = UDim2.new(1, -30, 1.6, -30),
		Rotation = -3.5,
		SlideTime = 0.6,
		FrameColor = Color3.fromRGB(238, 231, 214),
		FramePadding = 0.045,
		FrameThickness = 0.055,
		BackdropColor = Color3.fromRGB(16, 10, 8),
		FinalColor = Color3.fromRGB(226, 214, 196),
		SheenTime = 2.2,
		VignetteTransparency = 0.35,
		FadeTime = 0.8,
	},
}
