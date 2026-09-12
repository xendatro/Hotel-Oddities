return {
	Tag = "MirrorRoom",
	OpaqueTag = "MirrorOpaque",
	TransparencyAttribute = "MirrorTransparency",
	ViewerAttribute = "MirrorViewer",

	-- studs of slack around the floor plan, so the reflection is already up before the doorway
	Padding = 8,
	-- studs below the floor still counted as inside, for jumps, ragdolls and stairs
	FloorTolerance = 8,

	-- seconds before retrying a clone that failed to build
	RetryDelay = 2,

	CastShadow = false,
	BendLocalLook = true,
	ReflectEnemies = true,

	StripClasses = {
		"BaseScript",
		"Sound",
		"AudioPlayer",
		"AudioEmitter",
		"ParticleEmitter",
		"Trail",
		"Beam",
		"Fire",
		"Smoke",
		"Sparkles",
		"Light",
		"BillboardGui",
		"SurfaceGui",
		"Highlight",
		"ClickDetector",
		"ProximityPrompt",
		"JointInstance",
		"WeldConstraint",
		"Constraint",
	},
}
