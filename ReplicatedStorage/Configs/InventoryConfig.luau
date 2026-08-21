return {
	--- Slots along the bottom of the screen, each bound to a number key.
	HotbarSlots = 9,
	--- Extra slots reachable only through the backpack panel. Total capacity is Hotbar + Backpack.
	BackpackSlots = 27,

	--- Opens and closes the backpack panel.
	ToggleKey = Enum.KeyCode.Backquote,
	--- Equips the hotbar slot at the matching index. Must be at least `HotbarSlots` long.
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

	--- Slot geometry, in pixels before scaling.
	SlotSize = 64,
	SlotPadding = 6,
	CornerRadius = 8,

	Colors = {
		Slot = Color3.fromRGB(28, 28, 32),
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
		Panel = 0.1,
		Dragging = 0.35,
	},

	--- Shown until per-tool icons exist. A tool with a TextureId uses that instead.
	PlaceholderIcon = "",
}
