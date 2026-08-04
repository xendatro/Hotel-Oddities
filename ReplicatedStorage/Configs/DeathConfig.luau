--- Everything the death screen reads: who killed you, what the player should have known, and how the
--- screen looks while it tells them. Shared, because the server only ever sends a cause id -- the
--- name and the hint are resolved on the client, so rewording a hint never touches gameplay code.
---
--- `Causes` keys are enemy ids: the same keys as `ServerStorage.Configs.EnemyConfigs`, which is what
--- `EnemyService:Spawn` stamps onto every enemy it puts in the world. An enemy with no entry here
--- falls back to `Unknown`, so a new enemy is safe to ship before its hint is written.
---
--- Hints are written as the thing you wish you had known ten seconds earlier: the tell, then the
--- counter, in a sentence or two. A death screen is read at a glance rather than studied, so length
--- costs more than it buys -- but each one still has to be specific, since a hint that could
--- describe any of them teaches nothing.

export type Cause = {
	Name: string,
	Hint: string,
}

return {
	--- Seconds a recorded cause stays credible. Only `Eye` deals damage a player can survive, so
	--- this is what stops a glance at it half a hallway ago from taking the blame for a later fall.
	CauseMemory = 8,

	--- Used for a death nothing claimed: falling, a hole, or an enemy with no entry below.
	Unknown = {
		Name = "The Hotel",
		Hint = "Nothing in here claimed this one. The building is as dangerous as the things walking it.",
	} :: Cause,

	Causes = {
		Chaser = {
			Name = "Chaser",
			Hint = "It hunts by sight and it is faster than you. Break its line of sight and get into a room.",
		},

		CeilingDweller = {
			Name = "Ceiling Dweller",
			Hint = "It drops out of a ceiling vent onto whoever opens one. Look up. On the floor it is just a Chaser.",
		},

		Blind = {
			Name = "Blind",
			Hint = "It only hears you. Sprinting carries twice as far as walking, and standing still makes no sound at all.",
		},

		WeepingAngel = {
			Name = "Weeping Angel",
			Hint = "It cannot move while anybody is looking at it. Back away facing it -- never turn around.",
		},

		Mimic = {
			Name = "Mimic",
			Hint = "It wears a player's face and copies your movement a beat late. A real player answers you; this only echoes.",
		},

		Stalker = {
			Name = "Stalker",
			Hint = "It walks a few steps behind you at your exact speed. Look over your shoulder -- being seen makes it run.",
		},

		Eye = {
			Name = "Eye",
			Hint = "It charges you for looking. Dead center on your screen kills in three seconds. Keep it at the edge and walk.",
		},

		Chaos = {
			Name = "Chaos",
			Hint = "The corridor lights turn red before it arrives. That is your cue to get off the hallway and into a room.",
		},

		Sisters = {
			Name = "The Sisters",
			Hint = "Two of them, abreast, slower than you walk. Step around the pair -- the space between them is not a gap.",
		},
	} :: { [string]: Cause },

	--- The screen itself. Everything visible is built in code from these values, so restyling it means
	--- editing this table and nothing else.
	Screen = {
		DisplayOrder = 100, -- above the inventory, which sits at 10

		--- Timing, in seconds, measured from the moment the screen is asked to appear.
		FadeInTime = 0.45,
		EyebrowDelay = 0.5,
		NameDelay = 0.8,
		RuleDelay = 1.15,
		HintDelay = 1.4,
		FadeOutTime = 0.55,
		--- The screen refuses to leave before it has finished saying what it is for: it holds until the
		--- hint has typed itself out and been sat with for `ReadTime`, and never for less than
		--- `MinimumTime`. Respawning does not cut that short -- a fast respawn would otherwise flash the
		--- hint past somebody before they had read a word of it.
		---
		--- Hints are short enough now that `MinimumTime` is what actually decides this; `ReadTime` only
		--- takes over if one is rewritten long. Note the hold outlasts the default five-second respawn
		--- either way, so raise `Players.RespawnTime` to match if you would rather not come back to the
		--- world behind a screen that is still up.
		MinimumTime = 8,
		ReadTime = 3,

		--- Characters per second the hint types itself out at. Slow on purpose, and most of what the
		--- screen is doing with its time: at a clip the hint reads as a terminal printing at you, and
		--- what should land is closer to something being said quietly to somebody who has just lost.
		--- The total time on screen is about what it was before this dropped -- it is spent typing now
		--- rather than sitting finished, which is the whole difference.
		TypeSpeed = 24,
		--- Blinks after the last typed character until the hint is finished.
		CursorBlinkTime = 0.55,

		--- How much of the world survives behind the black. Not quite opaque: with the blur and the
		--- desaturation below, what is left is enough to read as a room you can no longer reach.
		BackdropTransparency = 0.06,
		BlurSize = 32,
		Saturation = -0.85,
		Brightness = -0.15,
		Contrast = 0.15,

		--- Darkening drawn in from each edge, and how far in it reaches as a fraction of the screen.
		VignetteSize = 0.34,
		VignetteStrength = 0.35, -- transparency at the very edge; 0 would be solid black
		VignetteBreathe = 0.12, -- how far that wanders
		VignetteBreatheTime = 4.5, -- seconds for one full breath

		--- CRT lines over the whole screen, and the brighter band that crawls down through them.
		ScanlineCount = 96,
		ScanlineTransparency = 0.93,
		SweepHeight = 0.22,
		SweepTime = 6,
		SweepTransparency = 0.965,

		--- The colour split on the enemy's name: how many pixels the red and cyan ghosts sit off the
		--- white one while it is settled, and how far they are thrown during a glitch.
		SplitIdle = 2,
		SplitBurst = 11,

		--- Bursts arrive on a random interval and last `GlitchBurstTime`. During one, the whole block
		--- of text jumps sideways and a few torn bars cut across the screen.
		GlitchIntervalMin = 1.4,
		GlitchIntervalMax = 4.5,
		GlitchBurstTime = 0.14,
		GlitchShift = 7, -- pixels the text block is thrown sideways
		GlitchSliceCount = 4,
		GlitchSliceHeight = 14,
		GlitchSliceTransparency = 0.78,

		--- Layout, in pixels before scaling.
		ContentWidth = 0.66, -- of the screen
		ContentMaxWidth = 760,
		NameHeight = 92,
		EyebrowSize = 15,
		HintSize = 21,
		Spacing = 14,

		EyebrowFont = Enum.Font.GothamMedium,
		NameFont = Enum.Font.GothamBlack,
		HintFont = Enum.Font.Gotham,
		--- Spelled out with spaces because Roblox text has no letter spacing of its own.
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
