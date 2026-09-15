return {
	HotbarSlots = 5,
	BackpackSlots = 25,

	ToggleKeys = {
		Enum.KeyCode.I,
		Enum.KeyCode.ButtonY,
	},
	HotbarKeys = {
		Enum.KeyCode.One,
		Enum.KeyCode.Two,
		Enum.KeyCode.Three,
		Enum.KeyCode.Four,
		Enum.KeyCode.Five,
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
		Stroke = Color3.fromRGB(72, 72, 82),
		Text = Color3.fromRGB(236, 236, 240),
		TextDim = Color3.fromRGB(150, 150, 160),
	},

	Transparency = {
		Slot = 0.15,
		SlotEmpty = 0.45,
		Dragging = 0.35,
	},

	PlaceholderIcon = "",

	Page = {
		Id = "Inventory",
		Gui = "InventoryGui",
		DragGui = "InventoryDragGui",
		DragGuiDisplayOrder = 100,
		GhostZIndex = 60,
		DropStrokeColor = Color3.fromRGB(96, 168, 96),
		SelectStrokeColor = Color3.fromRGB(70, 70, 70),
		DropStrokeThickness = 3,
		NoticeTime = 1.2,
		Ink = Color3.fromRGB(70, 70, 70),
		Bad = Color3.fromRGB(164, 62, 62),
		Text = {
			ToHotbar = "TO HOTBAR",
			ToBag = "TO BAG",
			HotbarFull = "HOTBAR FULL",
			BagFull = "BAG FULL",
			Empty = "NO ITEMS",
			EmptyDescription = "Everything you pick up in the hotel ends up here.",
		},
	},
}
