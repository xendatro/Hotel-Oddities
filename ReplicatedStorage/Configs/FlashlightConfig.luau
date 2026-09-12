export type Cone = {
	Name: string,
	Angle: number,
	Range: number,
	Brightness: number,
	Shadows: boolean,
}

return {
	Attribute = "LightOn",

	Color = Color3.fromRGB(255, 244, 224),
	Master = 1,

	CameraOffset = Vector3.new(0.4, -0.3, -1),

	Cones = {
		{ Name = "Wash", Angle = 140, Range = 12, Brightness = 0.35, Shadows = false },
		{ Name = "Spill", Angle = 100, Range = 24, Brightness = 0.5, Shadows = false },
		{ Name = "Beam", Angle = 70, Range = 40, Brightness = 0.9, Shadows = false },
		{ Name = "Core", Angle = 45, Range = 60, Brightness = 2.2, Shadows = true },
	} :: { Cone },
}
