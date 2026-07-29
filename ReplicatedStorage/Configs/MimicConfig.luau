--- How a `Mimic` moves while it is pretending to be a player.
---
--- Shared, unlike the rest of the enemy tuning, because the motion itself runs on the stalked
--- player's own client (`MimicService`). The server still owns every decision about when the act
--- starts and ends -- that lives in `EnemyConfigs.Mimic`.
---
--- Everything here is expressed as keys, because that is all a player is. A humanoid walks at exactly
--- its `WalkSpeed` or stands still, and its animation is scaled by how fast it is going: anything in
--- between makes the legs crawl while the body glides, which is the fastest way for something to stop
--- reading as a person.
return {
	-- Mirroring. The only thing that moves it: it holds the keys you held, a beat after you held them.
	ReactionDelayMin = 0.3, -- seconds behind the player its copied input plays back
	ReactionDelayMax = 0.6,
	KeyDeadzone = 0.5, -- fraction of walk speed a component must reach to count as a key held

	-- The imperfection. A person copying you is not a recording of you: every key change costs them a
	-- fresh scrap of reaction time, so they start late, stop late -- that overshoot is most of what
	-- sells it -- and miss anything you tapped faster than they could answer. Rolled per change and
	-- per key, so the two hands are never quite in step either.
	ReactionJitterMin = 0.05,
	ReactionJitterMax = 0.25,

	-- Idling. Players standing around wave, point, dance. Spaced far enough apart to read as somebody
	-- amusing themselves rather than a looping prop, and dropped the instant it takes a step.
	EmoteDelayMin = 9,
	EmoteDelayMax = 25,

	-- Aim. First person, so it faces where it is looking and strafes without turning, exactly as a
	-- player does -- it never rotates to follow its own feet.
	TurnRate = 10, -- how quickly it swings onto you, per second
	AimDriftAngle = 2.5, -- degrees of wander around you; nobody holds a crosshair perfectly still
	AimDriftPeriod = 3.5,

	WallProbeDistance = 4,
}
