local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local GhostConfig = require(ReplicatedStorage.Configs.GhostConfig)
local GhostMotion = require(ReplicatedStorage.Modules.GhostMotion)
local Hallways = require(ReplicatedStorage.Modules.Hallways)
local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local DangerMapService = require(ServerStorage.Services.DangerMapService)
local Gaze = require(ServerStorage.Modules.Gaze)
local GhostAreaService = require(ServerStorage.Services.GhostAreaService)
local NPC = require(ServerStorage.Classes.NPC)

local GHOST_TAG = "Ghost"
local GOAL_ATTEMPTS = 8
local NO_FLOOR_RETRY = 1
local MINIMUM_TRIP = 1e-3
local LURK_POINT_ATTEMPTS = 16
local LURK_CHECK_INTERVAL = 0.15

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
		self:_updateHidden(now)
		if GhostAreaService:IsPlayerNear(self.RootPart.Position) then return true end
	until now - leg.StartedAt >= leg.Duration
	return false
end

function Ghost:_updateHidden(now: number)
	local hiddenUntil = self.HiddenUntil
	if hiddenUntil and now >= hiddenUntil then
		self.HiddenUntil = nil
		GhostMotion.PublishAppear(self.Model, now)
	end
end

function Ghost:_pickLurkSpot(): (Vector3?, Vector3?)
	local config = self.Config
	local point = DangerMapService:PickPoint(config.LurkDangerBias, function(candidate)
		local hallway = Hallways.Nearest(candidate.Position)
		local floorY = if hallway then hallway.FloorY else candidate.Position.Y
		local position = Vector3.new(candidate.Position.X, floorY + config.LurkHeight, candidate.Position.Z)
		if GhostAreaService:IsPlayerNear(position) then return false end
		return not Gaze.IsLookedAt(position, { Ignore = { self.Model } })
	end, LURK_POINT_ATTEMPTS)
	if not point then return nil, nil end

	local hallway = Hallways.Nearest(point.Position)
	local floorY = if hallway then hallway.FloorY else point.Position.Y
	local position = Vector3.new(point.Position.X, floorY + config.LurkHeight, point.Position.Z)

	local facing = if hallway then hallway.Axis else Vector3.zAxis
	if math.random() < 0.5 then
		facing = -facing
	end
	return position, facing
end

function Ghost:_plantAt(position: Vector3, facing: Vector3)
	local cframe = CFrame.lookAt(position, position + facing)
	self.RootPart.CFrame = cframe

	local leg = GhostMotion.NewHold(cframe, workspace:GetServerTimeNow())
	self.Leg = leg
	GhostMotion.Publish(self.Model, leg)
end

local function drift(_changeState: StateMachine.ChangeState, npc: any)
	local now = workspace:GetServerTimeNow()
	npc:_updateHidden(now)

	if now >= npc.ModeEndsAt and not npc.HiddenUntil then
		npc.ModeEndsAt = now + npc.Config.ModePeriod
		if math.random() < npc.Config.LurkChance then
			return "Lurk", npc
		end
	end

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

local function lurk(_changeState: StateMachine.ChangeState, npc: any)
	local position, facing = npc:_pickLurkSpot()
	if not position then
		return "Drift", npc
	end

	GhostMotion.PublishFade(npc.Model, workspace:GetServerTimeNow())
	task.wait(GhostConfig.FadeTime)

	npc:_plantAt(position, facing)
	GhostMotion.PublishAppear(npc.Model, workspace:GetServerTimeNow())

	while true do
		task.wait(LURK_CHECK_INTERVAL)
		local now = workspace:GetServerTimeNow()

		if now >= npc.ModeEndsAt then
			return "Drift", npc
		end

		if Gaze.IsLookedAt(npc.RootPart, { Ignore = { npc.Model } }) then
			GhostMotion.PublishFade(npc.Model, now)
			task.wait(GhostConfig.FadeTime)
			npc.HiddenUntil = workspace:GetServerTimeNow() + npc.Config.LurkHiddenTime
			return "Drift", npc
		end
	end
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
	self.ModeEndsAt = workspace:GetServerTimeNow() + self.Config.ModePeriod
	self.HiddenUntil = nil

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
		Lurk = lurk,
		Vanish = vanish,
		Despawn = NPC.SharedStates.Despawn,
	}, {
		Impact = {},
	}, {}, "Drift", self)
end

return Ghost
