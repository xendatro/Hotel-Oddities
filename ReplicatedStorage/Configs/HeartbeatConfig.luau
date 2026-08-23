return {
	EnemyId = "Blind",
	Template = "Heartbeat",

	--- Furthest out it is heard at all, matching the radius Blind hears a walking player from.
	Range = 45,
	--- At this distance and nearer it is at full volume and full rate.
	FullDistance = 8,

	Volume = {
		Far = 0.2,
		Near = 2.2,
	},

	--- Set while Blind is pursuing or attacking, which is the only thing that quickens the beat.
	PursuitAttribute = "Pursuing",

	--- Playback rate, not pitch: an AudioPitchShifter takes back out the pitch the rate adds,
	--- so the heart only beats faster. Distance does not touch this; only the pursuit does.
	Rate = {
		Resting = 0.82,
		Pursuit = 1.35,
	},

	FadeInSpeed = 3,
	FadeOutSpeed = 1.5,
	--- Deliberately slow: the beat should wind up and down rather than snap between paces.
	RateSpeed = 0.9,

	SilenceEpsilon = 0.005,
}
