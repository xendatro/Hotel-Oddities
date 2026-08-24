return {
	SpeedMultiplier = 0.5,

	BlocksSprint = true,

	Camera = {
		Drop = 1.7,
		DropAnimated = 0.35,
		BlendSpeed = 9,
	},

	Body = {
		HipDrop = 0,

		IdleAnimationId = 132166956074684 :: number?,
		WalkAnimationId = 135369405756779 :: number?,
		AnimationFadeTime = 0.18,
		WalkCycleSpeed = 8,
		WalkThreshold = 0.5,
	},

	Stealth = {
		Attribute = "Crouching",

		NoiseRadius = 0,

		StepVolume = 0.16,
		StepPlaybackSpeed = 0.8,
		StepMaxDistance = 12,
		StepFrequencyMultiplier = 0.75,
	},

	Input = {
		Keys = {
			Enum.KeyCode.C,
			Enum.KeyCode.LeftControl,
			Enum.KeyCode.ButtonB,
		},
		StandOnJump = true,
	},

	Touch = {
		Text = "CROUCH",
		Position = UDim2.new(1, -18, 1, -150),
		Size = UDim2.fromOffset(74, 74),
		CornerRadius = 12,

		Colors = {
			Background = Color3.fromRGB(12, 12, 16),
			Stroke = Color3.fromRGB(72, 72, 82),
			Text = Color3.fromRGB(232, 232, 238),
			ActiveBackground = Color3.fromRGB(158, 176, 208),
			ActiveStroke = Color3.fromRGB(232, 232, 238),
			ActiveText = Color3.fromRGB(12, 12, 16),
		},

		Transparency = {
			Background = 0.35,
			Stroke = 0.5,
		},

		TextSize = 13,
	},
}
