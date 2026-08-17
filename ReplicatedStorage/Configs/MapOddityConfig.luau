-- Rare, harmless oddities that affect one complete straight hallway run.
return {
	Enabled = true,

	RollInterval = 45,
	InitialDelay = 45,
	TriggerChance = 0.15,

	MinDuration = 45,
	MaxDuration = 120,
	MinimumPlayerDistance = 32,
	Effects = {
		Transparency = {},
		DoorsOpen = {
			OpeningSpeed = 0.75,
		},
	},

	HallwayTransparency = 0.02,
	HallwayHeightWindow = 24,
	HallwayBelowWindow = 4,
	SpatialPadding = 0.5,
	MinimumPartHallwayFraction = 0.5,
}
