--- Turning something towards something else, for the enemies whose whole tell is where they are
--- pointed. Pure: it answers with rotations and never writes one, so a caller can ease a model, a
--- part or nothing at all with the same two functions.

local Aim = {}

--- The rotation that puts a thing at `position` looking straight at `target`, upright. Its
--- LookVector, so a model whose front is its own LookVector is aimed by this alone.
function Aim.Toward(position: Vector3, target: Vector3): CFrame
	return CFrame.lookAt(position, target).Rotation
end

--- `rotation` moved part of the way to `goal`: `rate` is the fraction of the angle left it closes
--- per second, taken over `deltaTime` seconds.
---
--- Framerate independent by construction. Easing a fixed fraction per *frame* -- the usual way this
--- is written -- turns faster on a better machine, which is how one player watches a thing snap
--- round while another watches it drift.
function Aim.Ease(rotation: CFrame, goal: CFrame, rate: number, deltaTime: number): CFrame
	return rotation:Lerp(goal, 1 - math.exp(-rate * deltaTime))
end

return Aim
