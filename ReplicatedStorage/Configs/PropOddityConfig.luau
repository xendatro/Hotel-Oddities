return {
	Enabled = true,

	Effects = {
		LanternFall = {
			Tag = "Floor1Light",
			ModelName = "HallwayLantern",

			ArmedCount = 2,

			ApproachChance = 1,

			TriggerDistance = 25,

			ArmDistance = 45,

			SameFloorTolerance = 8,

			ApproachDot = 0.5,

			ApproachMinSpeed = 4,

			CandidateMinDistance = 55,
			CandidateMaxDistance = 160,

			CandidateSpacing = 90,

			CandidateSamples = 48,

			MinGroundTime = 45,

			FixClearDistance = 24,

			FixViewCone = 120,

			FixViewDistance = 160,

			PollInterval = 0.2,

			CollisionGroup = "FallenProp",

			DebugHighlight = false,

			DebugLog = true,
		},

		PaintingFall = {
			Tag = "PictureFrame",

			ArmedCount = 1,

			ApproachChance = 1,
			TriggerDistance = 25,
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
			CollisionGroup = "FallenProp",

			ShoveSpeed = 14,
			ShoveLift = 4,

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
