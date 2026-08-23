local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local EnemyDiscoveryService = require(ServerStorage.Services.EnemyDiscoveryService)
local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local HideSpotService = require(ServerStorage.Services.HideSpotService)
local NPC = require(ServerStorage.Classes.NPC)
local Peek = require(ServerStorage.Classes.Enemies.Behaviors.Peek)
local PeekSpotService = require(ServerStorage.Services.PeekSpotService)

local FaceStalker = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Enemies")
	:WaitForChild("FaceStalker") :: RemoteEvent

local PERCEPTION_INTERVAL = 0.25
local HOLD_INTERVAL = 0.1
local FOLLOW_HYSTERESIS = 2
local RETRY_INTERVAL = 0.25

local RETREAT_STEPS = { 20, 12, 6 }
local RETREAT_SPREAD = { 0, 30, -30, 60, -60, 90, -90 }
local RETREAT_TIME = 0.6
local MAX_BLIND_RETREAT = 2
local HEADING_SPEED = 6
local RETREAT_REFRESH = 0.25
local ROUTE_APPROACH_FRACTION = 0.5
local ROUTE_CLEARANCE = 12
local ROUTE_LOOKAHEAD = 30
local ROUTE_DETOUR_LIMIT = 1.7
local ROUTE_DETOUR_FLOOR = 15
local MAX_RETREAT_ATTEMPTS = 5
local RETREAT_PROGRESS = 4
local REPATH_WAIT = 0.1

local Stalker = NPC.extend("Stalker")

local function releaseCamera(npc: any)
	local target = npc.RevealTarget
	npc.RevealTarget = nil
	if target and target.Parent == Players then
		FaceStalker:FireClient(target, nil)
	end
end

local function randomRange(minimum: number, maximum: number): number
	return minimum + math.random() * (maximum - minimum)
end

