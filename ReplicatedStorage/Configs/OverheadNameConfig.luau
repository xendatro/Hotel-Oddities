return {
	Tag = "OverheadName",
	UserIdAttribute = "OverheadNameUserId",

	VerifiedGlyph = 0xE000,

	StudSize = Vector2.new(6, 0.6),
	ExtentsOffset = Vector3.new(0, 1, 0),
	StudsOffsetWorldSpace = Vector3.new(0, 0.6, 0),
	TowardCamera = 2,
	MaxDistance = math.huge,
	AlwaysOnTop = false,

	Font = Enum.Font.Merriweather,
	MaxTextSize = 28,
	TextColor = Color3.fromRGB(240, 230, 206),
	StrokeColor = Color3.fromRGB(20, 15, 10),
	StrokeTransparency = 0.35,
}
