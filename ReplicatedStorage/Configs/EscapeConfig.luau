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
		TopCount = 4,
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

		Layout = {
			TopMargin = 0.06,
			BottomMargin = 0.06,
			TitleWidth = 0.55,
			TitleGap = 0.05,
			TitleTextWidth = 0.8,
			TitleTextHeight = 0.42,
			RowWidth = 0.9,
			RowStretch = 1.25,
			HeadshotLeft = 0.045,
			HeadshotHeight = 0.66,
			NameGap = 0.025,
			TextHeight = 0.31,
			ScoreLeft = 0.76,
			ScoreRight = 0.955,
		},
	},
}
