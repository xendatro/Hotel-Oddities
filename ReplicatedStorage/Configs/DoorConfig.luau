--- Tunables for the `DoorPart` swing. Client-only: doors are animated locally on every machine, so
--- nothing here is enforced by the server.

return {
	--- A `DoorPart` only swings when an ancestor carries EVERY one of these tags. Other systems tag
	--- doorways too, so both are required to single out the ones that should open on approach.
	DoorwayTags = { "Doorway", "RoomDoor" },

	--- How far the slab swings, in degrees. Past 90 so a doorway is fully clear to walk through.
	OpenAngle = 100,

	--- Studs from the middle of the slab at which a player pushes it open.
	OpenDistance = 9,
	--- Studs at which it falls shut again. Larger than `OpenDistance` so standing on the boundary
	--- does not flutter the door.
	CloseDistance = 14,
	--- Ignore players this far above or below the slab. Hotel floors stack, and a door should not
	--- answer to someone standing on top of it.
	MaxHeightDifference = 8,

	--- Seconds between proximity checks. The swing itself is stepped every frame; only the decision
	--- to open or shut is polled.
	PollInterval = 0.1,

	--- Swing spring. A ratio under 1 lets the door overshoot slightly and settle back, which reads as
	--- weight rather than a slide.
	Stiffness = 95,
	DampingRatio = 0.62,
	--- Seconds of simulation per integration step. Long frames are split into several so a hitch
	--- cannot fling the spring.
	MaxStep = 1 / 120,

	--- Below both of these, a shutting door is treated as closed and stops being stepped.
	SettleAngle = 0.35,
	SettleVelocity = 6,
	--- A door within this many degrees of shut is allowed to pick a new side. Above it, a player who
	--- crossed over mid-swing keeps the side the door is already committed to instead of having it
	--- sweep back through them.
	ResideAngle = 2,
}
