return {
	Remotes = {
		Folder = "Map",
		Sync = "Sync",
		Reveal = "Reveal",
	},

	Gui = {
		ScreenGui = "Map",
		Paper = "Main",
		InkName = "Ink",
		DangerName = "Danger",
		MarkerName = "Markers",
	},

	Discovery = {
		-- Studs of hallway revealed to either side of the player.
		Radius = 30,
		Interval = 0.25,
		-- An interval must grow by this much before it is stored or replicated.
		MinGrowth = 1.5,
		HeightWindow = 24,
		BelowWindow = 6,
	},

	Canvas = {
		Resolution = 1024,
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
	},

	Danger = {
		Resolution = 128,
		Opacity = 0.5,
		Low = Color3.fromRGB(120, 132, 96),
		High = Color3.fromRGB(150, 46, 32),
	},

	Markers = {
		Size = 26,
		PlayerSize = 18,
		PopScale = 1.45,
		PopTime = 0.45,
		PingTime = 0.85,
		PingSize = 5,
		FlashTime = 0.6,
	},
}
