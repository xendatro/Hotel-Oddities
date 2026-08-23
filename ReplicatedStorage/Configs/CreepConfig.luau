return {
	LightRange = 80,
	ConnectedHallwayLightRange = 15,
	DarkDistance = 60,

	TurnRate = 16,

	BackdropDistance = 12,
	BackdropMinimumDistance = 5,
	BackdropEndMargin = 10,
	BackdropCeilingSearch = 60,
	BackdropHeightOverlap = 1.5,
	BackdropMinimumHeight = 8,
	BackdropHeight = 24,
	BackdropThickness = 1,

	--- Eye colours a creep can spawn with. Neon, so they have to stay bright enough to read
	--- against the blacked-out hallway; the first is the original red.
	EyeColors = {
		Color3.fromRGB(190, 12, 12),
		Color3.fromRGB(255, 138, 0),
		Color3.fromRGB(226, 224, 96),
		Color3.fromRGB(80, 235, 130),
		Color3.fromRGB(150, 70, 255),
		Color3.fromRGB(235, 240, 255),
	},

	--- Studs kept between two pairs of eyes when they are scattered. 1-6.
	PairSpacing = 2.6,

	--- Attempts made to place each extra pair before it is given up on. 4-40.
	PairPlacementTries = 16,

	--- Picked by weight on every spawn, so a creep is not the same twice. Pairs is how many
	--- pairs of eyes it wears, Spread is how far they scatter from the spawn point in studs
	--- across the hallway, up, and along it. MixedColors gives every pair its own colour
	--- instead of one for the whole creep.
	Variants = {
		{
			Weight = 5,
			PairsMin = 1,
			PairsMax = 1,
		},
		{
			Weight = 3,
			PairsMin = 3,
			PairsMax = 4,
			SpreadAcross = 4.5,
			SpreadUp = 5,
			SpreadAlong = 2.5,
		},
		{
			Weight = 2,
			PairsMin = 6,
			PairsMax = 7,
			SpreadAcross = 5.5,
			SpreadUp = 7,
			SpreadAlong = 3.5,
			MixedColors = true,
		},
	},
}
