--- Everything the drawer system reads: what counts as a drawer, how far it slides, how it is asked
--- to open, and how the prompt under the cursor is drawn.
---
--- The slide itself is client-side on every machine, like the doors. Only the open/shut boolean is
--- the server's, so two players looking at the same desk agree about it.

return {
	--- Carried by the drawer MODEL, not its parts.
	Tag = "Drawer",
	--- Where the open/shut state lives, written by the server on the model and read by everyone.
	Attribute = "DrawerOpen",

	--- Studs the drawer travels along its outward axis when opened.
	OpenDistance = 1,

	--- Which of the model pivot's own axes points out of the drawer's face. Only used when the
	--- handle cannot be found: the authored drawers all face the pivot's -Z, and a handle sitting on
	--- that face is a better answer than a constant, so it is preferred when one is there.
	OutwardAxis = Vector3.new(0, 0, -1),
	--- A part whose name contains this is taken for the drawer's handle, and the face it sits on for
	--- the face the drawer pulls out of.
	HandleKeyword = "handle",
	--- How far off centre the handle has to sit before its face is believed, in studs.
	HandleThreshold = 0.25,

	--- Slide spring. Damped just short of critical, so the drawer arrives with a little weight
	--- rather than gliding to a stop.
	Stiffness = 190,
	DampingRatio = 0.85,
	--- Seconds of simulation per integration step; long frames are split so a hitch cannot fling it.
	MaxStep = 1 / 120,
	--- Below both of these a settling drawer is snapped home and stops being stepped.
	SettleDistance = 0.002,
	SettleVelocity = 0.05,

	Targeting = {
		--- Studs from the camera within which a drawer can be looked at. The server allows a little
		--- more than this before it refuses a toggle.
		Reach = 10,
		ServerReach = 16,
		--- Invisible, walk-through parts -- region markers and the like -- are stepped over rather
		--- than treated as something blocking the view. This many of them, then the ray gives up.
		MaxPassthrough = 4,
	},

	Input = {
		Keys = {
			Enum.KeyCode.E,
			--- Right trigger on a gamepad.
			Enum.KeyCode.ButtonR2,
		},
		--- What the badge reads. Console gets the trigger's short name rather than a glyph, which no
		--- font here has.
		KeyboardLabel = "E",
		GamepadLabel = "RT",
		--- Touch has no cursor to rest on a drawer, so it gets a button instead of a prompt. It is
		--- only bound while a drawer is actually being looked at.
		TouchAction = "DrawerToggle",
		TouchButtonPosition = UDim2.new(1, -150, 1, -150),
		TouchButtonSize = UDim2.fromOffset(74, 74),
	},

	Highlight = {
		FillColor = Color3.fromRGB(255, 255, 255),
		OutlineColor = Color3.fromRGB(236, 240, 248),
		FillTransparency = 0.93,
		OutlineTransparency = 0.15,
		--- Occluded rather than always-on-top: a drawer behind a wall should not glow through it.
		DepthMode = Enum.HighlightDepthMode.Occluded,
	},

	Sound = {
		Enabled = true,
		OpenTemplate = "DrawerOpen",
		CloseTemplate = "DrawerClose",
		PlaybackSpeed = 1.6,
		Group = "SFX",
	},

	UI = {
		--- Name of the prompt built under the Cursor ScreenGui at edit time.
		Container = "Interact",
		--- Pixels below the middle of the screen, where the cursor dot sits.
		TopMargin = 14,
		--- Room around the pill inside the group that fades. The pill's outline draws outside its own
		--- border and a CanvasGroup clips to its bounds, so without this the outline is cut in half.
		Padding = 4,
		--- The pill is measured from its parts rather than from the words inside it, so it is exactly as
		--- wide as it needs to be and never changes shape as Open becomes Close. Only swapping between
		--- the keyboard badge and the wider console one resizes it, which happens on a device change
		--- and nothing else.
		PillHeight = 34,
		PillPaddingLeft = 7,
		PillPaddingRight = 7,
		--- Between the badge and the word.
		KeyGap = 8,
		--- Room set aside for the word. Wide enough for the longest of them with a little air, and
		--- fixed so the two never draw at different widths.
		TextWidth = 42,

		--- The key badge is a square for a single-character key, and only widens for the ones that need
		--- two. Left to size itself it came out an awkward oblong for both.
		KeySize = 24,
		KeyWideSize = 38,
		--- The prompt slides up into place over this many pixels as it fades in.
		Rise = 8,
		--- And starts a touch small, so it grows into place rather than appearing at full size.
		EnterScale = 0.92,

		FadeInTime = 0.1,
		FadeOutTime = 0.16,

		--- A press flashes the key badge: it shrinks by this much and brightens to Press, then eases
		--- back at this rate per second.
		PressScale = 0.12,
		PressDecay = 6,

		Colors = {
			Panel = Color3.fromRGB(18, 18, 22),
			Stroke = Color3.fromRGB(72, 72, 82),
			Key = Color3.fromRGB(38, 38, 44),
			KeyPressed = Color3.fromRGB(158, 176, 208),
			Text = Color3.fromRGB(236, 236, 240),
		},

		--- Words on the prompt, picked by what the drawer would do next.
		OpenText = "Open",
		CloseText = "Close",
	},
}
