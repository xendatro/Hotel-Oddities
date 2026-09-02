export type Framing = {
	Yaw: number,
	Pitch: number,
	Zoom: number,
	Padding: number,
	OffsetX: number,
	OffsetY: number,
}

return {
	FieldOfView = 40,

	Default = {
		Yaw = 20,
		Pitch = 5,
		Zoom = 1,
		Padding = 1.55,
		OffsetX = 0,
		OffsetY = 0,
	} :: Framing,

	Ambient = Color3.fromRGB(196, 192, 186),
	LightColor = Color3.fromRGB(255, 250, 240),
	LightDirection = Vector3.new(-0.4, -0.8, -0.45),

	Items = {
		Flashlight = { Yaw = -25 },
		Medkit = { Yaw = -70 },
		Pathfinder = { Yaw = 160 },
		Shovel = { Pitch = 8, Zoom = 1.15 },
		SpellBook = { Yaw = -70 },
		Trap = { Pitch = 12 },
	} :: { [string]: { [string]: number } },
}
