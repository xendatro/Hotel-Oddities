return {
	--- Carried by the drawer MODEL, not its parts.
	Tag = "Drawer",
	--- Where the open/shut state lives, written by the server on the model and read by everyone.
	Attribute = "DrawerOpen",

	--- Studs the drawer travels along its outward axis when opened.
	OpenDistance = 1,
	AutoCloseDelay = 60,
	AutoCloseCheckInterval = 60,
	OpenedAtAttribute = "DrawerOpenedAt",

	OutwardAxis = Vector3.new(0, 0, -1),
	HandleKeyword = "handle",
	--- How far off centre the handle has to sit before its face is believed, in studs.
	HandleThreshold = 0.25,

	Stiffness = 190,
	DampingRatio = 0.85,
	--- Seconds of simulation per integration step; long frames are split so a hitch cannot fling it.
	MaxStep = 1 / 120,
	--- Below both of these a settling drawer is snapped home and stops being stepped.
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
			--- Right trigger on a gamepad.
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
		--- Occluded rather than always-on-top: a drawer behind a wall should not glow through it.
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
		--- Name of the prompt built under the Cursor ScreenGui at edit time.
		Container = "Interact",
		--- Pixels below the middle of the screen, where the cursor dot sits.
		TopMargin = 14,
		Padding = 4,
		PillHeight = 34,
		PillPaddingLeft = 7,
		PillPaddingRight = 7,
		--- Between the badge and the word.
		KeyGap = 8,
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
			Panel = Color3.fromRGB(18, 18, 22),
			Stroke = Color3.fromRGB(72, 72, 82),
			Key = Color3.fromRGB(38, 38, 44),
			KeyPressed = Color3.fromRGB(158, 176, 208),
			Text = Color3.fromRGB(236, 236, 240),
		},

		--- Words on the prompt, picked by what the drawer would do next.
		OpenText = "Open",
		CloseText = "Close",
	},
}
