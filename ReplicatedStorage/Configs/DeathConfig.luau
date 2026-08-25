export type Cause = {
	Name: string,
	Hint: string,
}

return {
	CauseMemory = 8,

	Revive = {
		ForceFieldDuration = 25,
	},

	Unknown = {
		Name = "The Hotel",
		Hint = "Nothing was chasing you. The hotel got you all by itself.",
	} :: Cause,

	Causes = {
		Chaser = {
			Name = "Mad Guest",
			Hint = "It sees you and it runs faster than you do. Get out of sight and hide in a room.",
		},

		CeilingDweller = {
			Name = "Ceiling Dweller",
			Hint = "It waits in the ceiling vents and drops on whoever opens one. Look up first.",
		},

		Blind = {
			Name = "Blind",
			Hint = "It cannot see. It only hears you. Running is loud, walking is quieter, and crouching makes no sound at all.",
		},

		WeepingAngel = {
			Name = "Weeping Angel",
			Hint = "It can only move when nobody is looking. Keep your eyes on it and walk backwards.",
		},

		Mimic = {
			Name = "Mimic",
			Hint = "It looks like another player, but it copies what you do a moment later. A real player will talk back.",
		},

		Stalker = {
			Name = "Stalker",
			Hint = "It follows right behind you at your own speed. Look behind you to catch it, but it will run once you do.",
		},

		Eye = {
			Name = "Eye",
			Hint = "Looking right at it kills you in about three seconds. Keep it at the side of your screen and walk away.",
		},

		Chaos = {
			Name = "Chaos",
			Hint = "The hallway lights turn red just before it shows up. That is your warning to get into a room.",
		},

		Sisters = {
			Name = "The Sisters",
			Hint = "There are two of them walking side by side, and they are slower than you. Go around them, never between them.",
		},

		HallwayVoid = {
			Name = "The Void",
			Hint = "The plank was the only floor left. Cross gaps slowly and watch for the hotel opening below you.",
		},

		HallwayCrush = {
			Name = "The Squeeze",
			Hint = "The corridor was getting narrower the whole time. When the walls start to move, run for the nearest opening.",
		},
	} :: { [string]: Cause },

	Screen = {
		DisplayOrder = 100,

		FadeInTime = 0.45,
		EyebrowDelay = 0.5,
		NameDelay = 0.8,
		RuleDelay = 1.15,
		HintDelay = 1.4,
		FadeOutTime = 0.55,
		MinimumTime = 8,
		ReadTime = 3,

		TypeSpeed = 24,
		CursorBlinkTime = 0.55,

		BackdropTransparency = 0,
		BlurSize = 32,
		Saturation = -0.85,
		Brightness = -0.15,
		Contrast = 0.15,

		VignetteSize = 0.34,
		VignetteStrength = 0.35,
		VignetteBreathe = 0.12,
		VignetteBreatheTime = 4.5,

		ScanlineCount = 96,
		ScanlineTransparency = 0.93,
		SweepHeight = 0.22,
		SweepTime = 6,
		SweepTransparency = 0.965,

		SplitIdle = 2,
		SplitBurst = 11,

		GlitchIntervalMin = 1.4,
		GlitchIntervalMax = 4.5,
		GlitchBurstTime = 0.14,
		GlitchShift = 7,
		GlitchSliceCount = 4,
		GlitchSliceHeight = 14,
		GlitchSliceTransparency = 0.78,

		ContentWidth = 0.66,
		ContentMaxWidth = 760,
		NameHeight = 92,
		EyebrowSize = 15,
		HintSize = 21,
		Spacing = 14,

		EyebrowFont = Enum.Font.GothamMedium,
		NameFont = Enum.Font.GothamBlack,
		HintFont = Enum.Font.Gotham,
		EyebrowText = "K I L L E D   B Y",

		Colors = {
			Backdrop = Color3.fromRGB(0, 0, 0),
			Eyebrow = Color3.fromRGB(132, 132, 140),
			Name = Color3.fromRGB(240, 240, 244),
			NameGhostRed = Color3.fromRGB(255, 40, 48),
			NameGhostCyan = Color3.fromRGB(0, 220, 235),
			Rule = Color3.fromRGB(96, 20, 24),
			Hint = Color3.fromRGB(186, 186, 194),
			Scanline = Color3.fromRGB(0, 0, 0),
			Sweep = Color3.fromRGB(255, 255, 255),
			Slice = Color3.fromRGB(255, 255, 255),
		},
	},
}
