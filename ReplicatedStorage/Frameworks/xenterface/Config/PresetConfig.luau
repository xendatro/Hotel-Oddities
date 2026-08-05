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

return PresetConfig