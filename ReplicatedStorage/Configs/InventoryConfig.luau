return {
	HotbarSlots = 9,
	BackpackSlots = 27,
	SingleCopy = {
		Camcorder = true,
		["Walkie Talkie"] = true,
	},

	ToggleKey = Enum.KeyCode.Backquote,
	HotbarKeys = {
		Enum.KeyCode.One,
		Enum.KeyCode.Two,
		Enum.KeyCode.Three,
		Enum.KeyCode.Four,
		Enum.KeyCode.Five,
		Enum.KeyCode.Six,
		Enum.KeyCode.Seven,
		Enum.KeyCode.Eight,
		Enum.KeyCode.Nine,
	},

	DragThreshold = 8,
	TouchDragThreshold = 16,

	SlotSize = 64,
	SlotPadding = 6,
	CornerRadius = 8,

	Colors = {
		Slot = Color3.fromRGB(28, 28, 32),
		SlotEmpty = Color3.fromRGB(20, 20, 24),
		SlotEquipped = Color3.fromRGB(72, 92, 128),
		SlotDisabled = Color3.fromRGB(52, 34, 34),
		SlotDropTarget = Color3.fromRGB(58, 78, 58),
		Panel = Color3.fromRGB(18, 18, 22),
		Stroke = Color3.fromRGB(72, 72, 82),
		Text = Color3.fromRGB(236, 236, 240),
		TextDim = Color3.fromRGB(150, 150, 160),
	},

	Transparency = {
		Slot = 0.15,
		SlotEmpty = 0.45,
		Panel = 0.1,
		Dragging = 0.35,
	},

	PlaceholderIcon = "",
}
