return {
	Modes = {
		{ Id = "All", Label = "All Players", Friends = false },
		{ Id = "Friends", Label = "Friends Only", Friends = true },
	},

	--- Seconds between teleports. The server owns this number; the client only counts it down.
	Cooldown = 60,
	--- The TeleportCooldown label while one is running. Takes the whole seconds left.
	CooldownFormat = "Cooldown %d",
	--- The marker's own countdown, shown where the distance normally is.
	MarkerCooldownFormat = "%ds",

	ArriveDistance = 4,

	Highlight = {
		FillColor = Color3.fromRGB(120, 235, 255),
		FillTransparency = 0.6,
		OutlineColor = Color3.fromRGB(236, 236, 240),
		OutlineTransparency = 0,
	},

	Marker = {
		Size = Vector2.new(260, 210),
		--- Raises the marker from the root part to just over the head.
		Offset = Vector3.new(0, 3, 0),
		MaxDistance = 1000,

		ReferenceHeight = 1080,
		MinScale = 0.8,
		MaxScale = 1.35,

		--- Where the bubble's centre and the name sit inside that box, in pixels from its top.
		BubbleCentre = 78,
		NameIdleY = 74,
		NameFocusY = 158,

		BubbleSize = 118,
		--- The soft ring of colour behind the headshot, as a multiple of the bubble.
		HaloScale = 1.34,
		HaloTransparency = 0.68,
		RingThickness = 3,

		NameSize = 20,
		IdleNameSize = 17,
		DistanceSize = 15,
		ShowDistance = true,
		DistanceFormat = "%dm",
	},

	--- How near the aim point a marker has to be before it opens, and how it moves when it does.
	Focus = {
		RadiusScale = 0.13,
		MinRadius = 88,
		MaxRadius = 260,
		ReleaseSlack = 1.35,

		InTime = 0.26,
		OutTime = 0.15,
		RestScale = 0.5,

		PulsePeriod = 1.7,
		PulseAmount = 0.05,
	},

	Press = {
		Scale = 0.9,
		Time = 0.07,
		--- The flare a taken teleport leaves behind.
		ConfirmScale = 1.5,
		ConfirmTime = 0.34,
	},

	Colors = {
		Ring = Color3.fromRGB(120, 235, 255),
		RingCooldown = Color3.fromRGB(146, 148, 158),
		Halo = Color3.fromRGB(120, 235, 255),
		Plate = Color3.fromRGB(12, 13, 17),
		PlateStroke = Color3.fromRGB(120, 235, 255),
		Name = Color3.fromRGB(238, 242, 248),
		Distance = Color3.fromRGB(120, 235, 255),
		DistanceCooldown = Color3.fromRGB(172, 174, 184),
	},
}
