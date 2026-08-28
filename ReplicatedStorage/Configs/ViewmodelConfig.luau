return {
	HandOffset = CFrame.new(1.05, -1.05, -1.6),

	Scale = 0.65,

	Fit = {
		Base = Vector3.new(0.5, -0.45, -1.0),
		PerStud = Vector3.new(0.28, 0.24, 0.5),
	},

	SwayAmount = 0.6,
	SwaySpeed = 8,

	BobAmount = 0.03,
	BobSpeed = 10,

	Arm = {
		Enabled = true,
		Size = Vector3.new(0.42, 0.42, 1.7),
		Shoulder = CFrame.new(1.5, -1.6, 0.1),
	},

	Overrides = {
		Camera = {
			AnchorAt = "Handle",
			Scale = 0.4,
			Anchor = Vector3.new(1, -0.95, -3),
			Rotate = CFrame.Angles(0, math.rad(-20), math.rad(55)),
		},
		Medkit = { AnchorAt = "Handle", Anchor = Vector3.new(0.8, -0.3, -1.7) },
		["Walkie Talkie"] = {
			AnchorAt = "Handle",
			Scale = 0.50,
			Anchor = Vector3.new(1.09, -0.61, -1.65),
			ArmAnchor = Vector3.new(1.33, -0.45, -2.40),
			Rotate = CFrame.Angles(math.rad(1), math.rad(-51), math.rad(15)),
			PoseSpeed = 9,
			Poses = {
				Talk = {
					Anchor = Vector3.new(0.45, -0.32, -0.85),
					ArmAnchor = Vector3.new(0.95, -0.9, -1.35),
					Rotate = CFrame.Angles(math.rad(-10), math.rad(-40), math.rad(20)),
				},
				Raised = {
					Anchor = Vector3.new(0, -0.236, -0.46),
					ArmAnchor = Vector3.new(0.35, -0.8, -0.65),
					Rotate = CFrame.Angles(math.rad(-3), math.rad(4), 0),
				},
			},
		},
		Soda = { Rotate = CFrame.Angles(math.rad(-90), 0, 0) },
		SpellBook = { Rotate = CFrame.Angles(math.rad(-15), math.rad(-95), 0) },
		Pathfinder = { Rotate = CFrame.Angles(0, math.rad(-25), 0) },
	},
}
