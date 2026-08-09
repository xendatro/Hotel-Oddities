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

	Pathfinder = {
		Tag = "Pathfinder",
		Cooldown = 0.35,
		--- Markers standing at once, and the size of a plain stack -- one number, because the two
		--- versions of the tool run out against it differently. The plain one spends a use per
		--- placement and empties before the cap is ever reached; the gamepass one spends nothing, so
		--- its 21st placement recycles the oldest marker instead.
		MaxInWorld = 20,
		--- Charges on one Pathfinder, and the denominator the on-screen counter reads against. These
		--- are NOT stack quantity: one Pathfinder is one device carrying this many markers, so it is
		--- granted like any other single item and only leaves the inventory once it is empty.
		Uses = 20,
		--- Shown beside the count while the tool is equipped.
		Caption = "MARKERS",
		--- Refuses to place within this many studs of an existing marker; the nearby one flares
		--- instead. Stops a double tap from burning two on the same square of carpet.
		MinSpacing = 8,
		--- How far below the player to look for a floor before refusing to place in midair.
		SnapDistance = 12,
		--- Newest marker is drawn in NewColor and the trail fades back toward OldColor behind it.
		--- Everything else about how one looks belongs to the `PathfinderMarker` prop in
		--- ReplicatedStorage.Props.Other, including its size and how far off its dot stays drawn.
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
		Visual = "Fire",
	},
}
