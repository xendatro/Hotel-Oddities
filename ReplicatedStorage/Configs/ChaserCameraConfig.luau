return {
	FadeInSpeed = 10,
	FadeOutSpeed = 13,
	FovReleaseSpeed = 2.5,

	CeilingDweller = {
		FieldOfView = 49,
	},

	MimicFovDelay = 0.25,

	MadGuest = {
		EnemyId = "Chaser",
		Range = 60,
		FullIntensityDistance = 8,
		FieldOfView = {
			Far = 6,
			Near = 16,
			Speed = 4,
		},
		Punch = {
			FieldOfView = 12,
			DecaySpeed = 5,
		},
		Sting = {
			Sound = "MadGuestSting",
			Shake = "Jolt",
			Cooldown = 8,
		},
		Stomp = {
			Range = 45,
			FullIntensityDistance = 6,
			Magnitude = 1.6,
			Roughness = 14,
			FadeOutTime = 0.25,
			PositionInfluence = Vector3.new(0.04, 0.12, 0),
			RotationInfluence = Vector3.new(1, 0.25, 0.45),
		},
	},

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
			Range = 60,
			FullIntensityDistance = 8,
			Intensity = 0.6,
			Roughness = 3.5,
			MagnitudeScale = 5,
			PositionInfluence = Vector3.new(0.02, 0.02, 0),
			RotationInfluence = Vector3.new(0.55, 0.4, 0.75),
		},
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
