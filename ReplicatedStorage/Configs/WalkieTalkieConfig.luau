return {
	PhysicalDistance = 30,
	TaggedSoundDistance = 30,
	TaggedSoundPickupFalloff = 2,
	RadioAllowedTag = "RadioAllowed",
	DeathActiveGrace = 0.75,
	TransmissionGrace = 0.5,
	VoiceVolume = 0.32,
	ProximityRadioBlend = 0.08,
	TaggedSoundVolume = 0.06,
	RadioPhysicalVolume = 0,
	RadioNoiseRadius = 35,
	RelaySyncInterval = 0.15,

	ToolName = "Walkie Talkie",
	PowerAttribute = "WalkiePowered",
	VoiceAttribute = "VoiceEligible",
	TransmitAttribute = "WalkieTransmitting",

	Keys = {
		Power = Enum.KeyCode.G,
		Raise = Enum.KeyCode.R,
	},

	Modes = {
		{ Id = "All", Label = "ALL", Friends = false },
		{ Id = "Friends", Label = "FRIENDS", Friends = true },
	},

	Categories = {
		{ Id = "Global", Label = "GLOBAL" },
		{ Id = "Voices", Label = "VOICES", Maximum = 2.5 },
		{ Id = "Monster", Label = "MONSTER" },
		{ Id = "Noise", Label = "RADIO NOISE" },
	},

	Ui = {
		ScrollSpeed = 0.9,
		HitPadding = 6,
		DragSpeed = 1,
		Colors = {
			Enabled = Color3.fromRGB(126, 240, 158),
			Disabled = Color3.fromRGB(240, 186, 74),
			NoVoice = Color3.fromRGB(238, 92, 78),
			Dim = Color3.fromRGB(70, 122, 88),
			Idle = Color3.fromRGB(24, 46, 32),
			Muted = Color3.fromRGB(238, 92, 78),
		},
		Status = {
			Enabled = "ONLINE",
			Disabled = "RADIO OFF",
			NoVoice = "NO VOICE",
			Muted = "MUTED",
			Self = "YOU",
		},
		Meter = {
			Gain = 6,
			Attack = 22,
			Release = 6,
		},
		Hints = {
			Talk = "HOLD LMB - TALK",
			Talking = "TRANSMITTING",
			Raised = "%s - LOWER RADIO",
			Settings = "%s - LOWER RADIO",
		},
		OffPrompt = "PRESS %s",
		OffPromptTouch = "TAP POWER",
	},

	Prompt = {
		Text = "[%s] TURN ON WALKIE-TALKIE",
		TouchText = "TAP THE POWER BUTTON TO USE YOUR WALKIE-TALKIE",
		FadeTime = 0.25,
	},

	Touch = {
		ActiveBackground = Color3.fromRGB(40, 90, 58),
	},

	Effects = {
		Compressor = {
			Threshold = -20,
			Ratio = 8,
			Attack = 0.01,
			Release = 0.18,
			MakeupGain = 14,
		},
		Bandpass = {
			Frequency = 1700,
			Q = 0.8,
		},
		Equalizer = {
			LowGain = -20,
			MidGain = 6,
			HighGain = -14,
		},
		DistortionLevel = 0.35,
		Tagged = {
			Bandpass = {
				Frequency = 1550,
				Q = 1.2,
			},
			Equalizer = {
				LowGain = -28,
				MidGain = 8,
				HighGain = -20,
			},
			DistortionLevel = 0.52,
		},
		Limiter = {
			MaxLevel = -1,
			Release = 0.08,
		},
		Static = {
			ActiveVolume = 1,
			DeathVolume = 1,
		},
	},
}
