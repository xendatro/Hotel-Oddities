--- Client-side tuning for the stare an `Eye` gives you. Nothing here is read by the server: where it
--- is looking is drawn on each machine for that machine's own camera, and the damage it charges does
--- not depend on it. This is presentation for a thing whose whole presentation is where it points.
return {
	--- Studs within which it bothers to track you. Comfortably past the server's own `ObservationRange`
	--- of 150, so that turning is never the reason it stops costing you -- it is looking at you before
	--- you are close enough to be billed, which is the order those two want to happen in.
	TrackRange = 250,

	--- How quickly it comes around, as a fraction of the remaining angle closed per second. Slow
	--- enough to read as a thing turning rather than a thing snapping, fast enough that stepping out
	--- of a doorway does not give you a second of a blank white sphere: about a tenth of a second to
	--- cover most of a turn. A first sighting skips this entirely -- see `EyeRenderService`.
	TurnRate = 12,

	--- The idle float, through `Modules.Bob`. Small and slow on purpose: enough that it never quite
	--- reads as a prop somebody left in the corridor, not so much that it looks like it is coming for
	--- you. Shallower and a little quicker than the Ghost's, which is a body breathing rather than a
	--- thing hanging in the air.
	BobHeight = 0.3, -- studs it carries either side of where the server says it is
	BobPeriod = 2.6, -- seconds per full rise and fall
}
