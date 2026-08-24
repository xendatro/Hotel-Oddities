return {
	Modes = {
		{ Id = "All", Label = "All Players", Friends = false },
		{ Id = "Friends", Label = "Friends Only", Friends = true },
	},

	Cooldown = 60,
	CooldownFormat = "Cooldown %d",
	MarkerCooldownFormat = "%ds",

	ArriveDistance = 4,

	Highlight = {
		FillColor = Color3.fromRGB(214, 176, 110),
		FillTransparency = 0.68,
		OutlineColor = Color3.fromRGB(243, 232, 205),
		OutlineTransparency = 0,
	},

	Marker = {
		Size = Vector2.new(260, 310),
		Offset = Vector3.new(0, 3, 0),
		MaxDistance = 1000,

		ReferenceHeight = 1080,
		MinScale = 0.8,
		MaxScale = 1.35,

		BubbleCentre = 128,
		NameIdleY = 124,
		NameFocusY = 208,

		BubbleSize = 118,
		HaloScale = 1.34,
		HaloTransparency = 0.68,
		RingThickness = 3,

		NameSize = 20,
		IdleNameSize = 17,
		DistanceSize = 16,
		PlateGap = 12,
		ShowDistance = true,
		DistanceFormat = "%dm",
	},

	Focus = {
		RadiusScale = 0.13,
		MinRadius = 88,
		MaxRadius = 260,
		ReleaseSlack = 1.35,

		InTime = 0.26,
		OutTime = 0.24,
		RestScale = 0.5,

		PulsePeriod = 1.7,
		PulseAmount = 0.05,
	},

	Press = {
		Scale = 0.9,
		Time = 0.07,
		ConfirmScale = 1.5,
		ConfirmTime = 0.34,
	},

	Colors = {
		Ring = Color3.fromRGB(74, 57, 40),
		RingCooldown = Color3.fromRGB(140, 130, 116),
		Halo = Color3.fromRGB(217, 199, 160),
		Plate = Color3.fromRGB(227, 213, 176),
		PlateStroke = Color3.fromRGB(74, 57, 40),
		Name = Color3.fromRGB(46, 35, 24),
		NameIdle = Color3.fromRGB(240, 230, 206),
		NameStroke = Color3.fromRGB(20, 15, 10),
		Distance = Color3.fromRGB(96, 24, 18),
		DistanceCooldown = Color3.fromRGB(112, 102, 90),
	},

	Fonts = {
		Name = Enum.Font.Merriweather,
		Distance = Enum.Font.Merriweather,
	},
}
