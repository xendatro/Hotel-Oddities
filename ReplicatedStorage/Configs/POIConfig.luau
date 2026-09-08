return {
	Tag = "POI",

	Remotes = {
		Folder = "POI",
		Discovered = "Discovered",
		Enter = "Enter",
		Sync = "Sync",
	},

	Detection = {
		-- Overridden per part by a "Radius" attribute.
		Radius = 22,
		Interval = 0.35,
		-- Studs the player may be above or below the part before it stops counting.
		HeightWindow = 30,
		BelowWindow = 12,
	},

	Sound = {
		Name = "POIDiscovered",
		Bus = "SFX",
		-- Seconds before the same point of interest plays its sound again.
		Cooldown = 120,
	},

	Gui = {
		ScreenGui = "POIGui",
		Card = "Card",
	},

	Popup = {
		Hold = 3.2,
		InTime = 0.4,
		OutTime = 0.35,
		-- Seconds between the eyebrow, title, rule and counter arriving.
		Stagger = 0.07,
		SlideOffset = 14,
		ExitDrift = 10,
		RuleWidth = 190,
		RuleTime = 0.7,
		EyebrowTransparency = 0.35,
		TitleTransparency = 0,
		CounterTransparency = 0.45,
		RuleTransparency = 0.25,
		CountUpTime = 0.5,
		-- A queued popup waits this long after the previous one leaves.
		QueueGap = 0.2,
		EyebrowText = "POINT OF INTEREST",
		CounterText = "%d / %d DISCOVERED",
		CounterTextUnknownTotal = "%d DISCOVERED",
	},
}
