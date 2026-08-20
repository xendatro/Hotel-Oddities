--- Everything the computer-hacking system reads: what counts as a hackable computer, how it is
--- looked at and asked to open, where the camera sits while a minigame is up, and how the two bits
--- of interface around it are drawn.
---
--- Hacking is PER PLAYER. Everyone hunts the same five computers, but each player breaks into their
--- own copy of each one: the server keeps a set of hacked models per player and syncs it only to that
--- player, and every screen in the hotel is coloured by the client looking at it. So nothing here is
--- shared state -- it is all presentation, and two players standing at the same monitor can honestly
--- be seeing different colours on it.
---
--- The minigames themselves do NOT read this: the framework carries its own Theme so the games stay
--- self-contained. The few colours repeated below are repeated on purpose, so nothing in Services
--- has to require a Modules folder that may not have been written yet.

return {
	--- Carried by the computer MODEL, applied by the server at boot.
	Tag = "HackComputer",

	--- What the server scans workspace for. A model of this name whose parent IS Workspace is the
	--- authoring template and deliberately never tagged -- it is furniture, not a puzzle.
	ModelName = "ComputerModel",
	--- Path from the tagged model down to the glowing face, one name per step. Kept as data because
	--- the screen part is added by a separate pass over the models and may not be there yet.
	ScreenPath = { "Computer", "Screen" },

	Remotes = {
		--- Folder under ReplicatedStorage.Communication, created by the server at require time.
		Folder = "Computer",
		--- Fired by the client when a minigame is won; the server checks it and files it against that
		--- one player.
		Complete = "Complete",
		--- Fired by the server AT ONE PLAYER with the whole array of models that player has hacked.
		--- Always a full snapshot -- there are only ever a handful of computers, so replacing the set
		--- outright costs nothing and cannot drift the way a stream of deltas can.
		Sync = "Sync",
	},

	Colors = {
		--- Painted by each CLIENT onto the Neon screen part, never by the server: which computers are
		--- green is a different answer for every player in the room.
		---
		--- Neon blue: a machine still asking for a password.
		ScreenLocked = Color3.fromRGB(0, 132, 255),
		--- Light neon green, the same green the minigames use for ACCESS GRANTED.
		ScreenHacked = Color3.fromRGB(96, 255, 128),
	},

	Targeting = {
		--- Studs from the camera within which a computer can be looked at. The server allows a little
		--- more than this before it refuses a completion.
		Reach = 10,
		ServerReach = 16,
		--- Invisible, walk-through parts -- region markers and the like -- are stepped over rather
		--- than treated as something blocking the view. This many of them, then the ray gives up.
		MaxPassthrough = 4,
	},

	Input = {
		Keys = {
			Enum.KeyCode.E,
			--- Right trigger on a gamepad.
			Enum.KeyCode.ButtonR2,
		},
		--- What the badge reads. Console gets the trigger's short name rather than a glyph, which no
		--- font here has.
		KeyboardLabel = "E",
		GamepadLabel = "RT",
		--- Touch has no cursor to rest on a computer, so it gets a button instead of a prompt. It is
		--- only bound while a computer is actually being looked at.
		TouchAction = "ComputerHack",
		TouchButtonPosition = UDim2.new(1, -150, 1, -150),
		TouchButtonSize = UDim2.fromOffset(74, 74),

		--- Leaving a session. Bound only while one is open, and sunk so Q cannot also do whatever else
		--- the game has put on it.
		ExitAction = "ComputerExit",
		ExitKeys = {
			Enum.KeyCode.Q,
			--- B on a gamepad, which is where "back out of this" already lives.
			Enum.KeyCode.ButtonB,
		},
	},

	Camera = {
		--- The camera does not stand at a fixed distance: it stands wherever the screen part fills this
		--- much of the LIMITING side of the viewport, worked out at open time from the live field of
		--- view and viewport size. A fixed number can only ever be right for one shape of window, and a
		--- phone in portrait and a widescreen monitor are not the same shape; this is right for both,
		--- and lands the player noticeably closer to the glass than the old 2.6 studs did.
		FillFraction = 0.92,
		--- Floor under that sum, in studs. Only reached by an oddly small screen part or a field of view
		--- something else has pulled somewhere strange -- it is there so the camera cannot end up inside
		--- the monitor it is reading.
		MinDistance = 1,
		TweenTime = 0.35,
		--- Only the ride out is eased. Leaving snaps: the moment the session is over the player wants
		--- their own eyes back, and a slow ride home with the controls still locked reads as a hang.
		EasingStyle = Enum.EasingStyle.Quad,
		EasingDirection = Enum.EasingDirection.Out,
	},

	Highlight = {
		FillColor = Color3.fromRGB(255, 255, 255),
		OutlineColor = Color3.fromRGB(236, 240, 248),
		FillTransparency = 0.93,
		OutlineTransparency = 0.15,
		--- Occluded rather than always-on-top: a computer behind a wall should not glow through it.
		DepthMode = Enum.HighlightDepthMode.Occluded,
	},

	UI = {
		--- The prompt built under the Cursor ScreenGui at edit time. It belongs to the drawers; this
		--- system clones it rather than sharing it, so two prompts can never fight over one CanvasGroup.
		Container = "Interact",
		--- What the clone is called once it is in place.
		Prompt = "HackPrompt",

		--- Pixels below the middle of the screen, where the cursor dot sits.
		TopMargin = 14,
		--- Room around the pill inside the group that fades. The pill's outline draws outside its own
		--- border and a CanvasGroup clips to its bounds, so without this the outline is cut in half.
		Padding = 4,
		PillHeight = 34,
		PillPaddingLeft = 7,
		PillPaddingRight = 7,
		--- Between the badge and the word.
		KeyGap = 8,
		--- Room set aside for the word. Fixed, so the pill is one shape rather than one that breathes.
		TextWidth = 42,

		--- The key badge is a square for a single-character key, and only widens for the ones that need
		--- two.
		KeySize = 24,
		KeyWideSize = 38,
		--- The prompt slides up into place over this many pixels as it fades in.
		Rise = 8,
		--- And starts a touch small, so it grows into place rather than appearing at full size.
		EnterScale = 0.92,

		FadeInTime = 0.1,
		FadeOutTime = 0.16,

		--- A press flashes the key badge: it shrinks by this much and brightens, then eases back at
		--- this rate per second.
		PressScale = 0.12,
		PressDecay = 6,

		Colors = {
			Key = Color3.fromRGB(38, 38, 44),
			KeyPressed = Color3.fromRGB(158, 176, 208),
		},

		--- The one word this prompt ever says.
		HackText = "Hack",

		--- The crosshair is hidden for the length of a session: the mouse is free and pointing at a
		--- minigame, so a dot pinned to the middle of the screen is just a lie.
		HideCursorInSession = true,
	},

	--- The screen of a computer nobody has touched yet. Deliberately quiet -- the Neon part colour is
	--- what actually reads across a room, and this is only there to say the thing is interactive.
	IdleScreen = {
		--- Studs of canvas per stud of part. Low, because these are three or four short words.
		PixelsPerStud = 90,
		Font = Enum.Font.Arcade,
		--- The label alternates between these two. The second is replaced by the assigned game's title
		--- when the minigame framework is loaded and willing to say what it picked.
		LockedText = "SYSTEM LOCKED",
		FallbackText = "ACCESS DENIED",
		--- What it says forever once the computer has been broken into. No tick glyph: the Arcade font
		--- has no character for one and would draw a box where the reassurance was meant to be.
		HackedText = "ACCESS GRANTED",

		--- Seconds each of the two lines is up, and the period of the block cursor's blink.
		CycleTime = 2.4,
		BlinkTime = 0.9,

		--- Drawn straight onto a Neon part, so the plate behind the words is dark and mostly clear.
		Background = Color3.fromRGB(4, 8, 16),
		BackgroundTransparency = 0.35,
		Text = Color3.fromRGB(200, 240, 255),
		--- Matches Colors.ScreenHacked and the framework's Accent. The plate is darkened underneath it,
		--- because green words on a green neon panel are no words at all.
		HackedTextColor = Color3.fromRGB(96, 255, 128),
		HackedBackgroundTransparency = 0.12,
	},

	HUD = {
		Name = "ComputersUI",
		--- Above the world, below anything modal.
		DisplayOrder = 12,

		--- Right edge. The Y is NOT the obvious half-height: the effects HUD grows from the middle of
		--- that edge and the revive card sits at 0.17-0.34 of it, and 0.375 is the middle of the only
		--- band between them that stays clear when both are up at once.
		EdgeMargin = 12,
		VerticalPosition = 0.375,
		Size = UDim2.fromOffset(96, 36),

		Font = Enum.Font.Arcade,
		IconSize = 22,
		IconPadding = 8,

		Background = Color3.fromRGB(6, 12, 24),
		BackgroundTransparency = 0.25,
		Stroke = Color3.fromRGB(0, 200, 255),
		StrokeThickness = 2,
		Text = Color3.fromRGB(220, 236, 255),
		--- What the pill turns into once every computer in the hotel has been broken into.
		Complete = Color3.fromRGB(96, 255, 128),
		--- Full cycles per second of the finished pill's pulse, and how far it fades at the trough.
		FlashSpeed = 1.5,
		FlashDepth = 0.55,

		--- Stands in for the icon until the art exists. Read as "PC" because two Arcade-font letters
		--- fill the same square a monitor would.
		FallbackIcon = "PC",
	},
}

