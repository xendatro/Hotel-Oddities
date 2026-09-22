return {
	Pages = {
		Items = { Label = "Items", Key = Enum.KeyCode.I },
		Kits = { Label = "Kits", Key = Enum.KeyCode.K },
		Shop = { Label = "Shop", Key = Enum.KeyCode.G },
		Inventory = { Label = "Inventory", Key = Enum.KeyCode.E },
	},

	Format = "%s [%s]",

	Label = {
		Name = "SideButtonLabel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.97),
		Size = UDim2.fromScale(0.94, 0.19),
		FontFace = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold),
		Color = Color3.fromRGB(64, 48, 32),
		MinTextSize = 7,
		MaxTextSize = 13,
		StrokeColor = Color3.fromRGB(247, 240, 222),
		StrokeThickness = 1.5,
		StrokeTransparency = 0.2,
		ZIndexOffset = 2,
	},
}
