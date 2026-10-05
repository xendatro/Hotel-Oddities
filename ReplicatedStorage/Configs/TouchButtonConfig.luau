return {
	Gui = "TouchButtons",
	DisplayOrder = 13,

	Size = 0.15,
	MinPixels = 48,
	MaxPixels = 110,
	CornerRadius = UDim.new(0.22, 0),
	StrokeThickness = 1.5,

	Font = Enum.Font.GothamMedium,
	MinTextSize = 8,
	MaxTextSize = 16,
	TextPadding = 0.12,

	Slots = {
		Sprint = Vector2.new(-0.37, -0.14),
		Crouch = Vector2.new(-0.41, -0.33),
		WalkieTalk = Vector2.new(-0.58, -0.16),
		WalkieRaise = Vector2.new(-0.62, -0.35),
		WalkiePower = Vector2.new(-0.48, -0.52),
	},

	Colors = {
		Background = Color3.fromRGB(12, 12, 16),
		Stroke = Color3.fromRGB(72, 72, 82),
		Text = Color3.fromRGB(232, 232, 238),
		ActiveBackground = Color3.fromRGB(158, 176, 208),
		ActiveStroke = Color3.fromRGB(232, 232, 238),
		ActiveText = Color3.fromRGB(12, 12, 16),
	},

	Transparency = {
		Background = 0.35,
		Stroke = 0.5,
	},
}
