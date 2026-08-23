local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Bob = require(ReplicatedStorage.Modules.Bob)
local GhostConfig = require(ReplicatedStorage.Configs.GhostConfig)

local MINIMUM_HEADING = 1e-3

export type Leg = { Origin: CFrame, Target: CFrame, Duration: number, StartedAt: number }

local GhostMotion = {}

GhostMotion.LegAttribute = "DriftStartedAt"
GhostMotion.FadeAttribute = "FadeStartedAt"

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

function GhostMotion.Evaluate(leg: Leg, now: number): CFrame
	local elapsed = now - leg.StartedAt
	local travel = if leg.Duration > 0 then math.clamp(elapsed / leg.Duration, 0, 1) else 1
	local turn = math.clamp(elapsed / GhostConfig.TurnTime, 0, 1)

	local rotation = leg.Origin.Rotation:Lerp(leg.Target.Rotation, turn)
	return rotation + leg.Origin.Position:Lerp(leg.Target.Position, travel)
end

function GhostMotion.Bob(clock: number, phase: number): Vector3
	return Bob.Offset(clock, phase, GhostConfig.BobHeight, GhostConfig.BobPeriod)
end

function GhostMotion.Publish(model: Model, leg: Leg)
	model:SetAttribute("DriftOrigin", leg.Origin)
	model:SetAttribute("DriftTarget", leg.Target)
	model:SetAttribute("DriftDuration", leg.Duration)
	model:SetAttribute(GhostMotion.LegAttribute, leg.StartedAt)
end

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

function GhostMotion.PublishFade(model: Model, startedAt: number)
	model:SetAttribute(GhostMotion.FadeAttribute, startedAt)
end

function GhostMotion.ReadFade(model: Model): number?
	return model:GetAttribute(GhostMotion.FadeAttribute) :: number?
end

function GhostMotion.FadeAlpha(startedAt: number, now: number): number
	local elapsed = math.clamp((now - startedAt) / GhostConfig.FadeTime, 0, 1)
	return TweenService:GetValue(elapsed, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
end

return GhostMotion
