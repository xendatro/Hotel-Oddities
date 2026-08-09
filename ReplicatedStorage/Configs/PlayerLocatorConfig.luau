--- Every tunable the player locator reads. Shared, because the cooldown is displayed by the client
--- and enforced by the server and the two must not be able to disagree about how long it is.

return {
	--- The order `Toggle` cycles through. `Label` is what the Mode text reads while it is selected;
	--- `Friends` decides who gets highlighted.
	Modes = {
		{ Id = "All", Label = "All Players", Friends = false },
		{ Id = "Friends", Label = "Friends Only", Friends = true },
	},

	--- Seconds between teleports. The server owns this number; the client only counts it down.
	Cooldown = 60,
	--- The TeleportCooldown label while one is running. Takes the whole seconds left.
	CooldownFormat = "Cooldown %d",

	--- How far behind the target the arriving player is placed, in studs. Far enough not to land
	--- inside them, close enough that they are the first thing seen.
	ArriveDistance = 4,

	Highlight = {
		FillColor = Color3.fromRGB(120, 235, 255),
		FillTransparency = 0.6,
		OutlineColor = Color3.fromRGB(236, 236, 240),
		OutlineTransparency = 0,
	},

	Marker = {
		--- The tappable area over a highlighted player, in studs. Roughly a character: wide enough
		--- to hit from across a room, tight enough not to swallow clicks meant for the floor.
		Size = Vector2.new(4.5, 6),
		--- Raises that area from the root part to the middle of the body.
		Offset = Vector3.new(0, 0.5, 0),
		--- Studs past which the marker stops drawing. The point of a locator is the player you
		--- cannot see, so this is deliberately most of the hotel.
		MaxDistance = 1000,
		ShowName = true,
		NameColor = Color3.fromRGB(236, 236, 240),
		NameSize = 22,
	},
}
