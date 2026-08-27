export type ToolConfig = {
	Tag: string,
	Sound: string?,
	Cooldown: number?,
	[string]: any,
}

return {
	Flashlight = {
		Tag = "Flashlight",
		Cooldown = 0.15,
	},

	Key = {
		Tag = "Key",
	},

	Bandage = {
		Tag = "Bandage",
		Sound = "Bandage",
		HealAmount = 10,
	},

	Medkit = {
		Tag = "Medkit",
		Sound = "Medkit",
		HealAmount = 45,
	},

	SpellBook = {
		Tag = "SpellBook",
		Sound = "SpellBook",
		RevealLimbs = true,
		MaxCastTime = 12,
		EffectDelay = 1,
		ReaderDelay = 1.8,
	},

	Trap = {
		Tag = "Trap",
		Sound = "PlaceTrap",
		CloseSound = "TrapClose",
		MaxInWorld = 10,
		DespawnDelay = 5,
	},

	Ball = {
		Tag = "Ball",
		Sound = "Ball",
		RevealLimbs = true,
		Range = 60,
		ServerRange = 80,
		FlightSpeed = 90,
		FlightSteps = 50,
	},

	Shovel = {
		Tag = "Shovel",
		Sound = "Shovel",
		RevealLimbs = true,
		DigDepth = 100,
		HoleStartScale = 0.1,
		HoleEndScale = 0.792,
		HoleGrowTime = 2,
		MaxDigDistance = 10,
	},

	Pathfinder = {
		Tag = "Pathfinder",
		Cooldown = 0.35,
		MaxInWorld = 20,
		Uses = 20,
		Caption = "MARKERS",
		MinSpacing = 8,
		SnapDistance = 12,
		NewColor = Color3.fromRGB(120, 235, 255),
		OldColor = Color3.fromRGB(64, 104, 142),
		PlaceTime = 0.18,
		RemoveTime = 0.15,
	},

	Soda = {
		Tag = "Soda",
		WalkSpeed = 22,
		Duration = 8,
		FovBoost = 8,
		UseDelay = 0.1,
	},

	["Energy Drink"] = {
		Tag = "Energy Drink",
		WalkSpeed = 28,
		Duration = 6,
		FovBoost = 14,
		UseDelay = 0.35,
		OpenSound = "OpenSound",
		DrinkSound = "DrinkSound",
	},

	Visor = {
		Tag = "Visor",
		FaceAccessory = "Accessory",
		FaceAttachment = CFrame.new(0, -0.2, -0.45),
		LightingSaturation = -0.18,
		LightingBrightness = 0.05,
		LightingContrast = 0.04,
		LightingTint = Color3.fromRGB(190, 220, 255),
		LightingInTime = 0.3,
		LightingOutTime = 0.45,
	},

	["Gravity Warper"] = {
		Tag = "Gravity Warper",
		Cooldown = 2,
		Duration = 30,
		AscendTime = 1.2,
		DescendTime = 1,
		MaxCeilingDistance = 60,
	},

	["Player Locator"] = {
		Tag = "Player Locator",
	},

	Camera = {
		Tag = "Camera",
		Sound = "PlaceTrap",
		Cooldown = 1,
	},

	["Walkie Talkie"] = {
		Tag = "Walkie Talkie",
	},

	["Big Head"] = {
		Tag = "Big Head",
		Cooldown = 1,
		OddityKind = "HeadSize",
	},

	["Big Character"] = {
		Tag = "Big Character",
		Cooldown = 1,
		OddityKind = "Size",
		OddityOverrides = {
			SizeOptions = { 1.1 },
		},
	},

	["Small Character"] = {
		Tag = "Small Character",
		Cooldown = 1,
		OddityKind = "Size",
		OddityOverrides = {
			SizeOptions = { 0.9 },
		},
	},

	Transparency = {
		Tag = "Transparency",
		Cooldown = 1,
		OddityKind = "Transparency",
	},

	["Random Oddity"] = {
		Tag = "Random Oddity",
		Cooldown = 1,
		OddityChoices = {
			{ Kind = "HeadSize" },
			{ Kind = "Size", Settings = { SizeOptions = { 1.1 } } },
			{ Kind = "Size", Settings = { SizeOptions = { 0.9 } } },
			{ Kind = "Transparency" },
		},
	},
}
