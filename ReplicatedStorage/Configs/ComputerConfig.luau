return {
	Tag = "HackComputer",
	IdAttribute = "ComputerId",

	ModelName = "ComputerModel",
	ScreenPath = { "Computer", "Screen" },

	Remotes = {
		Folder = "Computer",
		Complete = "Complete",
		Sync = "Sync",
	},

	Colors = {
		ScreenLocked = Color3.fromRGB(0, 132, 255),
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
		DepthMode = Enum.HighlightDepthMode.Occluded,
	},

	UI = {
		Container = "Interact",
		Prompt = "HackPrompt",

		TopMargin = 14,
		Padding = 4,
		PillHeight = 34,
		PillPaddingLeft = 7,
		PillPaddingRight = 7,
		KeyGap = 8,
		TextWidth = 42,

		KeySize = 24,
		KeyWideSize = 38,
		Rise = 8,
		EnterScale = 0.92,

		FadeInTime = 0.1,
		FadeOutTime = 0.16,

		PressScale = 0.12,
		PressDecay = 6,

		Colors = {
			Key = Color3.fromRGB(38, 38, 44),
			KeyPressed = Color3.fromRGB(158, 176, 208),
		},

		HackText = "Hack",

		HideCursorInSession = true,
	},

	IdleScreen = {
		PixelsPerStud = 90,
		Font = Enum.Font.Arcade,
		LockedText = "SYSTEM LOCKED",
		FallbackText = "ACCESS DENIED",
		HackedText = "ACCESS GRANTED",

		CycleTime = 2.4,
		BlinkTime = 0.9,

		Background = Color3.fromRGB(4, 8, 16),
		BackgroundTransparency = 0.35,
		Text = Color3.fromRGB(200, 240, 255),
		HackedTextColor = Color3.fromRGB(96, 255, 128),
		HackedBackgroundTransparency = 0.12,
	},

	HUD = {
		Name = "ComputersUI",
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
		Complete = Color3.fromRGB(96, 255, 128),
		FlashSpeed = 1.5,
		FlashDepth = 0.55,

		FallbackIcon = "PC",
	},
}
