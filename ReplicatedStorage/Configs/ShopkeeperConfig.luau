return {
	Tag = "Shopkeeper",
	PageAttribute = "PageId",

	Targeting = {
		Reach = 10,
	},

	Input = {
		Keys = {
			Enum.KeyCode.E,
			Enum.KeyCode.ButtonR2,
		},
		KeyboardLabel = "E",
		GamepadLabel = "RT",
		TouchAction = "ShopkeeperOpen",
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

	UI = {
		Container = "Interact",
		Prompt = "ShopkeeperPrompt",
		TopMargin = 14,
		Padding = 4,
		PillHeight = 34,
		PillPaddingLeft = 7,
		PillPaddingRight = 7,
		KeyGap = 8,
		TextWidth = 92,
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
	},

	SmileAnimationId = 14366558676,
}
