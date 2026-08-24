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
		StunDuration = 5,
		MaxInWorld = 10,
		DespawnDelay = 5,
	},

	Ball = {
		Tag = "Ball",
		Sound = "Ball",
		RevealLimbs = true,
		StunDuration = 3,
		--- How far the aiming raycast reaches, in studs.
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
		--- How far the reported dig site may be from the player before the server refuses it.
		MaxDigDistance = 10,
	},

	Pathfinder = {
		Tag = "Pathfinder",
		Cooldown = 0.35,
		MaxInWorld = 20,
		Uses = 20,
		--- Shown beside the count while the tool is equipped.
		Caption = "MARKERS",
		MinSpacing = 8,
		--- How far below the player to look for a floor before refusing to place in midair.
		SnapDistance = 12,
		NewColor = Color3.fromRGB(120, 235, 255),
		OldColor = Color3.fromRGB(64, 104, 142),
		PlaceTime = 0.18,
		RemoveTime = 0.15,
	},

	Soda = {
		Tag = "Soda",
		--- A clear escape boost without quite matching the faster chase enemies.
		WalkSpeed = 22,
		Duration = 8,
		FovBoost = 8,
		UseDelay = 0.1,
	},

	["Energy Drink"] = {
		Tag = "Energy Drink",
		--- Shorter and much faster than Soda: the emergency overdrive option.
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
		--- Local pose of the visor's FaceFrontAttachment.
		FaceAttachment = CFrame.new(0, -0.2, -0.45),
		LightingSaturation = -0.18,
		LightingBrightness = 0.05,
		LightingContrast = 0.04,
		LightingTint = Color3.fromRGB(190, 220, 255),
		LightingInTime = 0.3,
		LightingOutTime = 0.45,
	},

	["Player Locator"] = {
		Tag = "Player Locator",
	},

	["Walkie Talkie"] = {
		Tag = "Walkie Talkie",
	},
}
