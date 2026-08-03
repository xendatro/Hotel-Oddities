--- The maths of one `Ghost` drift, for both halves of that enemy. Kept apart from either because it
--- is pure: a leg is a start, an end and a stretch of server time, and where the ghost is at any
--- moment is a function of those three. Server and client evaluate the same function against the
--- same clock, so the rendering is not a guess at the authority -- it is the authority, sampled on
--- the frame it is drawn instead of the tick it replicated.
---
--- A leg travels on the model as attributes rather than a remote: attributes reach a player who
--- joins mid-drift for free, where a broadcast would leave them watching a stepped ghost until it
--- picked its next goal.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bob = require(ReplicatedStorage.Modules.Bob)
local GhostConfig = require(ReplicatedStorage.Configs.GhostConfig)

local MINIMUM_HEADING = 1e-3

--- One straight trip: where it set off from, where it is bound, and when it left by server time.
export type Leg = { Origin: CFrame, Target: CFrame, Duration: number, StartedAt: number }

local GhostMotion = {}

--- The attribute a client watches to know a fresh leg has landed. Written last, once the rest of
--- the leg is already on the model, so a change to it always describes a complete leg.
GhostMotion.LegAttribute = "DriftStartedAt"

--- A leg from `origin` to `goal` at `speed`, facing the way it is about to travel.
function GhostMotion.NewLeg(origin: CFrame, goal: Vector3, speed: number, startedAt: number): Leg
	local offset = goal - origin.Position
	local heading = Vector3.new(offset.X, 0, offset.Z)
	local target = if heading.Magnitude > MINIMUM_HEADING
		then CFrame.lookAt(goal, goal + heading.Unit)
		else origin.Rotation + goal

	return {
		Origin = origin,
		Target = target,
		Duration = offset.Magnitude / speed,
		StartedAt = startedAt,
	}
end

--- Where the ghost is at `now`. Travel runs the length of the leg while the turn is over in
--- `GhostConfig.TurnTime`, so it swings onto its heading early and spends the rest of the trip
--- pointed where it is going rather than slowly coming about the whole way.
function GhostMotion.Evaluate(leg: Leg, now: number): CFrame
	local elapsed = now - leg.StartedAt
	local travel = if leg.Duration > 0 then math.clamp(elapsed / leg.Duration, 0, 1) else 1
	local turn = math.clamp(elapsed / GhostConfig.TurnTime, 0, 1)

	local rotation = leg.Origin.Rotation:Lerp(leg.Target.Rotation, turn)
	return rotation + leg.Origin.Position:Lerp(leg.Target.Position, travel)
end

--- The purely visual rise and fall to add on top of a position, at the ghost's own height and
--- period. `phase` is per ghost per client, so no two in the same hall breathe in step.
function GhostMotion.Bob(clock: number, phase: number): Vector3
	return Bob.Offset(clock, phase, GhostConfig.BobHeight, GhostConfig.BobPeriod)
end

--- Puts `leg` on the model for every client to read. Server only.
function GhostMotion.Publish(model: Model, leg: Leg)
	model:SetAttribute("DriftOrigin", leg.Origin)
	model:SetAttribute("DriftTarget", leg.Target)
	model:SetAttribute("DriftDuration", leg.Duration)
	model:SetAttribute(GhostMotion.LegAttribute, leg.StartedAt)
end

--- The leg currently on `model`, or nil before the ghost has set off on its first one.
function GhostMotion.Read(model: Model): Leg?
	local startedAt = model:GetAttribute(GhostMotion.LegAttribute) :: number?
	if not startedAt then return nil end

	return {
		Origin = model:GetAttribute("DriftOrigin") :: CFrame,
		Target = model:GetAttribute("DriftTarget") :: CFrame,
		Duration = model:GetAttribute("DriftDuration") :: number,
		StartedAt = startedAt,
	}
end

return GhostMotion
