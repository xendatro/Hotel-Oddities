return {
	FadeInSpeed = 10,
	FadeOutSpeed = 13,
	FovReleaseSpeed = 2.5,

	CeilingDweller = {
		FieldOfView = 49,
	},

	MimicFovDelay = 0.25,

	ChaseShakes = {
		-- The plain hunter is the full takeover: heavy, everything moving.
		Chaser = {
			Range = 55,
			FullIntensityDistance = 12,
			Intensity = 0.8,
			Roughness = 20,
			MagnitudeScale = 5,
			PositionInfluence = Vector3.new(0.25, 0.25, 0.25),
			RotationInfluence = Vector3.new(1, 1, 1),
		},
		-- The Dweller's chase carries the vent-jolt's character: sharp and angry at full proximity.
		CeilingDweller = {
			Range = 55,
			FullIntensityDistance = 12,
			Intensity = 0.64,
			Roughness = 32,
			MagnitudeScale = 5,
			PositionInfluence = Vector3.new(0.35, 0.35, 0.15),
			RotationInfluence = Vector3.new(1, 1, 0.5),
		},
		Mimic = {
			Range = 55,
			FullIntensityDistance = 12,
			Intensity = 0.25,
			Roughness = 32,
			MagnitudeScale = 5,
			PositionInfluence = Vector3.new(0.2, 0.2, 0.1),
			RotationInfluence = Vector3.new(0.5, 0.5, 0.25),
		},
	},
}
