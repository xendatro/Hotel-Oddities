return {
	DoorwayTags = { "Doorway", "RoomDoor" },

	--- How far the slab swings, in degrees. Past 90 so a doorway is fully clear to walk through.
	OpenAngle = 100,

	--- Studs from the middle of the slab at which a player pushes it open.
	OpenDistance = 6,
	CloseDistance = 10,
	MaxHeightDifference = 8,

	--- Carried by every live enemy model; see `NPC:Start`.
	EnemyTag = "Enemy",
	EnemyForceDistance = 5,
	EnemyReleaseDistance = 8,

	PollInterval = 0.1,

	Stiffness = 95,
	DampingRatio = 0.62,
	MaxStep = 1 / 120,

	--- Below both of these, a shutting door is treated as closed and stops being stepped.
	SettleAngle = 0.35,
	SettleVelocity = 6,
	ResideAngle = 2,
}
