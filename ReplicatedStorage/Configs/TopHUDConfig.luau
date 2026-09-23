export type Tier = {
	Name: string,
	Threshold: number,
	Fill: Color3,
	FillEdge: Color3,
	Glow: number,
	PulsePeriod: number,
}

return {
	Gui = "TopHud",
	ReferenceWidth = 960,
	ReferenceHeight = 1080,
	MinScale = 0.5,
	MaxScale = 1.3,

	Currencies = {
		Coins = {
			Attribute = "Coins",
			Flash = Color3.fromRGB(255, 214, 120),
		},
		Gems = {
			Attribute = "Gems",
			Flash = Color3.fromRGB(206, 160, 255),
		},
	},

	Roll = {
		Time = 0.32,
		FlashHold = 0.12,
		FlashFade = 0.6,
		PopScale = 1.22,
		PopTime = 0.4,
	},

	Danger = {
		Interval = 0.2,
		FollowSpeed = 4,
		ColorFollowSpeed = 5,
		GlowFollowSpeed = 3,
		Track = Color3.fromRGB(12, 12, 16),
		Stroke = Color3.fromRGB(72, 72, 82),
		GlowColor = Color3.fromRGB(214, 70, 70),
		GlowMinTransparency = 0.25,
		TrackTint = 0.35,
		StrokeTint = 0.6,
		Unknown = "—",

		Tiers = {
			{
				Name = "SAFE",
				Threshold = 0,
				Fill = Color3.fromRGB(232, 232, 238),
				FillEdge = Color3.fromRGB(158, 176, 208),
				Glow = 0,
				PulsePeriod = 2,
			},
			{
				Name = "UNEASY",
				Threshold = 0.2,
				Fill = Color3.fromRGB(236, 214, 150),
				FillEdge = Color3.fromRGB(214, 176, 104),
				Glow = 0,
				PulsePeriod = 2,
			},
			{
				Name = "TENSE",
				Threshold = 0.45,
				Fill = Color3.fromRGB(238, 170, 102),
				FillEdge = Color3.fromRGB(226, 128, 82),
				Glow = 0.25,
				PulsePeriod = 1.8,
			},
			{
				Name = "DIRE",
				Threshold = 0.65,
				Fill = Color3.fromRGB(226, 108, 96),
				FillEdge = Color3.fromRGB(196, 64, 64),
				Glow = 0.55,
				PulsePeriod = 1.2,
			},
			{
				Name = "DEADLY",
				Threshold = 0.82,
				Fill = Color3.fromRGB(214, 70, 70),
				FillEdge = Color3.fromRGB(150, 28, 36),
				Glow = 1,
				PulsePeriod = 0.8,
			},
		} :: { Tier },
	},
}
