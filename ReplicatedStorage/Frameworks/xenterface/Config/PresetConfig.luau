local PresetConfig = {}

PresetConfig.Example = {
	Active = "pos-c ap-0.5 t-0.2 linear bgc-new-0-0-0",
	Inactive = "i t-0.2 linear"
}

PresetConfig.Menu = {
	Active = "pos-c ap-0.5 t-0.2 back out",
	Inactive = "i t-0.3 linear"
}

PresetConfig.Hover = {
	Active = "size-a-0.01, t-0.1, linear",
	Inactive = "i t-0.1 linear"
}

PresetConfig.Hover2 = {
	Active = "p-a-0-(-10) t-0.1 linear",
	Inactive = "i t-0.1 linear"
}

PresetConfig.RectangleHover = {
	Active = "scale-1.15, quint, t-0.2",
	Inactive = "initial, quad, t-0.2"
}

PresetConfig.RectangleSelect = {
	Active = "scale-0.8, quint, t-0.2",
	Inactive = "initial, quad, t-0.2"
}

PresetConfig.ButtonHover = {
	Active = "scale-1.1, quint, t-0.2",
	Inactive = "initial, quad, t-0.2"
}

PresetConfig.FrameHover = {
	Active = "pos-sub-0-0-0.02-0, quint, t-0.1",
	Inactive = "initial, quad, t-0.1"
}

PresetConfig.FrameHoverScale = {
	Active = "scale-1.02, quint, t-0.2",
	Inactive = "initial, quad, t-0.2"
}

-- Hotel Oddities interface presets. Page uses Xenterface's standard Active/Inactive
-- sequences. Motion presets are read by InterfaceService because hover and press
-- are separate states from a tab's selected state.
-- Open rewinds the close: the page swings up from below, overshoots, then settles.
-- Close inhales (a small swell and tilt back) before it whips away, and it drives
-- Scale all the way to 0 so the page is already gone by the time Visible flips off.
-- Each step's delay is slightly shorter than its own tween so the next step takes
-- over while the previous one is still moving - no dead stops between steps.
PresetConfig.HotelPage = {
	Active = "v-t scale-0.55 rot-8 pos-0.5-0.585"
		.. " 0 scale-1.05 rot--2 pos-0.5-0.492 t-0.3 quint out"
		.. " 0.24 scale-1 rot-0 pos-c t-0.2 back out",
	Inactive = "scale-1.06 rot--3 pos-0.5-0.478 t-0.14 quad out"
		.. " 0.1 scale-0 rot-10 pos-0.5-0.6 t-0.28 cubic in"
		.. " 0.28 v-f",
	CloseTime = 0.38,
}

PresetConfig.HotelSideButton = {
	HoverScale = 1.08,
	PressScale = 0.9,
	HoverTilt = -2,
	HoverTime = 0.16,
	HoverStyle = Enum.EasingStyle.Quint,
	HoverDirection = Enum.EasingDirection.Out,
	PressTime = 0.08,
	PressStyle = Enum.EasingStyle.Quad,
	PressDirection = Enum.EasingDirection.Out,
	ReleaseTime = 0.2,
	ReleaseStyle = Enum.EasingStyle.Back,
	ReleaseDirection = Enum.EasingDirection.Out,
}

PresetConfig.HotelCloseButton = {
	HoverScale = 1.1,
	PressScale = 0.86,
	HoverTilt = 3,
	HoverTime = 0.16,
	HoverStyle = Enum.EasingStyle.Quint,
	HoverDirection = Enum.EasingDirection.Out,
	PressTime = 0.08,
	PressStyle = Enum.EasingStyle.Quad,
	PressDirection = Enum.EasingDirection.Out,
	ReleaseTime = 0.2,
	ReleaseStyle = Enum.EasingStyle.Back,
	ReleaseDirection = Enum.EasingDirection.Out,
}

PresetConfig.HotelEffects = {
	Time = 0.3,
	Blur = 18,
	FieldOfViewOffset = 8,
	MinimumFieldOfView = 45,
	Style = Enum.EasingStyle.Quint,
	Direction = Enum.EasingDirection.Out,
}

return PresetConfig
