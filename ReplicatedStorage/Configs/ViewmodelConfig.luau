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
		["Ball"] = {
			Scale = 0.65,
			Anchor = Vector3.new(0.81, -0.60, -1.28),
			ArmAnchor = Vector3.new(0.89, -0.58, -1.62),
			Rotate = CFrame.Angles(math.rad(-0), math.rad(0), math.rad(0)),
		},
		
		["Bandage"] = {
			Scale = 0.65,
			Anchor = Vector3.new(0.87, -0.69, -1.26),
			ArmAnchor = Vector3.new(0.89, -0.57, -1.26),
			Rotate = CFrame.Angles(math.rad(-8), math.rad(10), math.rad(-1)),
		},
		
		["Camcorder"] = {
			Scale = 0.65,
			Anchor = Vector3.new(0.76, -0.61, -1.33),
			ArmAnchor = Vector3.new(0.68, -0.61, -1.33),
			Rotate = CFrame.Angles(math.rad(90), math.rad(0), math.rad(90)),
		},
		
		
		Camera = {
			AnchorAt = "Handle",
			Scale = 0.4,
			Anchor = Vector3.new(1, -0.95, -3),
			Rotate = CFrame.Angles(0, math.rad(-20), math.rad(55)),
		},
		
		
		["Energy Drink"] = {
			Scale = 0.65,
			Anchor = Vector3.new(0.90, -0.62, -1.17),
			ArmAnchor = Vector3.new(0.94, -0.62, -1.35),
			Rotate = CFrame.Angles(math.rad(9), math.rad(0), math.rad(0)),
		},
		
		["Medkit"] = {
			AnchorAt = "Handle",
			Scale = 0.65,
			Anchor = Vector3.new(1.40, -0.78, -1.70),
			ArmAnchor = Vector3.new(1.31, -0.49, -2.07),
			Rotate = CFrame.Angles(math.rad(9), math.rad(0), math.rad(0)),
		},
		
		
		["Walkie Talkie"] = {
			AnchorAt = "Handle",
			Scale = 0.84,
			Anchor = Vector3.new(1.09, -0.44, -1.65),
			ArmAnchor = Vector3.new(1.21, -0.45, -2.40),
			Rotate = CFrame.Angles(math.rad(0), math.rad(-48), math.rad(15)),
			PoseSpeed = 9,
			Poses = {
				Talk = {
					AnchorOffset = Vector3.new(-0.41, 0.19, 0.35),
					ArmAnchorOffset = Vector3.new(-0.93, 0.55, -0.01),
					RotateOffset = CFrame.Angles(math.rad(5), math.rad(9), math.rad(8)),
				},
				Raised = {
					ArmAnchorOffset = Vector3.new(0.34, -0.62, -0.22),
					Framing = {
						Part = "Screen",
						Element = "Main",
						Coverage = 0.52,
					},
				},
			},
		},
		
		["Soda"] = {
			Scale = 0.65,
			Anchor = Vector3.new(1.01, -0.77, -1.39),
			ArmAnchor = Vector3.new(1.10, -0.60, -1.77),
			Rotate = CFrame.Angles(math.rad(93), math.rad(9), math.rad(2)),
		},
		
		SpellBook = { Rotate = CFrame.Angles(math.rad(-15), math.rad(-95), 0) },
		Pathfinder = { Rotate = CFrame.Angles(0, math.rad(-25), 0) },
	},
}
