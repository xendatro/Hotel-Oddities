local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MimicConfig = require(ReplicatedStorage.Configs.MimicConfig)
local MotionTrail = require(ReplicatedStorage.Classes.MotionTrail)

local TAU = math.pi * 2
local UP = Vector3.yAxis

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

function MimicMotion.Keys(sample: MotionTrail.Sample, walkSpeed: number): (number, number)
	local look = flatten(sample.Look)
	local move = flatten(sample.Move)
	if look.Magnitude < 1e-3 or move.Magnitude < 1e-3 then return 0, 0 end

	look = look.Unit
	local deadzone = walkSpeed * MimicConfig.KeyDeadzone
	return press(move:Dot(look), deadzone), press(move:Dot(look:Cross(UP)), deadzone)
end

function MimicMotion.MirrorKeys(forwardKey: number, rightKey: number): (number, number)
	return forwardKey, -rightKey
end

function MimicMotion.Direction(forward: Vector3, forwardKey: number, rightKey: number): Vector3
	local direction = forward * forwardKey + forward:Cross(UP) * rightKey
	return if direction.Magnitude > 1e-3 then direction.Unit else Vector3.zero
end

function MimicMotion.NewKey(): Key
	return { Held = 0, Pending = 0, At = 0 }
end

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

function MimicMotion.Drift(look: Vector3, clock: number, seed: number): Vector3
	local phase = clock * TAU / MimicConfig.AimDriftPeriod + seed
	local wander = math.sin(phase) * 0.6 + math.sin(phase * 0.43 + seed) * 0.4
	return CFrame.Angles(0, math.rad(wander * MimicConfig.AimDriftAngle), 0) * look
end

function MimicMotion.Turn(cframe: CFrame, look: Vector3, deltaTime: number, turnRate: number?): CFrame
	local flat = flatten(look)
	if flat.Magnitude < 1e-3 then return cframe end

	local goal = CFrame.lookAt(cframe.Position, cframe.Position + flat.Unit)
	return cframe:Lerp(goal, 1 - math.exp(-(turnRate or MimicConfig.TurnRate) * deltaTime))
end

return MimicMotion
