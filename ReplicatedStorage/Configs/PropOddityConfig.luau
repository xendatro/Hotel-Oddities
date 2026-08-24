return {
	Enabled = true,

	Effects = {
		LanternFall = {
			--- Tag the candidates are drawn from, narrowed to this model name so ceiling
			--- fixtures are left alone.
			Tag = "Floor1Light",
			ModelName = "HallwayLantern",

			--- How many lanterns are armed and watched at once, out of the whole map. 1-8.
			ArmedCount = 2,

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
			DebugHighlight = false,

			--- Debug: warn to the server log on every arm, approach, drop and repair. Turn off for release.
			DebugLog = true,
		},

		PaintingFall = {
			--- Tag the candidates are drawn from; every model carrying it qualifies, so no
			--- ModelName narrowing. 134 hallway frames.
			Tag = "PictureFrame",

			--- How many paintings are armed and watched at once, out of the whole map. 1-8.
			ArmedCount = 1,

			ApproachChance = 1,
			TriggerDistance = 25,
			ArmDistance = 45,
			SameFloorTolerance = 8,
			ApproachDot = 0.5,
			ApproachMinSpeed = 4,

			--- With only 134 frames on the map these bands have to be looser than the lanterns'
			--- or nothing qualifies.
			CandidateMinDistance = 55,
			CandidateMaxDistance = 220,
			CandidateSpacing = 60,
			CandidateSamples = 48,

			MinGroundTime = 45,
			FixClearDistance = 24,
			FixViewCone = 120,
			FixViewDistance = 160,
			PollInterval = 0.2,
			CollisionGroup = "FallenProp",

			--- Studs per second the painting is thrown off the wall toward the hallway centre,
			--- plus the upward part of that shove. 0-30 / 0-12.
			ShoveSpeed = 14,
			ShoveLift = 4,

			--- Random tumble given to the shove, in mass-scaled angular impulse. 0-20.
			ShoveSpin = 5,

			DebugHighlight = false,
			DebugLog = true,
		},

		PaintingDweller = {
			Tag = "PictureFrame",

			ArmedCount = 1,
			ApproachChance = 1,
			TriggerDistance = 22,
			ArmDistance = 45,
			SameFloorTolerance = 8,
			ApproachDot = 0.5,
			ApproachMinSpeed = 4,

			CandidateMinDistance = 55,
			CandidateMaxDistance = 220,
			CandidateSpacing = 60,
			CandidateSamples = 48,

			MinGroundTime = 45,
			FixClearDistance = 24,
			FixViewCone = 120,
			FixViewDistance = 160,
			PollInterval = 0.2,

			MinCanvasWidth = 6,
			HideDepth = 8,
			PopDepth = 7,
			RootDrop = 0.5,
			PopTime = 0.3,
			RetreatTime = 0.4,

			AttackReach = 7,
			AttackCooldown = 1.6,
			AttackHitTime = 0.38,

			ShakeRadius = 32,
			FlickerLights = 2,
			FlickerDuration = 1,

			ThrashAnimation = 92266255835557,
			AttackAnimation = 126599509413874,
			HoleImage = 75483437903741,

			DebugHighlight = true,
			DebugLog = true,
		},
	},
}
