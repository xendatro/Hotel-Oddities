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
	},
}
