return {
	Tag = "POI",

	Remotes = {
		Folder = "POI",
		Discovered = "Discovered",
		Enter = "Enter",
		Occupancy = "Occupancy",
		Sync = "Sync",
	},

	Detection = {
		-- The trigger is the tagged part's own volume grown by these studs.
		-- A "Radius" attribute grows a single part further sideways.
		Padding = 4,
		Interval = 0.1,
		-- Studs the player may stand above or below the part's box.
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
		Hold = 6,
		InTime = 0.75,
		OutTime = 0.7,
		-- Seconds between the eyebrow, title, rule and counter arriving.
		Stagger = 0.18,
		ExitDrift = 10,
		-- Pixels each line rises through as it fades in.
		Rise = 10,
		TypeTime = 0.9,
		RuleWidth = 190,
		RuleTime = 1.3,
		EyebrowTransparency = 0.35,
		TitleTransparency = 0,
		CounterTransparency = 0.45,
		RuleTransparency = 0.25,
		CountUpTime = 0.9,
		-- A queued popup waits this long after the previous one leaves.
		QueueGap = 0.35,
		EyebrowText = "POINT OF INTEREST",
		CounterText = "%d / %d DISCOVERED",
		CounterTextUnknownTotal = "%d DISCOVERED",
	},
}
