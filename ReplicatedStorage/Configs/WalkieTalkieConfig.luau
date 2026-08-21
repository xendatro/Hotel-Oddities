return {
	--- Local sound from a held radio. Direct radio output is not distance limited.
	PhysicalRange = 30,
	AmbientRange = 30,
	AmbientPickupFalloff = 2,
	RadioAllowedTag = "RadioAllowed",
	DeathActiveGrace = 0.75,
	TransmissionGrace = 0.5,
	-- This keeps radio speech near its old level after normal voice was raised to 1.65.
	RadioOutputVolume = 0.32,
	RadioPhysicalVolume = 0,
	RadioAmbientVolume = 0.25,
	RadioNoiseRadius = 35,
	NoiseInterval = 0.2,

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
