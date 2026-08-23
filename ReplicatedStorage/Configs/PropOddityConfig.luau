return {
	Enabled = true,

	Effects = {
		LanternFall = {
			--- Model name of the wall lanterns that can drop. Ceiling fixtures are left alone.
			ModelName = "HallwayLantern",

			--- How many lanterns are armed and watched at once, out of the whole map. 1-8.
			ArmedCount = 3,

			--- Chance a qualifying approach drops the lantern. Rarity comes from ArmedCount being
			--- tiny against the whole map, so this stays at 1; lower it only to make drops rarer
			--- still on top of that. 0-1.
			ApproachChance = 1,

			--- Approaches are measured to the hallway centre point beside the lantern, not the
			--- lantern itself. Studs from that point at which an approach counts. 10-40.
			TriggerDistance = 25,

			--- Studs the player must be beyond before that lantern arms for them. Must sit
			--- comfortably above TriggerDistance. 30-90.
			ArmDistance = 45,

			--- Studs of height difference between that centre point and the player's feet past
			--- which they count as being on another floor. 4-16.
			SameFloorTolerance = 8,

			--- Dot of travel direction against direction to that centre point; 0.5 is a 60 degree
			--- cone. -1 to 1.
			ApproachDot = 0.5,

			--- Studs per second the player must be moving to count as approaching. 0-8.
			ApproachMinSpeed = 4,

			--- Band a fresh candidate is picked in, in studs from the nearest player. Keep the
			--- minimum above ArmDistance so a new candidate is never already inside the trigger.
			CandidateMinDistance = 55,
			CandidateMaxDistance = 160,

			--- Studs a new candidate must keep from every other armed or already-downed lantern,
			--- so the three armed ones never cluster. 0-200.
			CandidateSpacing = 90,

			--- Random lanterns sampled per re-arm attempt before giving up for that tick. 8-128.
			CandidateSamples = 48,

			--- Seconds a lantern stays on the floor before it is allowed to fix itself. 10-180.
			MinGroundTime = 45,

			--- Nobody may be within this many studs when it fixes itself. 10-60.
			FixClearDistance = 24,

			--- Cone, in degrees, counted as looking at the lantern while it waits to be fixed. 60-180.
			FixViewCone = 120,

			--- Studs past which a player is too far to be looking at it at all. 40-300.
			FixViewDistance = 160,

			--- Seconds between approach and repair polls. 0.1-0.5.
			PollInterval = 0.2,

			--- Physics group the fallen parts sit in; players and enemies pass through it.
			CollisionGroup = "FallenProp",

			--- Debug: outline the armed lanterns through walls so they can be found. Turn off for release.
			DebugHighlight = true,

			--- Debug: warn to the server log on every arm, approach, drop and repair. Turn off for release.
			DebugLog = true,
		},
	},
}
