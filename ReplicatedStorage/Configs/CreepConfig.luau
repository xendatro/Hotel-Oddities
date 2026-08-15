--- Shared Creep presentation tuning. The server reads `LightRange` for its discovery radius and
--- `ConnectedHallwayLightRange` for the short spill into hallways that meet its own, while
--- each client turns the thing itself and places its own backdrop from the rest.
return {
	LightRange = 80, -- studs used for discovery around the Creep
	ConnectedHallwayLightRange = 15, -- studs into each hallway joined to its own

	--- How fast it comes round to face a viewer, as the fraction of the angle left closed per second.
	--- Quick: what turns is the pair of glowing points, and a pair that lags a strafing player reads
	--- as two lights sliding along the corridor rather than as something watching them.
	TurnRate = 16,

	--- The black wall behind it. Its whole job is that the corridor past the Creep looks like it does
	--- not continue -- so it is laid *across* the hallway it is standing in, floor to ceiling and wall
	--- to wall, rather than turned to face the viewer. A billboard is right up until the player is off
	--- to one side, when it stops covering the corridor and starts being a black slab standing in it.
	BackdropDistance = 12, -- studs behind the Creep, down the hallway, away from the viewer
	--- Never nearer the viewer than this, whatever the corridor is doing. Below it the wall is close
	--- enough to the Creep to read as one thing with it, and it is dropped instead -- see
	--- `CreepRenderService` on the corridors too short to hold one.
	BackdropMinimumDistance = 5,
	--- Preferred inset from the end of the hallway. Corridors are authored butted together, so the
	--- last stretch of one is the opening of whatever crosses it. Short corridors relax this inset
	--- when needed to keep the wall inside its own ends.
	BackdropEndMargin = 10,
	--- How tall it is, floor upwards. Measured off the corridor rather than fixed, because the hotel is
	--- not one height: some halls are ceilinged and some are open to the night, and a wall tall enough
	--- for the tallest of them stands up above the walls of the rest, black against the sky, from the
	--- other end of the map. What is wanted is a wall exactly as tall as the corridor it is in.
	BackdropCeilingSearch = 60, -- studs above the floor it looks for a ceiling, or failing that a wall top
	BackdropHeightOverlap = 1.5, -- studs past whatever it found, so the top is not a visible seam
	--- Under this, the measurement is thrown away and the fallback used. No corridor in the hotel is
	--- shin high, so a measurement that says one is has found a skirting board or a step rather than
	--- the top of anything, and building the wall to it puts a black kerb across the hallway.
	BackdropMinimumHeight = 8,
	BackdropHeight = 24, -- fallback where there is nothing above it at all to measure against
	BackdropThickness = 1,

	--- Used only where the Creep is nowhere the corridor graph knows about -- spawned into a room by
	--- hand, most likely. It falls back to the old behaviour there: square on to the viewer, and wide
	--- enough to cover whatever it is standing in.
	BackdropFallbackSize = Vector3.new(100, 100, 1),
}
