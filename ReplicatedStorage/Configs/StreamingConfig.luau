return {
	Enabled = false,

	ApproachLength = 96,

	CapLength = 64,

	BranchWarmDistance = 96,
	ReplicationLeadTime = 0.75,
	MaxPingLeadTime = 2,
	PredictionSpeedCap = 40,
	CorridorSelectionSlack = 4,
	UpdateInterval = 0.05,
	HysteresisTime = 2,
	PersistenceRetryInterval = 0.5,
	ReconcileInterval = 1,
	ReconcileGraceTime = 2,
	MissingReportCooldown = 0.25,
	MaxMissingReport = 128,

	GlobalAssetSize = 200,

	TeleportTimeout = 8,
	ClientReadyTimeout = 8,
	FailureMessage = "The area failed to load. Please try again.",

	IgnoreTag = "StreamingIgnore",
	ModelTag = "StreamingModel",
	ModelIdAttribute = "StreamingId",
}
