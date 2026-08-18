--- Every tunable the sprint system reads: how fast sprinting is, how long stamina lasts, what the
--- camera does about it, and how the stamina bar is drawn. The bar is built in code from these
--- values rather than from a StarterGui asset, matching the inventory and the effects HUD.

return {
	--- Multiplies whatever walk speed the player already has, so a drink and a sprint stack instead
	--- of one replacing the other.
	SpeedMultiplier = 1.5,

	--- Running the bar all the way down locks sprinting out until it has filled completely again --
	--- there is no threshold to configure. Stopping before it empties costs nothing but the wait.
	Stamina = {
		--- Arbitrary units. Divided by DrainRate this is how many seconds of sprinting a full bar
		--- buys: 100 / 17 is a little under six seconds.
		Max = 100,
		DrainRate = 17,
		RegenRate = 13,
		--- Seconds of not sprinting before the bar starts filling again. Stops a tapped sprint key
		--- from being free.
		RegenDelay = 0.9,
	},

	Camera = {
		--- Degrees added to the camera's field of view at full sprint.
		FovBoost = 9,
		--- How quickly the sprint blends in and out, as an exponential rate per second. Higher is
		--- snappier; this drives the field of view and the extra camera motion together.
		BlendSpeed = 6,
	},

	Input = {
		--- Held down, not toggled. Left trigger is the gamepad's sprint.
		HoldKeys = {
			Enum.KeyCode.LeftShift,
			Enum.KeyCode.RightShift,
			Enum.KeyCode.ButtonL2,
		},
		--- Touch gets a toggle instead: holding a screen button while also steering is unpleasant.
		TouchButtonTitle = "SPRINT",
		--- Position of the touch button, from the bottom-right corner. Clear of Roblox's jump
		--- button, which sits closer to the corner.
		TouchButtonPosition = UDim2.new(1, -150, 1, -60),
		TouchButtonSize = UDim2.fromOffset(74, 74),
	},

	UI = {
		--- Bar geometry in pixels before scaling. It sits above the inventory hotbar, centred.
		Width = 260,
		Height = 10,
		CornerRadius = 5,
		--- Room around the track inside the group that fades. The outline draws outside the track's
		--- own border and a CanvasGroup clips to its bounds, so without this the outline is cut in
		--- half down its length.
		Padding = 3,
		--- Distance from the bottom of the screen. The hotbar is 64 tall at 12 from the edge.
		BottomMargin = 88,

		Colors = {
			Track = Color3.fromRGB(12, 12, 16),
			Stroke = Color3.fromRGB(72, 72, 82),
			--- The fill runs from Fill to FillEdge across its own length, so a full bar has a little
			--- depth to it rather than reading as one flat block.
			Fill = Color3.fromRGB(232, 232, 238),
			FillEdge = Color3.fromRGB(158, 176, 208),
			--- Taken over by these once the bar is running out, and again once it is spent.
			Low = Color3.fromRGB(226, 152, 92),
			Empty = Color3.fromRGB(214, 88, 88),
		},

		Transparency = {
			Track = 0.35,
			Stroke = 0.5,
		},

		--- Share of the bar below which it reads as low, and below which it reads as spent.
		LowThreshold = 0.32,
		EmptyThreshold = 0.02,

		--- The bar is only worth showing while it is not full. Once it fills it waits this long,
		--- then fades out over FadeOutTime; a fresh drain brings it back in FadeInTime.
		FullHoldTime = 0.5,
		FadeOutTime = 0.45,
		FadeInTime = 0.12,
		--- How quickly the drawn fill chases the real value, as an exponential rate per second.
		--- Keeps the regen from looking like it is stepping.
		FollowSpeed = 14,
		--- The same idea for colour. The state changes in steps -- white to amber at the low mark,
		--- everything to red on lockout and back again once it lifts -- and stepping the colour with
		--- it reads as a flicker.
		ColorFollowSpeed = 7,
		ExhaustBlendSpeed = 3.5,
		--- Seconds for one full breath of the pulse the bar does while it is spent, and how far that
		--- breath carries the empty track towards Empty. A spent bar has almost no fill left to
		--- colour, so the track itself has to carry the lockout.
		EmptyPulsePeriod = 0.7,
		EmptyTrackTint = 0.5,
	},
}
