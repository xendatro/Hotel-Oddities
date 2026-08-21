--- One part of a stand-in. Built at the origin, in studs, and framed as a whole.
export type StandinPart = {
	Size: Vector3,
	Offset: Vector3?,
	Color: Color3?,
	Material: Enum.Material?,
	Shape: Enum.PartType?,
}

export type Headshot = {
	Focus: string?,
	Yaw: number?,
	Pitch: number?,
	Zoom: number?,
	Offset: Vector3?,
	Transparency: number?,
	WearFriendAvatar: boolean?,
	Standin: { StandinPart }?,
}

export type Entry = {
	Id: string,
	Name: string,
	Model: string,
	Description: string,
	Headshot: Headshot?,
}

return {
	EntriesPerPage = 8,

	TemplateFolder = "Enemies",

	StartProgress = 0,

	Locked = {
		Name = "UNDISCOVERED",
		CardName = "???",
		CardTextColor = Color3.fromRGB(202, 202, 202),
		Description = "You have not met this one yet.",
		ShowSilhouette = true,
		Tint = Color3.fromRGB(0, 0, 0),
		CardTint = Color3.fromRGB(108, 104, 118),
	},

	Discovery = {
		NamedAbove = 0,

		HiddenColor = Color3.fromRGB(64, 60, 72),

		NewColor = Color3.fromRGB(255, 236, 150),

		BlockRatio = 0.55,

		Reveal = {
			AfterDeathDelay = 1,
			DeathScreenTimeout = 20,

			OpenDelay = 0.8,
			WordInterval = 0.19,

			ChargeTime = 0.16,
			ChargeColor = Color3.fromRGB(255, 255, 255),

			SettleTime = 0.85,
			FlashFraction = 0.18,

			SettleDelay = 0.4,

			MaxDuration = 4,
		},
	},

	Empty = {
		Name = "INDEX",
		Description = "Select an entry.",
	},

	HideUndiscovered = false,

	Pagination = {
		Enabled = Color3.fromRGB(255, 255, 255),
		Disabled = Color3.fromRGB(150, 148, 155),
	},

	Animation = {
		Card = {
			HoverScale = 1.08,
			HoverLift = 0.05,
			HoverTilt = 2.5,

			PressScale = 0.95,
			PressTilt = 0,

			SelectedScale = 1.04,
			SelectedLift = 0.02,
			SelectedTilt = -1.5,

			HoverTime = 0.18,
			PressTime = 0.07,
			SettleTime = 0.26,

			Style = Enum.EasingStyle.Back,
			Direction = Enum.EasingDirection.Out,
			PressStyle = Enum.EasingStyle.Quad,
			PressDirection = Enum.EasingDirection.Out,
		},

		--- The page arrows and the close button, which are chrome rather than content and so move less.
		Button = {
			HoverScale = 1.15,
			PressScale = 0.9,
			DisabledScale = 0.92,

			HoverTime = 0.14,
			PressTime = 0.06,
			SettleTime = 0.2,

			Style = Enum.EasingStyle.Back,
			Direction = Enum.EasingDirection.Out,
		},

		--- Cards arriving on a page, dealt out rather than appearing all at once.
		Page = {
			EnterScale = 0.86,
			EnterDrop = 0.06,
			EnterTime = 0.34,
			Stagger = 0.035,
			ReplayOnOpen = true,
		},

		--- The info panel swapping from one entry to the next.
		Info = {
			FadeTime = 0.22,
			Rise = 0.02,
		},
	},

	--- Defaults for every headshot camera; an entry overrides what it needs in its own `Headshot`.
	Headshot = {
		FieldOfView = 40,
		Padding = 1.7,
		Yaw = 0,
		Pitch = 6,
		Zoom = 1,
		Tint = Color3.fromRGB(255, 255, 255),
	},

	Entries = {
		{
			Id = "Chaser",
			Name = "Chaser",
			Model = "Chaser",
			Description = "Something that used to work here. It still walks the halls it was hired to keep.",
		},
		{
			Id = "CeilingDweller",
			Name = "Ceiling Dweller",
			Model = "Ceiling Dweller",
			Description = "It lives above the tiles and comes down wherever the vents let it.",
		},
		{
			Id = "Blind",
			Name = "Blind",
			Model = "Blind",
			Description = "Eyeless, and listening. The hotel is as quiet as it is because of this one.",
		},
		{
			Id = "WeepingAngel",
			Name = "Weeping Angel",
			Model = "Weeping Angel",
			Description = "Stone, every time anyone checks. Nobody has ever watched one take a step.",
			Headshot = { Zoom = 0.82 },
		},
		{
			Id = "Mimic",
			Name = "Mimic",
			Model = "Mimic",
			Description = "It wears a guest's face badly. Watch it long enough and the seams show.",
			Headshot = { WearFriendAvatar = true },
		},
		{
			Id = "Stalker",
			Name = "Stalker",
			Model = "Stalker",
			Description = "It keeps station behind you and never closes the gap, right up until it does.",
		},
		{
			Id = "Sisters",
			Name = "The Sisters",
			-- One rig. The pair is two copies of it, and a headshot only has room for the one.
			Model = "Sister",
			Description = "Two of them, walking abreast and unhurried. They have all the time there is.",
		},
		{
			Id = "Chaos",
			Name = "Chaos",
			Model = "Chaos",
			Description = "It comes down the corridor at speed. The hotel warns you first, in red.",
			Headshot = {
				Standin = {
					{
						Size = Vector3.new(5, 5, 5),
						Color = Color3.fromRGB(255, 60, 20),
						Material = Enum.Material.Neon,
					},
				},
			},
		},
		{
			Id = "Watcher",
			Name = "Watcher",
			Model = "Watcher",
			Description = "It waits at the far ends of corridors, leaning out just far enough to be caught.",
		},
		{
			Id = "Ghost",
			Name = "Ghost",
			Model = "Ghost",
			Description = "A guest who never checked out. It drifts the floors and wants nothing from anyone.",
			Headshot = { WearFriendAvatar = true, Transparency = 0.5 },
		},
		{
			Id = "Creep",
			Name = "Creep",
			Model = "Creep",
			Description = "The lights go out around it. That is usually the whole of what you get.",
			Headshot = {
				Pitch = 0,
				Standin = {
					{
						Size = Vector3.new(0.55, 0.55, 0.55),
						Offset = Vector3.new(-1, 0, 0),
						Color = Color3.fromRGB(255, 0, 4),
						Material = Enum.Material.Neon,
					},
					{
						Size = Vector3.new(0.55, 0.55, 0.55),
						Offset = Vector3.new(1, 0, 0),
						Color = Color3.fromRGB(255, 0, 4),
						Material = Enum.Material.Neon,
					},
				},
			},
		},
		{
			Id = "Eye",
			Name = "Eye",
			Model = "Eye",
			Description = "It hangs in the dark and holds the room's attention. Staring back is expensive.",
			Headshot = { Focus = "Eyeball", Pitch = 4 },
		},
	} :: { Entry },
}
