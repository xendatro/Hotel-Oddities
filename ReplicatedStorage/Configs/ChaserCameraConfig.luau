--- Client-only tuning for the Chaser's proximity shake. Distances are in studs and angles are in degrees.
return {
	EffectRange = 55,
	FullIntensityDistance = 12,
	FadeInSpeed = 10,
	FadeOutSpeed = 13,
	PositionAmplitude = 0.06,
	RotationAmplitude = 0.8,
	Frequency = 8.5,

	-- The Ceiling Dweller is meant to unsettle without taking over the camera like a Chaser.
	CeilingDweller = {
		FieldOfView = 13,
		PositionAmplitude = 0.03,
		RotationAmplitude = 0.4,
	},

	-- One-shot camera cues sent while a vent opens and the Dweller drops.
	CeilingDwellerDrop = {
		OpeningFieldOfView = 9,
		FallStartFieldOfView = 12,
		FallEndFieldOfView = 24,
		ScreamFieldOfView = 36,
		ScreamShake = 0.08,
		ScreamRotation = 1.4,
		ScreamDuration = 2,
	},
}
