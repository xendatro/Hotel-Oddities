return {
	Permission = Enum.CaptureGalleryPermission.ReadAndUpload,

	Video = {
		MaxDuration = 30,
		Duration = 20,
		StopGrace = 0.35,
		ReadyTimeout = 12,
		HideToolFor = 0.15,
	},

	Screenshot = {
		Timeout = 8,
	},

	Gallery = {
		PageName = "Gallery",
		GuiName = "GalleryGui",
		Root = "Design",
		RefreshCooldown = 4,
		MaxItems = 120,
		ThisUniverseOnly = true,
	},

	Prompt = {
		Hold = 0.4,
		FadeTime = 0.28,
		SaveText = "KEEP",
		DiscardText = "BURN",
		Height = UDim2.fromScale(0.16, 0.16),
		Gap = 8,
		SaveColor = Color3.fromRGB(94, 132, 86),
		DiscardColor = Color3.fromRGB(140, 62, 52),
		TextColor = Color3.fromRGB(238, 231, 214),
		Transparency = 0.1,
	},

	Overlay = {
		Font = Enum.Font.Code,
		Color = Color3.fromRGB(255, 232, 178),
		StrokeColor = Color3.fromRGB(24, 12, 6),
		StrokeThickness = 1.4,
		Transparency = 0.08,
		TextScale = 0.062,
		Padding = 0.035,
		DateFormat = "MM/DD/YY",
		TimeFormat = "hh:mm A",
		RecordText = "REC",
		RecordColor = Color3.fromRGB(255, 86, 72),
		BlinkTime = 0.6,
	},

	Text = {
		NoCaptures = "NOTHING DEVELOPED YET",
		NeedPermission = "ALLOW CAPTURE ACCESS TO KEEP YOUR REEL",
		Denied = "CAPTURES STAY LOCAL UNTIL YOU ALLOW ACCESS",
		Saved = "Saved to your gallery",
		Discarded = "Burned",
		SaveFailed = "Could not save that one",
		Unsupported = "Recording is not available on this device",
		AlreadyRecording = "Already rolling",
		NoPass = "The camcorder is not available yet",
		Recording = "Recording...",
	},
}
