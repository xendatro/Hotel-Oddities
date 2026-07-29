--- How a `Ghost` looks while it drifts.
---
--- Shared, unlike the rest of the enemy tuning, because the drift is rendered on every client
--- (`GhostRenderService`) rather than watched as it replicates. The server still owns where the
--- ghost actually is and where it is going next -- that lives in `EnemyConfigs.Ghost`.
---
--- `TurnTime` is the one value both halves read: the turn is part of the leg, so a client that
--- disagreed about it would render the ghost facing somewhere the server says it is not.
return {
	TurnTime = 0.3, -- seconds to come about onto a new heading, out of a trip lasting several

	-- The bob is cosmetic and lives only on clients, so it never shifts the position the server
	-- answers questions about.
	BobHeight = 0.5, -- studs it carries either side of its true position
	BobPeriod = 3.5, -- seconds per full rise and fall; slower than a person breathes
}
