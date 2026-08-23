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

	FeatureScaleFraction = 1 / 2,

	Octaves = 2,
	Persistence = 0.5,

	NoiseGain = 1.6,

	Contrast = 1.8,

	FloorHeight = 50,

	FloorSeparation = 1.25,

	SafeRadiusFraction = 0.14,
	RampLengthFraction = 0.38,

	PointSpacing = 10,

	DespawnDistanceFraction = 0.45,
	DespawnGrace = 18,

	PatrolDangerWeight = 0.6,

	ProgrammaticVents = {
		MaxAlive = 5,
		InitialAlive = 5,
		InitialSpawnInterval = 1,
		SpawnInterval = 10,
		PlacementAttempts = 24,
		MinimumSpacing = 28,
		DespawnInterval = 5,
		--- Seconds a vent may exist before it is culled. It is only ever removed
		--- while unseen, so a watched vent outlives this until nobody is looking.
		--- CeilingVentService also derives its arm time from this.
		Lifetime = 180,
	},

	PatrolVisitMemory = 30,
	PatrolVisitPenalty = 0.9,

	PatrolMinTripFraction = 0.18,

	--- Same idea for the two corridor enemies that plan a whole route up front.
	RouteDangerWeight = 0.5,

	Director = {
		PursuitPerPlayer = 4,
		PursuitCap = 14,
		PresencePerPlayer = 2.5,
		PresenceCap = 10,

		PursuitQuietInterval = 75,
		PursuitBusyInterval = 30,
		PursuitFloorInterval = 25,

		PresenceQuietInterval = 35,
		PresenceBusyInterval = 12,
		PresenceFloorInterval = 10,

		MinSpawnDistance = 70,
		DetectionMargin = 1.25,

		MaxSpawnDistance = 320,

		PlacementAttempts = 24,

		--- How often the director looks at the world at all.
		TickInterval = 1,
		DespawnCheckInterval = 3,
	},
}
