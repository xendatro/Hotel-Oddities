return {
	-- Raising the input also raises any custom route fed by it. The radio output compensates for this.
	NormalVoiceVolume = 1.65,
	NoiseRadius = 45,
	NoiseInterval = 0.2,
	Activity = {
		Threshold = 0.05,
		Release = 0.18,
		PollInterval = 1 / 30,
		Heartbeat = 0.2,
		Timeout = 0.75,
	},
}
