--- @class Ghost
--- Ambient scenery that happens to be shaped like a person. It never targets, chases or damages
--- anybody -- it only drifts, forever, between random points over the hotel's floors, at the one
--- height above them that `GhostAreaService` hands it.
---
--- Its rig is anchored at the `HumanoidRootPart`, so none of the inherited humanoid locomotion
--- applies: it travels in a straight line from wherever it is to wherever it is going, through walls
--- and through the air alike, and picks a new goal the instant it lands on one. The only pause it
--- ever takes is while the map has no floor in it to drift over.
---
--- This half owns the truth. It picks each goal, publishes the leg, and moves the root along it
--- every heartbeat, so every server-side question about where a ghost is -- a raycast, a range
--- check -- gets the real answer. What it does not do is render: the leg is published for
--- `GhostRenderService` to replay on each client's own frames, which is the difference between a
--- ghost that glides and one that steps forward twenty times a second. The bob lives there too,
--- being nothing but something to look at.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local GhostMotion = require(ReplicatedStorage.Modules.GhostMotion)
local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local GhostAreaService = require(ServerStorage.Services.GhostAreaService)
local NPC = require(ServerStorage.Classes.NPC)

local GHOST_TAG = "Ghost" -- what the client renderer watches for
local GOAL_ATTEMPTS = 8 -- tries at a goal far enough away before it settles for a close one
local NO_FLOOR_RETRY = 1 -- seconds before looking again once nothing is tagged `MazeFloor`
local MINIMUM_TRIP = 1e-3 -- studs below which a leg is not worth travelling

local Ghost = NPC.extend("Ghost")

--- Somewhere new to drift to, preferring a point at least `Config.MinGoalDistance` away so it does
--- not shuffle around in one corner. Nil only while the map offers nowhere at all.
function Ghost:_pickGoal(): Vector3?
	local fallback = nil :: Vector3?

	for _ = 1, GOAL_ATTEMPTS do
		local point = GhostAreaService:GetRandomPoint()
		if not point then return nil end
		if (point - self.RootPart.Position).Magnitude >= self.Config.MinGoalDistance then
			return point
		end
		fallback = point
	end
	return fallback
end

--- Glides in a straight line to `goal` at `Config.DriftSpeed`, yielding until it arrives.
function Ghost:FloatTo(goal: Vector3)
	local origin = self.RootPart.CFrame
	if (goal - origin.Position).Magnitude < MINIMUM_TRIP then
		task.wait()
		return
	end

	local leg = GhostMotion.NewLeg(origin, goal, self.Config.DriftSpeed, workspace:GetServerTimeNow())
	self.Leg = leg
	GhostMotion.Publish(self.Model, leg)

	local now = leg.StartedAt
	repeat
		RunService.Heartbeat:Wait()
		now = workspace:GetServerTimeNow()
		self.RootPart.CFrame = GhostMotion.Evaluate(leg, now)
	until now - leg.StartedAt >= leg.Duration
end

--- Picks a goal, floats to it, and comes straight back for another one.
local function drift(_changeState: StateMachine.ChangeState, npc: any)
	local goal = npc:_pickGoal()
	if not goal then
		task.wait(NO_FLOOR_RETRY)
		return "Drift", npc
	end

	npc:FloatTo(goal)
	return "Drift", npc
end

function Ghost.new(model: Model, config)
	return NPC.new(model, config, Ghost)
end

function Ghost:Start()
	-- Nothing drives this rig but the leg; left on, the humanoid would keep falling out from under
	-- an anchored root and thrashing between its own states.
	self.Humanoid.EvaluateStateMachine = false
	self.Model:AddTag(GHOST_TAG)
	NPC.Start(self)
end

function Ghost:Despawn()
	self.Model:RemoveTag(GHOST_TAG)
	NPC.Despawn(self)
end

function Ghost:BuildStateMachine(): StateMachine.StateMachine
	return StateMachine.new({
		Drift = drift,
		Despawn = NPC.SharedStates.Despawn,
	}, {
		-- Mapped to nothing on purpose: a bear trap or a paper ball cannot hold a ghost still, and
		-- an unmapped reason would warn every time one landed.
		Impact = {},
	}, {}, "Drift", self)
end

return Ghost
