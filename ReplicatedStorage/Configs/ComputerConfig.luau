return {
	--- Carried by the computer MODEL, applied by the server at boot.
	Tag = "HackComputer",

	ModelName = "ComputerModel",
	ScreenPath = { "Computer", "Screen" },

	Remotes = {
		--- Folder under ReplicatedStorage.Communication, created by the server at require time.
		Folder = "Computer",
		Complete = "Complete",
		Sync = "Sync",
	},

	Colors = {
		ScreenLocked = Color3.fromRGB(0, 132, 255),
		--- Light neon green, the same green the minigames use for ACCESS GRANTED.
		ScreenHacked = Color3.fromRGB(96, 255, 128),
	},

	Targeting = {
		Reach = 10,
		ServerReach = 16,
		MaxPassthrough = 4,
	},

	Input = {
		Keys = {
			Enum.KeyCode.E,
			--- Right trigger on a gamepad.
			Enum.KeyCode.ButtonR2,
		},
		KeyboardLabel = "E",
		GamepadLabel = "RT",
		TouchAction = "ComputerHack",
		TouchButtonPosition = UDim2.new(1, -150, 1, -150),
		TouchButtonSize = UDim2.fromOffset(74, 74),

		ExitAction = "ComputerExit",
		ExitKeys = {
			Enum.KeyCode.Q,
			--- B on a gamepad, which is where "back out of this" already lives.
			Enum.KeyCode.ButtonB,
		},
	},

	Camera = {
		FillFraction = 0.92,
		MinDistance = 1,
		TweenTime = 0.35,
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
		Container = "Interact",
		--- What the clone is called once it is in place.
		Prompt = "HackPrompt",

		--- Pixels below the middle of the screen, where the cursor dot sits.
		TopMargin = 14,
		Padding = 4,
		PillHeight = 34,
		PillPaddingLeft = 7,
		PillPaddingRight = 7,
		--- Between the badge and the word.
		KeyGap = 8,
		--- Room set aside for the word. Fixed, so the pill is one shape rather than one that breathes.
		TextWidth = 42,

		KeySize = 24,
		KeyWideSize = 38,
		--- The prompt slides up into place over this many pixels as it fades in.
		Rise = 8,
		--- And starts a touch small, so it grows into place rather than appearing at full size.
		EnterScale = 0.92,

		FadeInTime = 0.1,
		FadeOutTime = 0.16,

		PressScale = 0.12,
		PressDecay = 6,

		Colors = {
			Key = Color3.fromRGB(38, 38, 44),
			KeyPressed = Color3.fromRGB(158, 176, 208),
		},

		--- The one word this prompt ever says.
		HackText = "Hack",

		HideCursorInSession = true,
	},

	IdleScreen = {
		--- Studs of canvas per stud of part. Low, because these are three or four short words.
		PixelsPerStud = 90,
		Font = Enum.Font.Arcade,
		LockedText = "SYSTEM LOCKED",
		FallbackText = "ACCESS DENIED",
		HackedText = "ACCESS GRANTED",

		--- Seconds each of the two lines is up, and the period of the block cursor's blink.
		CycleTime = 2.4,
		BlinkTime = 0.9,

		--- Drawn straight onto a Neon part, so the plate behind the words is dark and mostly clear.
		Background = Color3.fromRGB(4, 8, 16),
		BackgroundTransparency = 0.35,
		Text = Color3.fromRGB(200, 240, 255),
		HackedTextColor = Color3.fromRGB(96, 255, 128),
		HackedBackgroundTransparency = 0.12,
	},

	HUD = {
		Name = "ComputersUI",
		--- Above the world, below anything modal.
		DisplayOrder = 12,

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

		FallbackIcon = "PC",
	},
}
