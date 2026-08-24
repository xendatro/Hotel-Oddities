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

	--- Discount a patrol route's edges get for the danger along them: an edge
	--- costs its length times (1 - this * danger), so at 0.7 the nastiest
	--- hallway is priced at 30% of its length and a patrol will take a detour
	--- up to about three times longer to walk it. Must stay under 1 or a
	--- maximally dangerous edge becomes free and the search stops being
	--- shortest-path at all.
	PathDangerWeight = 0.7,

	ProgrammaticVents = {
		MaxAlive = 8,
		InitialAlive = 8,
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

	PatrolMinTripFraction = 0.18,

	--- Width of the carpet strip patrols wander across, centered on the hallway;
	--- each leg draws a uniform side-offset within it. 0 walks the centerline.
	PatrolCarpetWidth = 6.75,

	--- How much danger pulls on the route the two corridor enemies plan up front,
	--- which they score greedily per step rather than through PathDangerWeight.
	RouteDangerWeight = 0.5,

	Director = {
		--- Every enemy the director keeps on the map, and how many of it there
		--- should be. The director tops each one back up whenever it is short.
		---
		--- Count      how many of it there should be.
		--- Lifetime   seconds one lives before the director retires it. Omit and
		---            it stays forever. The clock does not pause while somebody
		---            is watching, but an expired enemy will not vanish until
		---            nobody can see it, so a player staring one down keeps it.
		--- Respawn    seconds to wait before refilling that slot.
		--- Placement  how a spawn point is found. Omit for the scored floor
		---            search; "Peek" leans it around a corner at a player;
		---            "Hallway" puts it down a corridor a player has yet to turn
		---            into, measured in walking distance rather than a straight
		---            line through the walls.
		Residents = {
			Chaser = { Count = 2 },
			Blind = { Count = 2 },
			Mimic = { Count = 2 },
			--- Pulled from the pool for now; put Count back to 1 to bring them back.
			Sisters = { Count = 0 },

			Eye = { Count = 1, Lifetime = 60, Respawn = 20 },
			Creep = { Count = 2, Respawn = 12 },
		},

		--- Fallback for a resident entry that names no Respawn of its own.
		ResidentRespawnDelay = 25,

		--- Chaos and the Stalker are events rather than populations: one attempt
		--- each on its own clock, dropped if there is no room or no spot for it,
		--- and both leave under their own steam rather than being retired.
		ChaosInterval = 180,

		StalkerRotationInterval = 60,
		StalkerSpawnAttempts = 3,
		StalkerRetryDelay = 2,

		--- Backstop only. A Stalker retreats within seconds of being spotted, so
		--- this should never fire unless one has got itself stuck.
		StalkerLifetime = 120,

		--- Ranking of candidate spawn points. Line of sight is an absolute veto;
		--- these only order what survives it. Danger prefers the nastier parts of
		--- the map, PlayerProximity hugs the closest distance the enemy is
		--- allowed to spawn at, EnemySpacing pushes it away from enemies already
		--- placed.
		Placement = {
			DangerWeight = 1,
			PlayerProximityWeight = 0.8,
			EnemySpacingWeight = 0.6,

			--- Studs past its own minimum distance at which a point stops
			--- counting as near a player at all.
			PlayerFalloff = 120,

			--- Separation from the nearest other enemy that scores full marks.
			EnemySpacing = 90,
		},

		--- Walking distance, not straight-line, for the "Hallway" placement. Keep
		--- the minimum clear of the enemy's own straight-line minimum below, or
		--- the near edge of the band gets vetoed for being through a wall.
		HallwayMinWalk = 130,
		HallwayMaxWalk = 240,

		MinSpawnDistance = 70,
		DetectionMargin = 1.25,

		MaxSpawnDistance = 320,

		--- Candidate points scored per spawn attempt.
		PlacementAttempts = 48,

		--- How often the director looks at the world at all.
		TickInterval = 1,
		DespawnCheckInterval = 3,
	},
}
