return {
	Permission = Enum.CaptureGalleryPermission.ReadAndUpload,

	RequireGamepass = false,

	Video = {
		MaxDuration = 30,
		Duration = 20,
		StopGrace = 0.35,
		ReadyTimeout = 12,
		HideToolFor = 0.15,
		Hud = {
			GuiName = "CamcorderRecording",
			StopKey = Enum.KeyCode.X,
			StopText = "STOP  [X]",
			StoppingText = "STOPPING...",
		},
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
		SaveText = "KEEP",
		DiscardText = "BURN",
	},

	Overlay = {
		DateFormat = "MM/DD/YY",
		TimeFormat = "hh:mm A",
		BlinkTime = 0.6,
	},

	Text = {
		NoCaptures = "NOTHING DEVELOPED YET",
		NeedPermission = "ALLOW CAPTURE ACCESS TO KEEP YOUR REEL",
		Access = "ALLOW DEVICE CAPTURES",
		Accessing = "CHECKING ACCESS...",
		Denied = "CAPTURES STAY LOCAL UNTIL YOU ALLOW ACCESS",
		Saved = "Saved to your gallery",
		Discarded = "Burned",
		Deleted = "Removed from this reel",
		SaveFailed = "Could not save that one",
		Unsupported = "Recording is not available on this device",
		NoSpace = "Not enough free space on this device to record",
		NoDeviceSupport = "This device cannot record video",
		CaptureFailed = "That one could not be saved to your gallery",
		AlreadyRecording = "Already rolling",
		NoPass = "The camcorder is not available yet",
		Recording = "Recording...",
	},
}
