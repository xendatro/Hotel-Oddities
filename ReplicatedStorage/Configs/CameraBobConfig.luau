--- Client-only first-person walking motion. Distances are in studs and angles are in degrees.
return {
	VerticalDistance = 0.045,
	HorizontalDistance = 0.025,
	RollAngle = 0.12,
	StepsPerSecond = 1.8,
	ReferenceWalkSpeed = 16,
	FadeSpeed = 10,

	--- How much the motion grows with speed. 1 scales the distances above in direct proportion to
	--- how fast the player is actually moving against ReferenceWalkSpeed, so a sprint shakes harder
	--- than a walk; 0 gives one fixed size at every speed. The clamps stop a crawl from flattening
	--- the motion entirely and a speed drink from making it unreadable.
	AmplitudeSpeedInfluence = 0.85,
	MinAmplitudeScale = 0.6,
	MaxAmplitudeScale = 2,
}
