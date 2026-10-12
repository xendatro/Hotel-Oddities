return {
	StatName = "Escapes",

	OrderedStore = {
		Name = "Escapes",
		StudioPrefix = "Studio_",
	},

	Leaderboard = {
		Folder = "Lobby",
		Part = "LeaderboardPart",
		Face = Enum.NormalId.Back,
		Gui = "LeaderboardUI",
		Root = "Design",
		Title = "MOST ESCAPES",
		NameFormat = "%s (%s)",
		UnknownName = "Unknown",
		Headshot = "rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150",
		TopCount = 50,
		RefreshInterval = 60,
		AwardRefreshDelay = 5,
		PixelsPerStud = 128,
		LightInfluence = 0,
		Brightness = 1,

		Templates = {
			TitlePlate = "Layer_807",
			TitleText = "MOST_WINS",
			Row = "Layer_803",
			Headshot = "Layer_797",
			Text = "Scores",
		},

		Scroll = {
			BarThickness = 14,
			BarColor = Color3.fromRGB(70, 70, 70),
			BarTransparency = 0.2,
		},

		Layout = {
			TopMargin = 0.04,
			BottomMargin = 0.04,
			TitleWidth = 0.55,
			TitleGap = 0.025,
			TitleTextWidth = 0.8,
			TitleTextHeight = 0.42,
			RowWidth = 0.9,
			RowStretch = 1.05,
			RowGap = 0.012,
			HeadshotLeft = 0.045,
			HeadshotHeight = 0.66,
			NameGap = 0.025,
			TextHeight = 0.31,
			ScoreLeft = 0.76,
			ScoreRight = 0.955,
		},
	},
}
