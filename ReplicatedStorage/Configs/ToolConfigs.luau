--- Every tool in the game, and every number that used to be hardcoded inside its class.
---
--- This table is the registry: `ToolService` (server) and `ToolClientService` (client) each walk it
--- at boot, look for a matching module under their own `Classes/Tools` folder, and wire the tag.
--- Adding a tool means adding an entry here and dropping in one or two files -- there is no list of
--- tools to keep in sync anywhere else.
---
--- A tool may have a server half, a client half, or both. Whichever module exists gets loaded.

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
		--- How long the caster stays untargetable if the animation never reaches its end marker.
		--- Without this a missing marker would strand them rooted and invisible forever.
		MaxCastTime = 12,
		EffectDelay = 1, -- before the book's own particles appear
		ReaderDelay = 1.8, -- before the effect on the caster appears
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
		--- Ceiling the server puts on a reported hit, generous enough to allow for the thrower
		--- having moved during the throw but tight enough that a distant claim is refused.
		ServerRange = 80,
		FlightSpeed = 90,
		FlightSteps = 50,
	},

	Shovel = {
		Tag = "Shovel",
		Sound = "Shovel",
		RevealLimbs = true,
		DigDepth = 100, -- how far down to look for ground before refusing to dig
		HoleStartScale = 0.1,
		HoleEndScale = 0.792,
		HoleGrowTime = 2,
		--- How far the reported dig site may be from the player before the server refuses it.
		MaxDigDistance = 10,
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
		Visual = "Fire",
	},
}
