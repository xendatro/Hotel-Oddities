return {
	HandOffset = CFrame.new(1.05, -1.05, -1.6),

	Scale = 0.65,

	Fit = {
		Base = Vector3.new(0.5, -0.45, -1.0),
		PerStud = Vector3.new(0.28, 0.24, 0.5),
	},

	SwayAmount = 0.6,
	SwaySpeed = 8,

	--- Walk bob applied to the rig while the character is moving.
	BobAmount = 0.03,
	BobSpeed = 10,

	--- The simple sleeve arm drawn from the lower-right screen edge to the tool.
	Arm = {
		Enabled = true,
		Size = Vector3.new(0.42, 0.42, 1.7),
		--- Where the shoulder end sits relative to the camera, just off the screen edge.
		Shoulder = CFrame.new(1.5, -1.6, 0.1),
	},

	Overrides = {
		-- Carried by its top handle bar, case hanging below the grip.
		Medkit = { AnchorAt = "Handle", Anchor = Vector3.new(0.8, -0.3, -1.7) },
		-- Authored lying flat in the hand; stood up it reads as a drink instead of a torpedo.
		Soda = { Rotate = CFrame.Angles(math.rad(-90), 0, 0) },
		-- Cover toward the camera instead of the page edge.
		SpellBook = { Rotate = CFrame.Angles(math.rad(-15), math.rad(-95), 0) },
		-- Angled a touch so the chevron screen has depth instead of sitting flat on the lens.
		Pathfinder = { Rotate = CFrame.Angles(0, math.rad(-25), 0) },
	},
}
