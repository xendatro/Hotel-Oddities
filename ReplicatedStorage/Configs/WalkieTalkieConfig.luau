--- Shared tuning for the walkie-talkie voice route.

return {
	--- Local sound from a held radio. Direct radio output is not distance limited.
	PhysicalRange = 30,
	AmbientRange = 30,
	RadioAllowedTag = "RadioAllowed",
	DeathActiveGrace = 0.75,
	-- The default voice route is raised slightly; radio routes are then attenuated below it.
	NormalVoiceVolume = 1.25,
	RadioOutputVolume = 0.42,
	RadioAmbientVolume = 0.65,
	VoiceNoiseRadius = 45,
	RadioNoiseRadius = 35,
	NoiseInterval = 0.2,
	VoiceActivity = {
		Threshold = 0.05,
		Release = 0.18,
		PollInterval = 1 / 30,
		Heartbeat = 0.2,
		Timeout = 0.75,
		TransmissionGrace = 0.5,
	},

	--- The player filter is shared by incoming and outgoing radio audio.
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
