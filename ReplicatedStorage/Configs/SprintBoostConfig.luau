export type BoostVisual = {
	Label: string,
	Fill: Color3,
	FillAlt: Color3,
	FillEdge: Color3,
	Accent: Color3,
	Glow: Color3,
	BlendInTime: number,
	BlendOutTime: number,
	GradientRotation: number,
	GradientScroll: number,
	ShiftPeriod: number,
	SheenPeriod: number,
	SheenWidth: number,
	SheenStrength: number,
	StreakBands: number,
	StreakPeriod: number,
	StreakRotation: number,
	StreakStrength: number,
	GlowThickness: number,
	GlowTransparency: number,
	GlowPulse: number,
	GlowPulsePeriod: number,
	EdgeWidth: number,
	EdgePulse: number,
	PopScale: number,
	PopTime: number,
	Rings: number,
	RingDelay: number,
	RingTime: number,
	RingGrowth: number,
	RingThickness: number,
	FlashTime: number,
	FlashStrength: number,
	TimerHeight: number,
	LabelSize: number,
	LabelGap: number,
	LabelTracking: number,
	LabelFlicker: number,
	Chromatic: boolean,
}

return {
	--- Matches the sprint bar's own geometry so the overlay lines up with the track.
	TimerGap = 4,
	AuraInset = 3,
	AuraCorner = 7,

	Boosts = {
		Soda = {
			Label = "SUGAR RUSH",
			Fill = Color3.fromRGB(255, 196, 104),
			FillAlt = Color3.fromRGB(255, 214, 140),
			FillEdge = Color3.fromRGB(240, 128, 88),
			Accent = Color3.fromRGB(255, 236, 198),
			Glow = Color3.fromRGB(255, 158, 82),

			BlendInTime = 0.28,
			BlendOutTime = 0.6,

			GradientRotation = 0,
			GradientScroll = 0.06,
			ShiftPeriod = 2.4,

			SheenPeriod = 1.7,
			SheenWidth = 0.14,
			SheenStrength = 0.45,

			StreakBands = 0,
			StreakPeriod = 1,
			StreakRotation = 0,
			StreakStrength = 0,

			GlowThickness = 2,
			GlowTransparency = 0.62,
			GlowPulse = 0.18,
			GlowPulsePeriod = 1.6,

			EdgeWidth = 0,
			EdgePulse = 0,

			PopScale = 0.05,
			PopTime = 0.34,

			Rings = 1,
			RingDelay = 0,
			RingTime = 0.5,
			RingGrowth = 16,
			RingThickness = 2,

			FlashTime = 0.22,
			FlashStrength = 0.55,

			TimerHeight = 2,
			LabelSize = 11,
			LabelGap = 6,
			LabelTracking = 1,
			LabelFlicker = 0,
			Chromatic = false,
		},

		["Energy Drink"] = {
			Label = "OVERDRIVE",
			Fill = Color3.fromRGB(120, 245, 255),
			FillAlt = Color3.fromRGB(196, 138, 255),
			FillEdge = Color3.fromRGB(72, 132, 255),
			Accent = Color3.fromRGB(236, 252, 255),
			Glow = Color3.fromRGB(126, 216, 255),

			BlendInTime = 0.14,
			BlendOutTime = 0.5,

			GradientRotation = 12,
			GradientScroll = 0.55,
			ShiftPeriod = 0.9,

			SheenPeriod = 0.55,
			SheenWidth = 0.07,
			SheenStrength = 0.6,

			StreakBands = 4,
			StreakPeriod = 0.36,
			StreakRotation = 24,
			StreakStrength = 0.3,

			GlowThickness = 4,
			GlowTransparency = 0.34,
			GlowPulse = 0.34,
			GlowPulsePeriod = 0.42,

			EdgeWidth = 3,
			EdgePulse = 0.35,

			PopScale = 0.16,
			PopTime = 0.42,

			Rings = 3,
			RingDelay = 0.09,
			RingTime = 0.55,
			RingGrowth = 34,
			RingThickness = 3,

			FlashTime = 0.16,
			FlashStrength = 1,

			TimerHeight = 3,
			LabelSize = 15,
			LabelGap = 8,
			LabelTracking = 2,
			LabelFlicker = 0.28,
			Chromatic = true,
		},
	} :: { [string]: BoostVisual },
}
