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
		Thought = "Thought",
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
		ThoughtTransparency = 0.05,
		ThoughtCharTime = 0.035,
	},

	Thoughts = {
		["Bell"] = "A bell this big, and no rope. Who is meant to ring it?",
		["Chairs"] = "All these chairs, all facing that door. What are they waiting for?",
		["Circle Bridge"] = "Don't look down. There's nothing down there to look at anyway.",
		["Endless Bridges"] = "How far down does this go? ...How far up?",
		["Endless Paintings"] = "I could swear that one just moved.",
		["Endless Pillars"] = "Every row looks like the last one. Am I going in circles?",
		["Endless Room"] = "Didn't I just walk through this room?",
		["Endless Stairs"] = "I've climbed these stairs before. I'm sure of it.",
		["Floating"] = "The floor doesn't feel like it wants me standing on it.",
		["Glitched Hallway"] = "The walls are there. I can feel them. I just can't see them.",
		["Hallway"] = "The carpet runs straight into the rubble. Something came through here.",
		["Hallways"] = "Somebody forgot to build a floor. Or something took it.",
		["Mess"] = "Water everywhere. What happened to the people who ate here?",
		["Mirror"] = "My reflection is on the ceiling. ...Is it looking back?",
		["Paintings"] = "They're all watching the door. Or me.",
		["Pendulum"] = "It's keeping time. Just not any time I know.",
		["Pit"] = "That railing isn't going to stop anyone.",
		["Pool"] = "I can't see the bottom. I don't want to.",
		["Rooms"] = "Rooms inside rooms. Who were these built for?",
		["Stairs"] = "Another floor? ...It was there a second ago.",
		["The Garden"] = "It's raining. Indoors. And the plants don't seem to mind.",
		["The Hole"] = "One plank left. I'm not testing it.",
	},
}
