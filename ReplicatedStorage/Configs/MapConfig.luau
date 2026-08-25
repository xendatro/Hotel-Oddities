return {
	Remotes = {
		Folder = "Map",
		Sync = "Sync",
		Reveal = "Reveal",
		Landmark = "Landmark",
	},

	Rooms = {
		Tag = "RoomFloor",
		ComputerTag = "ComputerRoomFloor",
	},

	Landmarks = {
		Computer = { Tag = "HackComputer", Radius = 34 },
		Spawn = { Tag = "Spawn", Radius = 40 },
		Exit = { Tag = "Exit", Radius = 40 },
	},

	Gui = {
		ScreenGui = "Map",
		Paper = "Main",
		PageGroup = "Main",
		PageId = "Map",
		ViewportName = "Viewport",
		ContentName = "Content",
		InkName = "Ink",
		DangerName = "Danger",
		ShadeName = "Shade",
		LegendName = "Legend",
		MarkerName = "Markers",
	},

	Controls = {
		-- Fraction of the paper kept clear of the torn edges.
		Inset = 0.055,
		MinZoom = 1,
		MaxZoom = 4.5,
		WheelStep = 0.22,
		ZoomLerp = 16,
		PanLerp = 22,
		PinchSensitivity = 1,
	},

	Discovery = {
		-- Studs of hallway revealed to either side of the player.
		Radius = 30,
		Interval = 0.25,
		-- An interval must grow by this much before it is stored or replicated.
		MinGrowth = 1.5,
		HeightWindow = 24,
		BelowWindow = 6,
		-- Studs between line-of-sight samples along a newly seen span.
		VisibilityStep = 5,
		EyeHeight = 3,
	},

	Canvas = {
		Resolution = 2048,
		-- Ink and wash sizes are authored against this resolution and scaled from it.
		Reference = 1024,
		-- Fraction of the canvas left as blank margin around the drawn map.
		Margin = 0.06,
	},

	Ink = {
		Color = Color3.fromRGB(38, 30, 22),
		Opacity = 0.93,
		BleedOpacity = 0.3,
		BleedOffset = 2.3,
		Width = 3.0,
		WidthVariance = 0.75,
		-- Studs between generated polyline vertices before wobble is applied.
		SegmentLength = 5,
		Wobble = 1.9,
		WobbleScale = 0.11,
		Overshoot = 3.6,
		EndCapChance = 0.35,
		RoomWidthScale = 1.15,
		ComputerWidthScale = 1.45,
		-- Studs between the diagonal hatch strokes filling a computer room.
		HatchSpacing = 7,
		HatchWidthScale = 0.5,
		HatchOpacity = 0.55,
		-- Seconds the computer room draws itself over when first opened.
		RevealTime = 1.1,
	},

	Shade = {
		Color = Color3.fromRGB(58, 48, 32),
		Opacity = 0.6,
		-- Studs the cleared floor area is grown by so ink sits on the boundary.
		Bleed = 1.4,
		Grain = 0.055,
		EdgeWobble = 0.75,
		-- Studs the lit floor fades back to dark at an undiscovered frontier.
		FrontierFade = 13,
		-- Studs the lit floor softens over at its side edges.
		SoftEdge = 3.2,
		SoftSteps = 3,
		-- Canvas pixels the wash fades out over at the sheet edge.
		Feather = 105,
		-- Canvas pixels of corner rounding on the wash so corners are not harsh.
		CornerRadius = 150,
	},

	Legend = {
		Font = Enum.Font.Kalam,
		TextSize = 22,
		SwatchSize = 26,
		Width = 250,
		Height = 92,
		Spacing = 8,
		Padding = 12,
		Rows = {
			{ Kind = "Hatch", Label = "computer room" },
			{ Kind = "Done", Label = "hacked" },
		},
	},

	Danger = {
		Resolution = 128,
		Opacity = 0.5,
		Low = Color3.fromRGB(120, 132, 96),
		High = Color3.fromRGB(150, 46, 32),
	},

	Markers = {
		Fill = Color3.fromRGB(247, 241, 186),
		Size = 34,
		GlyphInset = 7,
		FillTransparency = 0.2,
		StrokeWidth = 2.5,
		PlayerSize = 22,
		FriendSize = 24,
		PopScale = 1.45,
		PopTime = 0.45,
		PingTime = 0.85,
		PingSize = 5,
		FlashTime = 0.6,
		DoneFill = Color3.fromRGB(122, 162, 92),
		DoneGlyph = "\u{2713}",
	},
}
