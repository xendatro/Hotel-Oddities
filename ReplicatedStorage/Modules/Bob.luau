--- The rise and fall to hang on top of something's true position, for anything that should look alive
--- while it stands still. Pure, and stateless past the phase its caller keeps: the offset at any
--- moment is a function of the clock, so nothing here has to be stepped, stopped or cleaned up.
---
--- It is cosmetic by construction. The offset is never written back into whatever the server is
--- answering questions about -- a caller adds it as it draws, which is what makes it safe to give
--- two clients different phases for the same model. Height and period are passed in rather than
--- configured here, since what reads as breathing on one thing reads as a hover on another; each
--- caller keeps its own numbers in its own config.

local TAU = math.pi * 2

local Bob = {}

--- A starting point on the cycle. Per thing per client, so no two in the same hall move in step --
--- a row of them rising and falling together reads as one animation rather than several things.
function Bob.NewPhase(): number
	return math.random() * TAU
end

--- Where `phase` sits at `clock` seconds: `height` studs either side of nothing, over `period`
--- seconds for a full rise and fall. Add it to a position; never store it in one.
function Bob.Offset(clock: number, phase: number, height: number, period: number): Vector3
	return Vector3.yAxis * math.sin(clock * TAU / period + phase) * height
end

return Bob
