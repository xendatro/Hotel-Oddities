export type FieldSettings = {
	Seed: number,
	FeatureScale: number,
	Octaves: number,
	Persistence: number,
	NoiseGain: number,
	Contrast: number,
	FloorHeight: number,
	FloorSeparation: number,
	StartPosition: Vector3,
	SafeRadius: number,
	RampLength: number,
}

return {
	Seed = 1337,

	FeatureScaleFraction = 1,

	Octaves = 2,
	Persistence = 0.5,

	NoiseGain = 1.6,

	Contrast = 1.8,

	FloorHeight = 50,

	FloorSeparation = 1.25,

	SafeRadiusFraction = 0.14,
	RampLengthFraction = 0.38,

	PointSpacing = 10,

	PathDangerWeight = 0.7,

	ProgrammaticVents = {
		MaxAlive = 8,
		InitialAlive = 8,
		InitialSpawnInterval = 1,
		SpawnInterval = 10,
		PlacementAttempts = 24,
		MinimumSpacing = 28,
		DespawnInterval = 5,
		Lifetime = 180,
	},

	PatrolMinTripFraction = 0.18,

	PatrolCarpetWidth = 6.75,

	Director = {
		Residents = {
			Chaser = { Count = 2 },
			Blind = { Count = 2 },
			Mimic = { Count = 2 },
			Sisters = { Count = 1 },

			Eye = { Count = 1, Lifetime = 60, Respawn = 20 },
			Creep = { Count = 2, Respawn = 12 },
		},

		ResidentRespawnDelay = 25,

		ChaosInterval = 120,

		StalkerRotationInterval = 60,
		StalkerSpawnAttempts = 3,
		StalkerRetryDelay = 2,

		StalkerLifetime = 120,

		Placement = {
			DangerWeight = 1,
			PlayerProximityWeight = 0.8,
			EnemySpacingWeight = 0.6,

			PlayerFalloff = 120,

			EnemySpacing = 90,
		},

		HallwayMinWalk = 130,
		HallwayMaxWalk = 240,

		MinSpawnDistance = 70,
		DetectionMargin = 1.25,

		MaxSpawnDistance = 320,

		PlacementAttempts = 48,

		TickInterval = 1,
		DespawnCheckInterval = 3,
	},
}
