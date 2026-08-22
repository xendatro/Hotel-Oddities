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
		FillColor = Color3.fromRGB(214, 176, 110),
		FillTransparency = 0.68,
		OutlineColor = Color3.fromRGB(243, 232, 205),
		OutlineTransparency = 0,
	},

	Marker = {
		Size = Vector2.new(260, 310),
		--- Raises the marker from the root part to just over the head.
		Offset = Vector3.new(0, 3, 0),
		MaxDistance = 1000,

		ReferenceHeight = 1080,
		MinScale = 0.8,
		MaxScale = 1.35,

		--- Where the bubble's centre and the name sit inside that box, in pixels from its top.
		--- The box runs taller than the art needs so the confirm flare and halo pulse stay inside it.
		BubbleCentre = 128,
		NameIdleY = 124,
		NameFocusY = 208,

		BubbleSize = 118,
		--- The soft ring of colour behind the headshot, as a multiple of the bubble.
		HaloScale = 1.34,
		HaloTransparency = 0.68,
		RingThickness = 3,

		NameSize = 20,
		IdleNameSize = 17,
		DistanceSize = 16,
		--- Space between the name and the distance, so the two do not read as one word.
		PlateGap = 12,
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
		OutTime = 0.24,
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
		Ring = Color3.fromRGB(74, 57, 40),
		RingCooldown = Color3.fromRGB(140, 130, 116),
		--- The soft wash behind the headshot: warm lamplight, not a screen glow.
		Halo = Color3.fromRGB(217, 199, 160),
		--- Aged paper, the same stock the index and its notes are printed on.
		Plate = Color3.fromRGB(227, 213, 176),
		PlateStroke = Color3.fromRGB(74, 57, 40),
		--- The name reads as ink on the open plate and as pale chalk when the plate is gone.
		Name = Color3.fromRGB(46, 35, 24),
		NameIdle = Color3.fromRGB(240, 230, 206),
		NameStroke = Color3.fromRGB(20, 15, 10),
		Distance = Color3.fromRGB(96, 24, 18),
		DistanceCooldown = Color3.fromRGB(112, 102, 90),
	},

	--- Serif throughout, as on the index pages. A hand reads badly at the distance's size.
	Fonts = {
		Name = Enum.Font.Merriweather,
		Distance = Enum.Font.Merriweather,
	},
}
