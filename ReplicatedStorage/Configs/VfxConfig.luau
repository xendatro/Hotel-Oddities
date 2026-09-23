return {
	Folder = "Effects",
	Remote = { Folder = "Vfx", Name = "Play" },
	HolderFolder = "LocalVfx",
	MaxDistance = 220,
	CleanupPadding = 0.25,

	Templates = {
		ChaosCrash = "ChaosCrash",
		VentDust = "VentDust",
		DwellerLanding = "DwellerLanding",
		PaintingBurst = "PaintingBurst",
		CrushDust = "CrushDust",
		CrushSeal = "CrushSeal",
		FlashlightDust = "FlashlightDust",
		StalkerWisp = "StalkerWisp",
	},

	Chaos = {
		WallProbe = 8,
	},

	Vent = {
		DustDuration = 0.9,
	},

	Crush = {
		CeilingSearch = 30,
		CeilingProbeAcross = 0.8,
		CeilingFallback = 12,
		CeilingInset = 0.4,
		SealAt = 0.97,
		MinimumLength = 2,
	},

	Flashlight = {
		Distance = 7,
	},

	Stalker = {
		SpottedAttribute = "PeekSpottedAt",
		WithdrawnAttribute = "PeekWithdrawnAt",
		EyeNames = { "LeftEye", "RightEye" },
		HeadName = "Head",
		GlowTemplate = { "IntroCutscene", "EyeGlow" },
		GlowScale = 0.55,
		GlowTowardCamera = 0.4,
		FlareAttack = 0.07,
		FlareSustain = 0.3,
		FlareDecay = 0.4,
		FlareGrowth = 0.8,
		FlareBrightness = 0.5,
		FlareEyeHeat = 0.55,
		HotEye = Color3.fromRGB(255, 170, 160),
		WithdrawFade = 0.12,
		MaxFlareTime = 4,
		WispLift = 0.35,
		MaxDistance = 160,
	},
}
