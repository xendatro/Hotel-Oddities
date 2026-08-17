--- Every tunable the active-effects HUD reads: the right-side panel that shows one tile per
--- effect currently running on the local player, with a drain sheet and a tenths countdown.
--- The UI is built in code from these values, matching how the inventory is styled.

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

	--- Mirrors HOLE_LIFETIME in ServerStorage.Services.HoleService -- that constant is local to the
	--- service, so keep the two in sync by hand if either changes.
	HoleLifetime = 30,

	--- Items that flash for FlashDuration when one is consumed. Timed items (Soda, Energy Drink,
	--- SpellBook) are absent on purpose: their entries are driven by their own signals instead, so
	--- the consumption tick never doubles up with the real duration tile.
	FlashItems = {
		Medkit = true,
		Bandage = true,
		Ball = true,
		Trap = true,
		Pathfinder = true,
	},

	--- rbxassetid icons per effect, generated art uploaded through Open Cloud. An empty string
	--- falls back to the item's name drawn as text.
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
