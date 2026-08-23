return {
	-- Mirroring. The only thing that moves it: it holds the keys you held, a beat after you held them.
	ReactionDelayMin = 0.3,
	ReactionDelayMax = 0.6,
	KeyDeadzone = 0.5,

	ReactionJitterMin = 0.05,
	ReactionJitterMax = 0.25,

	EmoteDelayMin = 9,
	EmoteDelayMax = 25,
	ModeEmoteDelayMin = 2.5,
	ModeEmoteDelayMax = 6,
	EmoteDuration = 3.5,
	SpinDelayMin = 3,
	SpinDelayMax = 7,
	SpinDuration = 2.4,

	HeadSnapDuration = 0.2,
	HeadUnlockTime = 0.4,
	RevealHoldTime = 0.75,
	RevealSoundVolume = 2,
	RevealReverbDecayTime = 3,
	RevealReverbWetLevel = 0,
	RevealReverbDryLevel = -3,

	RevealSubSpeed = 0.472,
	RevealSubVolume = 1.6,
	FloatHipRise = 3,
	FloatRiseTime = 0.35,
	FloatSettleTime = 0.3,
	FloatBobAmplitude = 0.5,
	FloatBobPeriod = 1.6,

	TurnRate = 6,
	InteractionTurnRate = 3.5,
	InteractionTurnTolerance = 3,
	AimDriftAngle = 2.5,
	AimDriftPeriod = 3.5,

	WallProbeDistance = 4,

	--- How close the Approach encounter walks before it stops and just looks at
	--- you. It only ever gets this close from behind: once you have it in view
	--- inside StrikeRange the encounter has already turned into a real chase.
	ApproachStopDistance = 5,

	--- The AlignOrientation that points the body somewhere its feet are not
	--- going. Torque is how hard it can turn, Responsiveness how sharply it
	--- settles -- higher is snappier, lower reads as a person turning.
	FacingTorque = 60000,
	FacingResponsiveness = 25,

	--- Withdraw gives ground until it has this much room, then holds.
	WithdrawGap = 30,
	--- Shadow trails you at this distance and never closes.
	ShadowGap = 22,

	BehindAngle = 115,
	BehindTurnDelayMin = 0.45,
	BehindTurnDelayMax = 1.3,
	ImmediateBehindTurnChance = 0.25,
}
