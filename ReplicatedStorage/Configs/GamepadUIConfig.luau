return {
	BackKeys = {
		Enum.KeyCode.ButtonB,
	},
	BackWindow = 0.25,
	SelectDelay = 0.05,

	SkipAttribute = "GamepadSkip",
	DefaultAttribute = "GamepadDefault",
	CloseTag = "InterfaceCloseButton",

	Cursor = {
		GuiName = "GamepadCursor",
		DisplayOrder = 1000,
		Image = "rbxasset://textures/Cursors/KeyboardMouse/ArrowFarCursor.png",
		Size = 64,
		Speed = 0.9,
		Deadzone = 0.15,
		Curve = 1.6,
		PressKeys = {
			Enum.KeyCode.ButtonR2,
		},
		AlternateKeys = {
			Enum.KeyCode.ButtonL2,
		},
		Priority = Enum.ContextActionPriority.High.Value + 10,
	},

	KeyText = {
		[Enum.KeyCode.ButtonA] = "A",
		[Enum.KeyCode.ButtonB] = "B",
		[Enum.KeyCode.ButtonX] = "X",
		[Enum.KeyCode.ButtonY] = "Y",
		[Enum.KeyCode.ButtonL1] = "LB",
		[Enum.KeyCode.ButtonR1] = "RB",
		[Enum.KeyCode.ButtonL2] = "LT",
		[Enum.KeyCode.ButtonR2] = "RT",
		[Enum.KeyCode.ButtonL3] = "L3",
		[Enum.KeyCode.ButtonR3] = "R3",
		[Enum.KeyCode.DPadUp] = "▲",
		[Enum.KeyCode.DPadDown] = "▼",
		[Enum.KeyCode.DPadLeft] = "◀",
		[Enum.KeyCode.DPadRight] = "▶",
		[Enum.KeyCode.ButtonSelect] = "View",
		[Enum.KeyCode.ButtonStart] = "Menu",
	},
}
