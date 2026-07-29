--- The maths of moving like a person, for the `Mimic`. Kept apart from both halves of that enemy
--- because it is pure: every function here turns numbers into numbers, which is what makes the
--- movement tunable in `MimicConfig` rather than buried in a state.
---
--- It works in keys rather than velocities. A player holds W, or A, or both, and their humanoid
--- answers at exactly its walk speed; they never travel at a third of it. Reproducing the keys gets
--- the movement, the animation and the timing right together, where reproducing a velocity gets a
--- body that slides along with its legs crawling underneath it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MimicConfig = require(ReplicatedStorage.Configs.MimicConfig)
local MotionTrail = require(ReplicatedStorage.Classes.MotionTrail)

local TAU = math.pi * 2
local UP = Vector3.yAxis

--- One key the mimic is holding, and the change it has not gotten around to yet.
export type Key = { Held: number, Pending: number, At: number }

local MimicMotion = {}

local function flatten(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function press(component: number, deadzone: number): number
	if component > deadzone then return 1 end
	if component < -deadzone then return -1 end
	return 0
end

--- The keys a player was holding at `sample`, in their own frame: forward is 1 when they were walking
--- the way they faced and -1 when they were backing up, right is 1 when they were strafing to their
--- own right.
function MimicMotion.Keys(sample: MotionTrail.Sample, walkSpeed: number): (number, number)
	local look = flatten(sample.Look)
	local move = flatten(sample.Move)
	if look.Magnitude < 1e-3 or move.Magnitude < 1e-3 then return 0, 0 end

	look = look.Unit
	local deadzone = walkSpeed * MimicConfig.KeyDeadzone
	return press(move:Dot(look), deadzone), press(move:Dot(look:Cross(UP)), deadzone)
end

--- The same keys as the mimic should hold them, facing the player who pressed them.
---
--- Forward carries straight over: walk at it and it walks at you, back off and it backs off. Sideways
--- flips, because the two of them are facing each other -- pressing the same key would send it the
--- opposite way across the room, where flipping it puts it in tandem, sliding the way you slid a beat
--- after you did.
function MimicMotion.MirrorKeys(forwardKey: number, rightKey: number): (number, number)
	return forwardKey, -rightKey
end

--- The world direction a mimic facing `forward` travels while holding those keys. Unit length, or
--- zero when it is holding nothing: full walk speed or standing, never in between.
function MimicMotion.Direction(forward: Vector3, forwardKey: number, rightKey: number): Vector3
	local direction = forward * forwardKey + forward:Cross(UP) * rightKey
	return if direction.Magnitude > 1e-3 then direction.Unit else Vector3.zero
end

function MimicMotion.NewKey(): Key
	return { Held = 0, Pending = 0, At = 0 }
end

--- Moves `key` toward `desired` the way a hand does rather than the way a wire does, and returns what
--- is actually being held now.
---
--- Every change costs a fresh scrap of reaction time. Starting late is expected; stopping late is the
--- overshoot a person makes when they are copying rather than deciding, and it is most of what
--- separates the two. Anything tapped faster than the reaction it earns never gets pressed at all --
--- they simply missed it, which nobody watching would find suspicious in the slightest.
function MimicMotion.HoldKey(key: Key, desired: number, clock: number): number
	if desired ~= key.Pending then
		key.Pending = desired
		key.At = clock
			+ MimicConfig.ReactionJitterMin
			+ math.random() * (MimicConfig.ReactionJitterMax - MimicConfig.ReactionJitterMin)
	end
	if clock >= key.At then
		key.Held = key.Pending
	end
	return key.Held
end

--- `look` nudged a couple of degrees off, wandering. A mimic that holds its aim perfectly still on
--- you is a turret; a person's drifts, even when they are staring right at you.
function MimicMotion.Drift(look: Vector3, clock: number, seed: number): Vector3
	local phase = clock * TAU / MimicConfig.AimDriftPeriod + seed
	local wander = math.sin(phase) * 0.6 + math.sin(phase * 0.43 + seed) * 0.4
	return CFrame.Angles(0, math.rad(wander * MimicConfig.AimDriftAngle), 0) * look
end

--- `cframe` rotated toward `look` at a human turn rate. Frame-rate independent, so it turns the same
--- on a machine dropping frames as one that is not.
function MimicMotion.Turn(cframe: CFrame, look: Vector3, deltaTime: number): CFrame
	local flat = flatten(look)
	if flat.Magnitude < 1e-3 then return cframe end

	local goal = CFrame.lookAt(cframe.Position, cframe.Position + flat.Unit)
	return cframe:Lerp(goal, 1 - math.exp(-MimicConfig.TurnRate * deltaTime))
end

return MimicMotion
