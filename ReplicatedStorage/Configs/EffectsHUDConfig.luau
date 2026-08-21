return {
	--- Tile geometry, in pixels before scaling. Kept near the inventory's slot look.
	TileSize = 56,
	TilePadding = 6,
	CornerRadius = 8,
	--- Inset of the icon image inside its tile.
	IconInset = 6,
	--- Distance of the panel from the right edge of the screen.
	EdgeMargin = 16,

	Colors = {
		Text = Color3.fromRGB(236, 236, 240),
		TextStroke = Color3.fromRGB(10, 10, 12),
		--- Tint of the spent portion of the icon; the remaining portion stays full colour.
		Dim = Color3.fromRGB(70, 70, 75),
	},

	Transparency = {
		--- The spent portion of the icon also fades a little on top of being tinted.
		Dim = 0.35,
	},

	--- How long an instantaneous use (Medkit, Bandage, ...) stays on screen just to say "used one".
	FlashDuration = 0.5,

	HoleLifetime = 30,

	FlashItems = {
		Medkit = true,
		Bandage = true,
		Ball = true,
		Trap = true,
		Pathfinder = true,
	},

	Icons = {
		Medkit = "rbxassetid://105226575800706",
		Bandage = "rbxassetid://120230018864645",
		Ball = "rbxassetid://84955134779306",
		Trap = "rbxassetid://140353021452740",
		Soda = "rbxassetid://90872991269591",
		["Energy Drink"] = "rbxassetid://115046022954595",
		SpellBook = "rbxassetid://102847037397486",
		Shovel = "rbxassetid://101244121948310",
		Pathfinder = "rbxassetid://104851926131232",
	},
}
