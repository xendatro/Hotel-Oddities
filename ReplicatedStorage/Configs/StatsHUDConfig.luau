return {
	EdgeMargin = 8,
	RowHeight = 18,
	CaptionWidth = 58,
	PanelWidth = 178,
	TextSize = 14,
	BackgroundTransparency = 0.45,

	Colors = {
		Caption = Color3.fromRGB(255, 255, 255),
		Background = Color3.fromRGB(0, 0, 0),
		Good = Color3.fromRGB(95, 220, 115),
		Fair = Color3.fromRGB(240, 205, 75),
		Bad = Color3.fromRGB(235, 85, 80),
		Unknown = Color3.fromRGB(145, 145, 155),
	},

	Enemies = {
		Interval = 0.25,
		RowHeight = 15,
		TextSize = 12,
		Hunting = {
			Stalk = true,
			Reveal = true,
			Chase = true,
			Attack = true,
			Pursue = true,
			Investigate = true,
		},
		Watching = {
			Seek = true,
			Lurk = true,
			Peek = true,
			Retreat = true,
			Rest = true,
			Flee = true,
		},
		AlwaysWarn = {
			Chaos = true,
		},
		IdleColor = Color3.fromRGB(120, 120, 130),
		HeadingColor = Color3.fromRGB(200, 200, 210),
	},

	Fps = {
		SampleWindow = 0.5,
		Good = 55,
		Fair = 30,
	},

	Ping = {
		Interval = 1,
		Good = 90,
		Fair = 180,
	},

	Danger = {
		Interval = 0.25,
		Good = 0.34,
		Fair = 0.67,
	},

	TagWaitTimeout = 20,
	TagPollInterval = 0.25,
	TagSettlePolls = 4,
}
