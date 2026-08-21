return {
	SpeedMultiplier = 1.5,

	Stamina = {
		Max = 100,
		DrainRate = 17,
		RegenRate = 13,
		RegenDelay = 0.9,
	},

	Camera = {
		--- Degrees added to the camera's field of view at full sprint.
		FovBoost = 9,
		BlendSpeed = 6,
	},

	Input = {
		--- Held down, not toggled. Left trigger is the gamepad's sprint.
		HoldKeys = {
			Enum.KeyCode.LeftShift,
			Enum.KeyCode.RightShift,
			Enum.KeyCode.ButtonL2,
		},
		--- Touch gets a toggle instead: holding a screen button while also steering is unpleasant.
		TouchButtonTitle = "SPRINT",
		TouchButtonPosition = UDim2.new(1, -150, 1, -60),
		TouchButtonSize = UDim2.fromOffset(74, 74),
	},

	UI = {
		--- Bar geometry in pixels before scaling. It sits above the inventory hotbar, centred.
		Width = 260,
		Height = 10,
		CornerRadius = 5,
		Padding = 3,
		--- Distance from the bottom of the screen. The hotbar is 64 tall at 12 from the edge.
		BottomMargin = 88,

		Colors = {
			Track = Color3.fromRGB(12, 12, 16),
			Stroke = Color3.fromRGB(72, 72, 82),
			Fill = Color3.fromRGB(232, 232, 238),
			FillEdge = Color3.fromRGB(158, 176, 208),
			--- Taken over by these once the bar is running out, and again once it is spent.
			Low = Color3.fromRGB(226, 152, 92),
			Empty = Color3.fromRGB(214, 88, 88),
		},

		Transparency = {
			Track = 0.35,
			Stroke = 0.5,
		},

		--- Share of the bar below which it reads as low, and below which it reads as spent.
		LowThreshold = 0.32,
		EmptyThreshold = 0.02,

		FullHoldTime = 0.5,
		FadeOutTime = 0.45,
		FadeInTime = 0.12,
		FollowSpeed = 14,
		ColorFollowSpeed = 7,
		ExhaustBlendSpeed = 3.5,
		EmptyPulsePeriod = 0.7,
		EmptyTrackTint = 0.5,
	},
}
