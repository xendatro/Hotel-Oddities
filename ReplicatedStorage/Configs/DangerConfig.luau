--- Tuning for the danger map: the field that decides how much of the hotel is trying to kill you,
--- and where.
---
--- The field is a fixed seed rather than a per-round roll, so a hotel's bad wings are a property of
--- that hotel and players can learn them. That also makes danger a pure function of position, which
--- is what lets the debug UI redraw a heatmap on the client without asking the server anything.
---
--- Every distance here is a fraction of the map's own extent rather than a number of studs, because
--- the alternative is re-tuning all of this by hand for every hotel. `DangerMapService` measures the
--- bounding box of the tagged `MazeFloor` parts at bake time and resolves these against it.

export type FieldSettings = {
	Seed: number,
	FeatureScale: number, -- studs across one blob of the field
	Octaves: number,
	Persistence: number,
	NoiseGain: number,
	Contrast: number,
	FloorHeight: number,
	FloorSeparation: number,
	StartPosition: Vector3,
	SafeRadius: number, -- studs from `Start` inside which danger is exactly zero
	RampLength: number, -- and how many studs it takes to climb from there to the full field
}

return {
	--- Pick this by looking at the heatmap, not by feel. It is authored content: the same number
	--- always produces the same hotel, so the job is to shop for one whose hot regions sit somewhere
	--- interesting relative to the doors, the vents and the objectives.
	Seed = 1337,

	--- Fraction of the map's longest horizontal side that one hot region spans. The temptation is to
	--- treat this as an aesthetic knob and it is not -- it decides whether the field is *avoidable*.
	--- Too large and the map has two bad places that players simply route around, and the whole
	--- system turns into a no-go zone they never visit. Around a sixth gives five or six regions,
	--- which is more than anybody can plan a path to avoid.
	FeatureScaleFraction = 1 / 6,

	--- Two is enough. One reads as too smooth to be a landscape; four is indistinguishable from two
	--- once the field has been contrasted, and costs twice the noise samples per baked point.
	Octaves = 2,
	Persistence = 0.5,

	--- Perlin's practical output is a good deal narrower than its nominal range -- samples cluster
	--- around the middle and the extremes almost never turn up. Without this the field would use
	--- about the middle two thirds of 0..1 and nowhere would ever be properly safe or properly bad.
	NoiseGain = 1.6,

	--- An S-curve applied after that, pushing values away from the middle. This is the difference
	--- between a field that gently undulates and one where there are Places You Do Not Go. 1 is off.
	Contrast = 1.8,

	--- Studs of height that separate one storey from the next, used only to work out which floor a
	--- point is on. Single-storey maps put everything on floor 0 and never notice this.
	FloorHeight = 50,

	--- How far apart consecutive floors are sampled along the noise's third axis. At 1 and above each
	--- storey is a completely fresh field, so learning the ground floor teaches you nothing about the
	--- third -- which is the point. Drop it to around 0.3 and floors start to resemble each other,
	--- if danger running in columns up through the building ever sounds better than danger being new
	--- on every storey.
	FloorSeparation = 1.25,

	--- The entrance. Nothing spawns inside `SafeRadius`, and the field climbs to full strength over
	--- `RampLength` past it.
	---
	--- The ramp is deliberately several times the safe radius. A short one makes the boundary a cliff
	--- -- one step past an invisible line and you are in full danger -- which reads as arbitrary and
	--- punishes a step nobody could see themselves taking. A long one gives a transitional band that
	--- is noticeably calmer than the deep hotel without being safe, and that band is the only thing
	--- that teaches a player the gradient exists at all.
	SafeRadiusFraction = 0.05,
	RampLengthFraction = 0.22,

	--- Studs between baked spawn candidates along the tagged floors. Tighter is a finer-grained
	--- choice of where something appears, at the cost of a longer bake and more memory. Ten is about
	--- half a corridor width, which is finer than anybody can perceive in the placement.
	PointSpacing = 10,

	--- Fraction of map extent past which an enemy is far enough from everybody to be culled.
	---
	--- This has to be much larger than anything spawns at, or a lone player generates a treadmill:
	--- things appear ahead of them, despawn behind them, and appear ahead again, so the hotel feels
	--- like it is following them around. The gap between the two is the band where an enemy simply
	--- persists and is nobody's problem, and that band wants to be wide.
	DespawnDistanceFraction = 0.45,
	DespawnGrace = 18, -- seconds it has to stay out there, unseen, before it actually goes

	--- How strongly a patrolling enemy prefers the more dangerous of two corners, against a
	--- straightness score that runs 0..1. Soft on purpose: this is a thumb on the scale, not a
	--- destination. Turn it up and patrols visibly beeline for the same few corridors and then pace
	--- them, which looks less like territory and more like a bug.
	PatrolDangerWeight = 0.6,
	--- Corners a patroller remembers, and what revisiting one costs it. Slightly more than the whole
	--- straightness range, so the corridor it just came out of loses to any other option -- which is
	--- the difference between something that patrols a hotel and something that paces one junction.
	PatrolMemory = 10,
	PatrolLoopPenalty = 1.2,

	--- Same idea for the two corridor enemies that plan a whole route up front.
	RouteDangerWeight = 0.5,

	--- What the director itself is allowed to do. Shared rather than server-only so the debug UI can
	--- put sliders on all of it without a second config to keep in step.
	Director = {
		--- Budget is purely linear in player count, with no base term, so each player brings their own
		--- share of the hotel's attention with them and a solo run is one player's worth of danger
		--- rather than a whole server's. The caps are a server-performance guard, not a design
		--- statement -- they only bind on a full server where everybody happens to be somewhere bad.
		PursuitPerPlayer = 4,
		PursuitCap = 14,
		PresencePerPlayer = 2.5,
		PresenceCap = 10,

		--- Seconds between spawn attempts for one player, from a dead-quiet spot to the worst of the
		--- map. Each player carries their own timer paced by the danger where *they* are standing, so
		--- somebody in a safe wing gets long gaps while somebody across the hotel is being hammered,
		--- and neither one is aware of the other.
		---
		--- The floor is the single most important fairness number here and it is deliberately
		--- generous. Every pursuer in the game deals instant death, so there is no attrition and no
		--- wounded state -- an encounter is escaped or fatal, nothing in between, which means pacing
		--- is the only pressure the game has and stacking two encounters is not twice as hard, it is
		--- a loss. Patrolling enemies also find players far more readily than the old spawn-area
		--- wandering did, so the same interval buys noticeably less quiet than it used to.
		PursuitQuietInterval = 75,
		PursuitBusyInterval = 30,
		PursuitFloorInterval = 25,

		PresenceQuietInterval = 35,
		PresenceBusyInterval = 12,
		PresenceFloorInterval = 10,

		--- Studs from every player that anything is allowed to appear, before each enemy's own
		--- detection range is taken into account. Something should have to *find* you: spawning a
		--- Chaser exactly on its own 60-stud detection range means it is hunting before it has
		--- finished appearing, so the real floor is the larger of this and its range times the margin.
		MinSpawnDistance = 70,
		DetectionMargin = 1.25,

		--- And the far side of the band. Beyond this a spawn is nobody's problem and would only be
		--- culled again a minute later, so the draw is not worth spending.
		MaxSpawnDistance = 320,

		--- Draws to take before giving up for this tick. A failure is a perfectly good outcome: it
		--- means every suitable spot was in somebody's sight, and the honest answer is to spawn
		--- nothing rather than to relax the rule that keeps spawns off-screen.
		PlacementAttempts = 24,

		--- How often the director looks at the world at all.
		TickInterval = 1,
		DespawnCheckInterval = 3,
	},
}
