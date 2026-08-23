local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local GhostConfig = require(ReplicatedStorage.Configs.GhostConfig)
local GhostMotion = require(ReplicatedStorage.Modules.GhostMotion)
local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local GhostAreaService = require(ServerStorage.Services.GhostAreaService)
local NPC = require(ServerStorage.Classes.NPC)

local GHOST_TAG = "Ghost"
local GOAL_ATTEMPTS = 8
local NO_FLOOR_RETRY = 1
local MINIMUM_TRIP = 1e-3

local Ghost = NPC.extend("Ghost")

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

function Ghost:FloatTo(goal: Vector3): boolean
	local origin = self.RootPart.CFrame
	if (goal - origin.Position).Magnitude < MINIMUM_TRIP then
		task.wait()
		return false
	end

	local leg = GhostMotion.NewLeg(origin, goal, self.Config.DriftSpeed, workspace:GetServerTimeNow())
	self.Leg = leg
	GhostMotion.Publish(self.Model, leg)

	local now = leg.StartedAt
	repeat
		RunService.Heartbeat:Wait()
		now = workspace:GetServerTimeNow()
		self.RootPart.CFrame = GhostMotion.Evaluate(leg, now)
		if GhostAreaService:IsPlayerNear(self.RootPart.Position) then return true end
	until now - leg.StartedAt >= leg.Duration
	return false
end

local function drift(_changeState: StateMachine.ChangeState, npc: any)
	local goal = npc:_pickGoal()
	if not goal then
		task.wait(NO_FLOOR_RETRY)
		return "Drift", npc
	end

	if npc:FloatTo(goal) then
		return "Vanish", npc
	end
	return "Drift", npc
end

local function vanish(_changeState: StateMachine.ChangeState, npc: any)
	GhostMotion.PublishFade(npc.Model, workspace:GetServerTimeNow())
	task.wait(GhostConfig.FadeTime)
	return "Despawn", npc
end

function Ghost.new(model: Model, config)
	return NPC.new(model, config, Ghost)
end

function Ghost:Start()
	self.Humanoid.EvaluateStateMachine = false

	-- It is driven entirely by assigning RootPart.CFrame, which overwrites
	-- position but never velocity, so left unanchored it banks gravity the whole
	-- time it is alive and launches the moment a leg ends.
	for _, descendant in self.Model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

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
		Vanish = vanish,
		Despawn = NPC.SharedStates.Despawn,
	}, {
		Impact = {},
	}, {}, "Drift", self)
end

return Ghost
