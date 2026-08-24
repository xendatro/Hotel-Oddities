return {
	Tag = "Drawer",
	Attribute = "DrawerOpen",

	OpenDistance = 1,
	AutoCloseDelay = 60,
	AutoCloseCheckInterval = 60,
	OpenedAtAttribute = "DrawerOpenedAt",

	OutwardAxis = Vector3.new(0, 0, -1),
	HandleKeyword = "handle",
	HandleThreshold = 0.25,

	Stiffness = 190,
	DampingRatio = 0.85,
	MaxStep = 1 / 120,
	SettleDistance = 0.002,
	SettleVelocity = 0.05,

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
		TouchAction = "DrawerToggle",
		TouchButtonPosition = UDim2.new(1, -150, 1, -150),
		TouchButtonSize = UDim2.fromOffset(74, 74),
	},

	Highlight = {
		FillColor = Color3.fromRGB(255, 255, 255),
		OutlineColor = Color3.fromRGB(236, 240, 248),
		FillTransparency = 0.93,
		OutlineTransparency = 0.15,
		DepthMode = Enum.HighlightDepthMode.Occluded,
	},

	Sound = {
		Enabled = true,
		OpenTemplate = "DrawerOpen",
		CloseTemplate = "DrawerClose",
		PlaybackSpeed = 1.6,
		Group = "SFX",
	},

	UI = {
		Container = "Interact",
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
			Panel = Color3.fromRGB(18, 18, 22),
			Stroke = Color3.fromRGB(72, 72, 82),
			Key = Color3.fromRGB(38, 38, 44),
			KeyPressed = Color3.fromRGB(158, 176, 208),
			Text = Color3.fromRGB(236, 236, 240),
		},

		OpenText = "Open",
		CloseText = "Close",
	},
}
