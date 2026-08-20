--- Tunables shared by the server's hallway streamer and its small client-side status display.

return {
	Enabled = true,

	-- Physical chunk cuts around junctions. The server still treats a chosen straight corridor as
	-- one sightline and makes all of its chunks persistent together.
	ApproachLength = 96,

	-- How far into a crossing corridor stays loaded for a junction the player can see but is not
	-- close to. A junction is a hole in the corridor wall, so the corridor behind it has to cap the
	-- view no matter how far down the sightline it sits.
	CapLength = 64,

	-- Start making every corridor at an upcoming junction persistent before the player can see
	-- around the corner. Speed and round-trip ping add to this base distance.
	BranchWarmDistance = 96,
	ReplicationLeadTime = 0.75,
	MaxPingLeadTime = 2,
	PredictionSpeedCap = 40,
	CorridorSelectionSlack = 4,
	UpdateInterval = 0.05,
	HysteresisTime = 2,

	-- An asset wider than this cannot belong to a single chunk, so it is always replicated instead
	-- of vanishing with whichever chunk happened to be nearest its centre.
	GlobalAssetSize = 200,

	-- Teleports use both Roblox's stream request and a client acknowledgement for the persistent
	-- chunk models. A timeout leaves the character where it was.
	TeleportTimeout = 8,
	ClientReadyTimeout = 8,
	FailureMessage = "The area failed to load. Please try again.",

	IgnoreTag = "StreamingIgnore",
	ModelTag = "StreamingModel",
}