local function flatten(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

function Stalker:_getFollowPosition(target: Player): (Vector3?, Vector3?)
	local position = self:GetTargetPosition(target)
	if not position then return nil, nil end

	local root = (target.Character :: Model).HumanoidRootPart :: BasePart
	local facing = flatten(root.CFrame.LookVector)
	if facing.Magnitude < 1e-3 then return position, position end
	return position - facing.Unit * self.Config.FollowDistance, position
end

local function getNearestEye(position: Vector3): (Vector3?, number)
	local nearest, nearestDistance = nil :: Vector3?, math.huge
	for _, eye in EnemyObservationService:GetEyes() do
		local distance = (eye - position).Magnitude
		if distance < nearestDistance then
			nearest, nearestDistance = eye, distance
		end
	end
	return nearest, nearestDistance
end

local function isRouteAway(path: Path, origin: Vector3, destination: Vector3): boolean
	local eyes = EnemyObservationService:GetEyes()
	local threshold = ROUTE_CLEARANCE
	for _, eye in eyes do
		threshold = math.min(threshold, flatten(eye - origin).Magnitude * ROUTE_APPROACH_FRACTION)
	end

	local travelled, previous = 0, origin
	for _, waypoint in path:GetWaypoints() do
		travelled += (waypoint.Position - previous).Magnitude
		previous = waypoint.Position
		if travelled > ROUTE_LOOKAHEAD then continue end

		for _, eye in eyes do
			if flatten(waypoint.Position - eye).Magnitude < threshold then return false end
		end
	end

	local direct = (destination - origin).Magnitude
	return direct < ROUTE_DETOUR_FLOOR or travelled <= direct * ROUTE_DETOUR_LIMIT
end

function Stalker:_computeWhileMoving(destination: Vector3, shouldStop: () -> boolean): Path?
	local path, finished = nil :: Path?, false
	task.spawn(function()
		path = self:ComputePath(destination)
		finished = true
	end)

	while not finished do
		if shouldStop() then
			task.spawn(function()
				while not finished do
					task.wait()
				end
				if path then
					path:Destroy()
				end
			end)
			return nil
		end

		local eye = getNearestEye(self.RootPart.Position)
		if eye then
			self:_retreatFrom(eye)
		end
		task.wait(RETREAT_REFRESH)
	end
	return path
end

function Stalker:_sprintTo(destination: Vector3, shouldStop: () -> boolean): string
	local attempts = 0
	local closest = (self.RootPart.Position - destination).Magnitude
	local obstructed = false

	while not shouldStop() do
		local path = self:_computeWhileMoving(destination, shouldStop)
		if not path then
			if shouldStop() then return "Abandoned" end
			attempts += 1
			if attempts >= MAX_RETREAT_ATTEMPTS then return "NoPath" end
			task.wait(REPATH_WAIT)
			continue
		end

		if not isRouteAway(path, self.RootPart.Position, destination) then
			path:Destroy()
			return "PastThem"
		end

		obstructed = false
		local connection = path.Blocked:Connect(function()
			obstructed = true
		end)

		local result = self:_walkPath(path, shouldStop)
		connection:Disconnect()
		path:Destroy()

		if result ~= "Blocked" then return result end

		local distance = (self.RootPart.Position - destination).Magnitude
		if distance < closest - RETREAT_PROGRESS then
			closest, attempts = distance, 0
		else
			attempts += 1
			if attempts >= MAX_RETREAT_ATTEMPTS then
				return if obstructed then "Obstructed" else "Stuck"
			end
		end
		task.wait(REPATH_WAIT)
	end
	return "Abandoned"
end

function Stalker:_retreatFrom(eye: Vector3): boolean
	local origin = self.RootPart.Position
	local away = flatten(origin - eye)
	if away.Magnitude < 1e-3 then return false end
	away = away.Unit

	for _, degrees in RETREAT_SPREAD do
		local direction = CFrame.Angles(0, math.rad(degrees), 0) * away
		for _, step in RETREAT_STEPS do
			local goal = origin + direction * step
			if self:HasMovementClearance(goal) then
				self.Humanoid:MoveTo(goal)
				return true
			end
		end
	end
	return false
end

local function stalk(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	local config = npc.Config
	npc.Target = target
	npc.Animator:Resume()
	npc.Animator:SetMovementTrack("Walk")
	npc:SetSpeed(config.WalkSpeed)

	local strikeAt = os.clock() + randomRange(config.StrikeTimeMin, config.StrikeTimeMax)
	local targetPosition = npc.RootPart.Position
	local ending = nil :: string?

	local function getGoal(): Vector3?
		if npc:IsObserved() then
			ending = "Seen"
			return nil
		end
		if os.clock() >= strikeAt then
			ending = "Strike"
			return nil
		end

		local behind, position = npc:_getFollowPosition(target)
		if not behind then
			ending = "Lost"
			return nil
		end
		targetPosition = position :: Vector3
		return behind
	end

	while not ending do
		local result = npc:Pursue(getGoal, config.FollowSlack, nil, function()
			return npc:HasLineOfSightToPlayer(target)
		end)
		if ending then break end

		if result == "Reached" then
			npc:StopMoving()
			while true do
				local behind = getGoal()
				if not behind then break end

				npc:FaceTowards(targetPosition)
				if (npc.RootPart.Position - behind).Magnitude > config.FollowSlack + FOLLOW_HYSTERESIS then
					break
				end
				task.wait(HOLD_INTERVAL)
			end
		else
			task.wait(config.RepathInterval)
		end
	end

	if ending == "Seen" then return "Flee", npc end
	if ending == "Strike" then return "Reveal", npc, target end
	return "Idle", npc
end

local function reveal(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	local config = npc.Config
	npc.RevealTarget = target
	npc.Target = target
	npc:SetSpeed(0)
	npc:StopMoving()

	local position = npc:GetTargetPosition(target)
	if not position then
		releaseCamera(npc)
		return "Idle", npc
	end

	npc:FaceTowards(position)
	FaceStalker:FireClient(target, npc.Model, config.RevealTurnTime)

	EnemyDiscoveryService:GrantEvent(target, npc.EnemyId)

	task.wait(config.RevealTurnTime + config.RevealHoldTime)

	if not npc:GetTargetPosition(target) then
		releaseCamera(npc)
		return "Idle", npc
	end
	return "Chase", npc, target
end

local function chase(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	npc.Target = target
	npc.Animator:Resume()
	npc.Animator:SetMovementTrack(nil)
	npc:SetSpeed(npc.Config.ChaseSpeed)

	local lastKnown = npc.RootPart.Position
	local result = npc:Pursue(function()
		local position = npc:GetTargetPosition(target)
		if position then
			lastKnown = position
		end
		return position
	end, nil, nil, function()
		return npc:HasLineOfSightToPlayer(target)
	end)

	if result == "Reached" then
		return "Attack", npc, target
	end
	return "Search", npc, lastKnown
end

local function attack(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	local position = npc:GetTargetPosition(target)
	if not position then
		return "Search", npc, npc.RootPart.Position
	end

	if (npc.RootPart.Position - position).Magnitude > npc.Config.AttackRange
		and not npc:IsTouchingPlayer(target)
	then
		return "Chase", npc, target
	end

	npc:Attack(target)
	npc.RevealTarget = nil
	task.wait(npc.Config.AttackCooldown)
	return "Idle", npc
end

local function flee(_changeState: StateMachine.ChangeState, npc: any)
	local config = npc.Config
	npc.Target = nil
	npc.Animator:Resume()
	npc.Animator:SetMovementTrack(nil)
	npc:SetSpeed(config.FleeSpeed)

	local despawnAt = os.clock() + config.FleeTime
	local function shouldDespawn(): boolean
		return not npc:IsObserved() or os.clock() >= despawnAt
	end

	local options = { Range = config.FleeCoverRange, MinDistance = config.FleeCoverMinDistance }
	local pause = 0
	local turnedBack = 0

	local function retreatStep()
		local eye = getNearestEye(npc.RootPart.Position)
		if eye then
			npc:_retreatFrom(eye)
		end
	end

	while not shouldDespawn() do
		retreatStep()

		if pause > 0 then
			local until_ = os.clock() + pause
			while os.clock() < until_ and not shouldDespawn() do
				task.wait(RETREAT_REFRESH)
				retreatStep()
			end
			if shouldDespawn() then break end
			pause = 0
		end

		local velocity = flatten(npc.RootPart.AssemblyLinearVelocity)
		options.Heading = if velocity.Magnitude > HEADING_SPEED then velocity else nil

		local spot = HideSpotService:Find(npc.RootPart.Position, config.AgentParams.AgentRadius, options)
		if not spot then
			pause = RETREAT_TIME
			continue
		end

		local from = npc.RootPart.Position
		local result = npc:_sprintTo(spot, shouldDespawn)

		if result == "NoPath" or result == "Stuck" or result == "Obstructed" then
			local covered = (npc.RootPart.Position - from).Magnitude
			warn(
				`[enemies] stalker retreat came up {result} `
					.. `after {math.floor(covered)} of {math.floor((spot - from).Magnitude)} studs`
			)
		end

		if result == "Reached" then
			pause, turnedBack = 0, 0
		elseif result == "PastThem" then
			turnedBack += 1
			pause = math.min(RETREAT_TIME * turnedBack, MAX_BLIND_RETREAT)
		else
			pause, turnedBack = RETRY_INTERVAL, 0
		end
	end

	return "Despawn", npc
end

local function search(_changeState: StateMachine.ChangeState, npc: any, _lastKnown: Vector3)
	releaseCamera(npc)
	npc.Target = nil
	npc.Animator:Resume()
	npc.Animator:SetMovementTrack("Walk")
	npc:SetSpeed(npc.Config.WalkSpeed)
	return "Patrol", npc
end

local function stunned(changeState: StateMachine.ChangeState, npc: any, duration: number)
	releaseCamera(npc)
	Peek.Exit(npc)
	return NPC.SharedStates.Stunned(changeState, npc, duration)
end

function Stalker:OnPeekFinished(reason: string, player: Player?)
	local held = reason == "Done"
		and player
		and math.random() < (self.Config.StalkChance or 0)
		and self:IsValidTarget(player)

	if held then
		return "Stalk", self, player
	end
	return "Despawn", self
end

function Stalker.new(model: Model, config, spot: PeekSpotService.PeekSpot?, player: Player?)
	local self = NPC.new(model, config, Stalker)
	self.RevealTarget = nil
	self.Spot = spot
	self.Audience = player
	if spot then
		self.StateMachine:SetStartState("Seek", self)
	end
	return self
end

function Stalker:Start()
	self.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	self.Animator:SetMovementTrack("Walk")
	NPC.Start(self)
end

function Stalker:Despawn()
	releaseCamera(self)
	Peek.Exit(self)
	NPC.Despawn(self)
end

function Stalker:BuildStateMachine(): StateMachine.StateMachine
	local npc = self

	local states = {
		Idle = NPC.SharedStates.Idle,
		Wander = NPC.SharedStates.Wander,
		Patrol = NPC.SharedStates.Patrol,
		Despawn = NPC.SharedStates.Despawn,
		Stalk = stalk,
		Reveal = reveal,
		Chase = chase,
		Attack = attack,
		Search = search,
		Flee = flee,
		Stunned = stunned,
	}
	for stateId, state in Peek.States do
		states[stateId] = state
	end

	local calm = { "Idle", "Wander", "Patrol", "Search" }
	local stunnable = { "Idle", "Wander", "Patrol", "Search", "Stalk", "Reveal", "Flee", "Chase", "Attack" }
	for _, stateId in Peek.StateNames do
		table.insert(stunnable, stateId)
	end

	return StateMachine.new(states, {
		Perception = calm,
		Seen = calm,
		Impact = stunnable,
	}, {
		Perception = function()
			while true do
				task.wait(PERCEPTION_INTERVAL)

				if npc:IsObserved() then
					npc.StateMachine:SetState("Flee", "Seen", npc)
					continue
				end

				local target = npc:GetNearestTarget()
				if target then
					npc.StateMachine:SetState("Stalk", "Perception", npc, target)
				end
			end
		end,
	}, "Idle", self)
end

return Stalker
