return {
	FadeInSpeed = 10,
	FadeOutSpeed = 13,
	FovReleaseSpeed = 2.5,

	CeilingDweller = {
		FieldOfView = 49,
	},

	MimicFovDelay = 0.25,

	ChaseShakes = {
		Chaos = {
			AllPlayers = true,
			Range = 50,
			FullIntensityDistance = 10,
			FalloffExponent = 2,
			Intensity = 0.95,
			Roughness = 28,
			MagnitudeScale = 5,
			PositionInfluence = Vector3.new(0.32, 0.32, 0.18),
			RotationInfluence = Vector3.new(1.2, 1.2, 0.55),
		},
		Chaser = {
			Range = 55,
			FullIntensityDistance = 12,
			Intensity = 0.35,
			Roughness = 16,
			MagnitudeScale = 5,
			PositionInfluence = Vector3.new(0.12, 0.12, 0.08),
			RotationInfluence = Vector3.new(0.45, 0.45, 0.1),
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
