--- Every tunable the first-person viewmodel reads.

return {
	--- Orientation reference for the virtual hand; each tool's Grip is applied against this, so
	--- tools keep their authored held rotation. Position placement is handled by Fit below.
	HandOffset = CFrame.new(1.05, -1.05, -1.6),

	--- Where a tool's bounding centre sits relative to the camera: Base for a point-sized item,
	--- plus PerStud in each axis per stud of the tool's bounding radius. Bigger tools sit further
	--- right, lower and deeper, so nothing swallows the middle of the screen.
	--- The whole rig is scaled down; a full-size prop a stud from the lens swallows the screen.
	Scale = 0.65,

	Fit = {
		Base = Vector3.new(0.5, -0.45, -1.0),
		PerStud = Vector3.new(0.28, 0.24, 0.5),
	},

	--- How far the rig lags behind camera rotation, and how fast it catches up. The lag is what
	--- sells "held in a hand" instead of "glued to the lens".
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

	--- Per-tool corrections. Anchor replaces the fitted Vector3 offset of the tool's bounding
	--- centre from the camera; Rotate is applied on top of the tool's held orientation, for tools
	--- whose authored grip reads badly this close to the lens.
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
