return {
	PhysicalDistance = 30,
	TaggedSoundDistance = 30,
	TaggedSoundPickupFalloff = 2,
	RadioAllowedTag = "RadioAllowed",
	DeathActiveGrace = 0.75,
	TransmissionGrace = 0.5,
	VoiceVolume = 0.32,
	TaggedSoundVolume = 0.06,
	RadioPhysicalVolume = 0,
	RadioNoiseRadius = 35,
	RelaySyncInterval = 0.15,

	Modes = {
		{ Id = "All", Label = "All Players", Friends = false },
		{ Id = "Friends", Label = "Friends Only", Friends = true },
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
