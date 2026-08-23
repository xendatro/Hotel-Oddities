local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local DangerConfig = require(ReplicatedStorage.Configs.DangerConfig)
local DangerMapService = require(ServerStorage.Services.DangerMapService)
local DeathService = require(ServerStorage.Services.DeathService)
local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local HallwayGraphService = require(ServerStorage.Services.HallwayGraphService)
local NpcAnimator = require(ReplicatedStorage.Classes.NpcAnimator)
local RoomService = require(ServerStorage.Services.RoomService)
local Vanished = require(ReplicatedStorage.Modules.Vanished)

local WAYPOINT_REACHED_DISTANCE = 1.25
local POLL_OVERSHOOT_ALLOWANCE = 1.5
local MAX_REACH_FRACTION = 0.75
local DEFAULT_WAYPOINT_SPACING = 4
local MOVEMENT_POLL_INTERVAL = 0.05
local CONTACT_PADDING = 0.25
local CONTACT_ROOT_DISTANCE = 2.25
local DIRECT_PURSUIT_DISTANCE = 24
local CLOSE_PURSUIT_DISTANCE = 16
local DIRECT_PURSUIT_HYSTERESIS = 4
local PURSUIT_OVERSHOOT = 12
local PURSUIT_COMMIT_DISTANCE = 10
local PURSUIT_PROGRESS = 2
local PURSUIT_STALL_GRACE = 1.5
local DIRECT_STALL_RETRY = 2
local UNREACHABLE_MEMORY = 12
local WANDER_ATTEMPTS = 6
local PREFETCH_LEAD = 2.5
local PREFETCH_ORIGIN_TOLERANCE = 12
local MIN_LANE_ADVANCE = 4
local PREFETCH_DESTINATION_TOLERANCE = 1
local FALLBACK_FIELD_OF_VIEW = 100
local ROOM_REACTION_DURATION = 3.5
local ROOM_REACTION_TURN_TIME = 0.45
local FORCED_DOORWAY_ATTRIBUTE = "ForcedDoorway"

local NETWORK_OWNER_REFRESH = 0.5

local PATROL_NODE_HEIGHT = 3
local PATROL_BLOCKED_WAIT = 0.4
local PATROL_BLOCKED_MEMORY = 12
local PATROL_REPLAN_FAILURES = 3

local ENEMY_TAG = "Enemy"
local OBSERVABLE_TAG = "Observable"

local NPC = {}
NPC.__index = NPC

NPC.SharedStates = {}

local ByModel: { [Model]: any } = {}

local function getAliveRoot(player: Player): BasePart?
	local character = player.Character
	if not character then return nil end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then return nil end
	return root :: BasePart
end

local function horizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function isWithinCone(origin: Vector3, lookVector: Vector3, point: Vector3, fieldOfView: number): boolean
	if fieldOfView >= 360 then return true end

	local offset = Vector3.new(point.X - origin.X, 0, point.Z - origin.Z)
	local facing = Vector3.new(lookVector.X, 0, lookVector.Z)
	if offset.Magnitude < 1e-3 or facing.Magnitude < 1e-3 then return true end

	local angle = math.deg(math.acos(math.clamp(offset.Unit:Dot(facing.Unit), -1, 1)))
	return angle <= fieldOfView / 2
end

function NPC.extend(className: string, parent: any?)
	local class = setmetatable({}, { __index = parent or NPC })
	class.__index = class
	class.ClassName = className
	return class
end

function NPC.new(model: Model, config: EnemyConfigs.EnemyConfig, class: any?)
	local self = setmetatable({}, class or NPC)

	self.Model = model
	self.Config = config
	self.Humanoid = model.Humanoid :: Humanoid
	self.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	self.RootPart = model.HumanoidRootPart :: BasePart
	self.Animator = NpcAnimator.new(model, config.Animations)
	self.HomePosition = model:GetPivot().Position
	self.Target = nil :: Player?
	self.AcquireAfter = nil :: number?
	self._observedUntil = nil :: number?
	self._unreachable = {} :: { [Player]: number }
	self._patrol = nil :: any
	self._prefetch = nil :: any
	self._networkOwner = nil :: Player?
	self._ownershipConnection = nil :: RBXScriptConnection?
	self.Active = false
	self.StateMachine = self:BuildStateMachine()

	return self
end

function NPC:BuildStateMachine(): StateMachine.StateMachine
	return StateMachine.new({
		Idle = NPC.SharedStates.Idle,
		Wander = NPC.SharedStates.Wander,
		Patrol = NPC.SharedStates.Patrol,
		Despawn = NPC.SharedStates.Despawn,
	}, {}, {}, "Idle", self)
end

function NPC.FromModel(model: Instance?): any?
	return model and ByModel[model] or nil
end

function NPC:Start()
	if self.Active then return end
	self.Active = true

	ByModel[self.Model] = self
	self.Model:AddTag(ENEMY_TAG)
	if self.Config.ObservationRange then
		self.Model:AddTag(OBSERVABLE_TAG)
	end

	self.HomePosition = self.RootPart.Position
	self.Humanoid.WalkSpeed = self.Config.WalkSpeed
	self:SetNetworkOwner(nil)
	self:_watchNetworkOwner()
	self.Animator:Start()
	self.StateMachine:Start()
end

function NPC:Despawn()
	if not self.Active then return end
	self.Active = false
	self:SetForcedDoorway(nil)

	ByModel[self.Model] = nil
	self:_discardPrefetch()
	self.Model:RemoveTag(ENEMY_TAG)
	self.Model:RemoveTag(OBSERVABLE_TAG)

	if self._ownershipConnection then
		self._ownershipConnection:Disconnect()
		self._ownershipConnection = nil
	end

	task.defer(function()
		self.StateMachine:Stop()
		self.Animator:Destroy()
		self.Model:Destroy()
	end)
end

function NPC:SetSpeed(speed: number)
	self.Humanoid.WalkSpeed = speed
end

function NPC:StopMoving()
	self.Humanoid:MoveTo(self.RootPart.Position)
end

function NPC:SetForcedDoorway(doorway: Model?)
	self.Model:SetAttribute(FORCED_DOORWAY_ATTRIBUTE, doorway and doorway.Name or nil)
end

function NPC:SetNetworkOwner(player: Player?)
	self._networkOwner = player
	self:_applyNetworkOwner()
end

function NPC:_applyNetworkOwner(parts: { Instance }?)
	local owner = self._networkOwner
	if owner and owner.Parent == nil then
		owner = nil
		self._networkOwner = nil
	end

	for _, descendant in parts or self.Model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:CanSetNetworkOwnership() then
			local read, current = pcall(descendant.GetNetworkOwner, descendant)
			local readAuto, automatic = pcall(descendant.GetNetworkOwnershipAuto, descendant)
			if not read or current ~= owner or not readAuto or automatic then
				pcall(descendant.SetNetworkOwner, descendant, owner)
			end
		end
	end
end

function NPC:_watchNetworkOwner()
	self._ownershipConnection = self.Model.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("BasePart") then
			self:_applyNetworkOwner({ descendant })
		end
	end)

	task.spawn(function()
		while self.Active do
			self:_applyNetworkOwner()
			task.wait(NETWORK_OWNER_REFRESH)
		end
	end)
end

function NPC:FaceTowards(position: Vector3)
	local origin = self.RootPart.Position
	local flat = Vector3.new(position.X, origin.Y, position.Z)
	if (flat - origin).Magnitude < 1e-3 then return end
	self.RootPart.CFrame = CFrame.lookAt(origin, flat)
end

function NPC:TurnTowardsSmooth(position: Vector3, duration: number?)
	local origin = self.RootPart.Position
	local flat = Vector3.new(position.X, origin.Y, position.Z)
	if (flat - origin).Magnitude < 1e-3 then return end

	local start = self.RootPart.CFrame
	local target = CFrame.lookAt(origin, flat)
	local elapsed = 0
	local turnTime = duration or ROOM_REACTION_TURN_TIME
	while elapsed < turnTime do
		elapsed += RunService.Heartbeat:Wait()
		self.RootPart.CFrame = start:Lerp(target, math.clamp(elapsed / turnTime, 0, 1))
	end
	self.RootPart.CFrame = target
end

function NPC:ReactAtRoomDoor(room: Model): boolean
	local doorway = RoomService:GetDoorway(room)
	self:SetForcedDoorway(doorway)
	local agentParams = self.Config.AgentParams or {}
	local approach, doorPosition = RoomService:GetDoorApproach(room, agentParams.AgentRadius or 2.5)
	if not approach or not doorPosition then
		self:SetForcedDoorway(nil)
		return false
	end

	self.Animator:Resume()
	self:SetSpeed(self.Config.WalkSpeed)
	local arrived = self:WalkTo(approach)
	self:StopMoving()
	self:SetSpeed(0)
	if not arrived then
		self:SetForcedDoorway(nil)
		return false
	end

	self:TurnTowardsSmooth(doorPosition)
	self.Animator:PlayEmote("cheer")
	task.wait(ROOM_REACTION_DURATION)
	self:SetForcedDoorway(nil)
	return true
end

function NPC:_computePath(origin: Vector3, destination: Vector3): Path?
	local path = PathfindingService:CreatePath(self.Config.AgentParams)
	local ok = pcall(path.ComputeAsync, path, origin, destination)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		path:Destroy()
		return nil
	end
	return path
end

function NPC:_discardPrefetch()
	local entry = self._prefetch
	if not entry then return end
	self._prefetch = nil
	if entry.Done and entry.Path then
		entry.Path:Destroy()
	end
end

function NPC:_pathOrigin(): Vector3
	return self.RootPart.Position - Vector3.yAxis * (self._laneProbeDrop or 0)
end

function NPC:PrefetchPath(destination: Vector3, origin: Vector3?)
	self:_discardPrefetch()

	local entry = { Destination = destination, Origin = origin or self:_pathOrigin(), Path = nil :: Path?, Done = false }
	self._prefetch = entry

	task.spawn(function()
		local path = self:_computePath(entry.Origin, destination)
		entry.Path, entry.Done = path, true
		if self._prefetch ~= entry and path then
			path:Destroy()
		end
	end)
end

function NPC:ComputePath(destination: Vector3, tolerance: number?): Path?
	local entry = self._prefetch
	if entry then
		if (entry.Destination - destination).Magnitude <= (tolerance or PREFETCH_DESTINATION_TOLERANCE)
			and (entry.Origin - self.RootPart.Position).Magnitude <= PREFETCH_ORIGIN_TOLERANCE then
			while not entry.Done do
				task.wait()
			end
			self._prefetch = nil
			if entry.Path then return entry.Path end
		else
			self:_discardPrefetch()
		end
	end
	return self:_computePath(self:_pathOrigin(), destination)
end

function NPC:TakePrefetchedPath(destination: Vector3, tolerance: number?): Path?
	local entry = self._prefetch
	if not entry then return nil end
	if not entry.Done then return nil end

	if (entry.Destination - destination).Magnitude > (tolerance or PREFETCH_DESTINATION_TOLERANCE)
		or (entry.Origin - self.RootPart.Position).Magnitude > PREFETCH_ORIGIN_TOLERANCE
	then
		self:_discardPrefetch()
		return nil
	end

	self._prefetch = nil
	local path = entry.Path
	entry.Path = nil
	return path
end

function NPC:GetMovementWaypoints(path: Path)
	return path:GetWaypoints()
end

function NPC:GetWaypointDistance(position: Vector3): number
	local rootHeight = self.Humanoid.HipHeight + self.RootPart.Size.Y / 2
	local rootPosition = position + Vector3.yAxis * rootHeight
	return (rootPosition - self.RootPart.Position).Magnitude
end

function NPC:_getReachDistance(): number
	local spacing = (self.Config.AgentParams and self.Config.AgentParams.WaypointSpacing) or DEFAULT_WAYPOINT_SPACING
	local perPoll = self.Humanoid.WalkSpeed * MOVEMENT_POLL_INTERVAL * POLL_OVERSHOOT_ALLOWANCE
	return math.clamp(perPoll, WAYPOINT_REACHED_DISTANCE, spacing * MAX_REACH_FRACTION)
end

function NPC:_laneObstruction(destination: Vector3): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter = { self.Model }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(filter, player.Character)
		end
	end
	params.FilterDescendantsInstances = filter
	params.RespectCanCollide = true

	local radius = self.Config.AgentParams.AgentRadius
	local height = math.min(self.Config.AgentParams.AgentHeight, self.RootPart.Size.Y)
	local center = self.RootPart.Position - Vector3.yAxis * (self._laneProbeDrop or 0)
	return workspace:Blockcast(
		CFrame.new(center),
		Vector3.new(radius * 2, height, radius * 2),
		horizontal(destination - self.RootPart.Position),
		params
	)
end

function NPC:GetClearRun(direction: Vector3, distance: number): number
	local heading = horizontal(direction)
	if heading.Magnitude < 1e-3 or distance <= 0 then return 0 end
	heading = heading.Unit

	local obstruction = self:_laneObstruction(self.RootPart.Position + heading * distance)
	if not obstruction then return distance end

	local radius = (self.Config.AgentParams and self.Config.AgentParams.AgentRadius) or 0
	return math.clamp(obstruction.Distance - radius, 0, distance)
end

function NPC:HasMovementClearance(destination: Vector3): boolean
	local offset = horizontal(destination - self.RootPart.Position)
	if offset.Magnitude < 1e-3 then return true end
	return self:_laneObstruction(destination) == nil
end

function NPC:MoveTowards(destination: Vector3): boolean
	local offset = horizontal(destination - self.RootPart.Position)
	if offset.Magnitude < 1e-3 then return false end

	local obstruction = self:_laneObstruction(destination)
	if not obstruction then
		self.Humanoid:MoveTo(destination)
		return true
	end
	if obstruction.Distance < MIN_LANE_ADVANCE then return false end

	self.Humanoid:MoveTo(self.RootPart.Position + offset.Unit * obstruction.Distance)
	return true
end

function NPC:_extendPast(destination: Vector3, beyond: Vector3?): Vector3
	local heading = if beyond then horizontal(beyond - destination) else Vector3.zero
	if heading.Magnitude < 1e-3 then
		heading = horizontal(destination - self.RootPart.Position)
	end
	if heading.Magnitude < 1e-3 then
		heading = horizontal(self.RootPart.CFrame.LookVector)
	end
	if heading.Magnitude < 1e-3 then return destination end
	return destination + heading.Unit * PURSUIT_OVERSHOOT
end

function NPC:MoveThrough(destination: Vector3, beyond: Vector3?)
	local root = self.RootPart.Position
	local extended = self:_extendPast(destination, beyond)
	local offset = horizontal(extended - root)
	if offset.Magnitude < 1e-3 then
		self.Humanoid:MoveTo(destination)
		return
	end

	local obstruction = self:_laneObstruction(extended)
	if not obstruction then
		self.Humanoid:MoveTo(extended)
	elseif obstruction.Distance <= horizontal(destination - root).Magnitude then
		self.Humanoid:MoveTo(destination)
	else
		self.Humanoid:MoveTo(root + offset.Unit * obstruction.Distance)
	end
end

function NPC:AdvanceWaypoint(waypoints: { PathWaypoint }, index: number): number
	local reach = self:_getReachDistance()
	while index < #waypoints do
		local following = waypoints[index + 1]
		if following.Action == Enum.PathWaypointAction.Jump then break end

		local here = self:GetWaypointDistance(waypoints[index].Position)
		if here > reach then
			if self:GetWaypointDistance(following.Position) >= here then break end
			if not self:HasMovementClearance(following.Position) then break end
		end
		index += 1
	end
	return index
end

local function remainingDistances(waypoints: { PathWaypoint }): { number }
	local remaining = table.create(#waypoints, 0)
	for index = #waypoints - 1, 1, -1 do
		remaining[index] = remaining[index + 1]
			+ (waypoints[index + 1].Position - waypoints[index].Position).Magnitude
	end
	return remaining
end

function NPC:_walkPath(
	path: Path,
	shouldAbandon: (() -> boolean)?,
	getNextDestination: (() -> Vector3?)?
): string
	local waypoints = self:GetMovementWaypoints(path)
	local remaining = if getNextDestination then remainingDistances(waypoints) else nil
	local blockedAt = nil :: number?
	local blockedConnection = path.Blocked:Connect(function(index)
		blockedAt = if blockedAt then math.min(blockedAt, index) else index
	end)
	local function finish(result: string): string
		blockedConnection:Disconnect()
		return result
	end

	for index = self:AdvanceWaypoint(waypoints, 2), #waypoints do
		if shouldAbandon and shouldAbandon() then return finish("Abandoned") end
		if blockedAt and blockedAt >= index then return finish("Blocked") end

		local waypoint = waypoints[index]
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			self.Humanoid.Jump = true
		end

		if remaining then
			local left = self:GetWaypointDistance(waypoint.Position) + (remaining :: { number })[index]
			if left / math.max(self.Humanoid.WalkSpeed, 1e-3) <= PREFETCH_LEAD then
				local destination = (getNextDestination :: () -> Vector3?)()
				if destination then
					self:PrefetchPath(destination, waypoints[#waypoints].Position)
				end
				remaining = nil
			end
		end

		self.Humanoid:MoveTo(waypoint.Position)
		if not self.Humanoid.MoveToFinished:Wait() then
			return finish("Blocked")
		end
	end
	return finish("Reached")
end

function NPC:WalkPatrolPath(path: Path, getNextDestination: (() -> Vector3?)?): string
	return self:_walkPath(path, nil, getNextDestination)
end

function NPC:WalkTo(destination: Vector3): boolean
	local path = self:ComputePath(destination)
	if not path then return false end

	local result = self:_walkPath(path)
	path:Destroy()
	return result == "Reached"
end

function NPC:Pursue(
	getGoal: () -> Vector3?,
	arriveDistance: number?,
	hasArrived: (() -> boolean)?,
	canMoveDirectly: (() -> boolean)?
): string
	local config = self.Config
	local commits = arriveDistance == nil and hasArrived == nil
	local commitDistance = config.CommitDistance or PURSUIT_COMMIT_DISTANCE
	local directDistance = config.DirectPursuitDistance or DIRECT_PURSUIT_DISTANCE
	local closeDistance = math.min(config.ClosePursuitDistance or CLOSE_PURSUIT_DISTANCE, directDistance)
	local repathInterval = config.RepathInterval or 0.5
	local repathDistance = config.RepathDistance or 8

	local path = nil :: Path?
	local waypoints = nil :: { PathWaypoint }?
	local index = 2
	local routeGoal = nil :: Vector3?
	local blockedAt = nil :: number?
	local blockedConnection = nil :: RBXScriptConnection?

	local closePursuit = false
	local lastSeen = nil :: Vector3?
	local directBlockedUntil = 0
	local failures, nextRequestAt = 0, 0
	local anchor, movedAt = self.RootPart.Position, os.clock()

	local function dropRoute()
		if blockedConnection then
			blockedConnection:Disconnect()
			blockedConnection = nil
		end
		if path then
			path:Destroy()
			path = nil
		end
		waypoints, index, routeGoal, blockedAt = nil, 2, nil, nil
	end

	local function finish(result: string): string
		dropRoute()
		self:_discardPrefetch()
		return result
	end

	local function backOff()
		failures += 1
		nextRequestAt = os.clock() + math.min(repathInterval * failures, 4)
	end

	local requestedDestination = nil :: Vector3?
	local routeToNode = false

	local function collectRoute(goal: Vector3)
		local entry = self._prefetch
		if not entry or not entry.Done then return end
		if not entry.Path then
			self:_discardPrefetch()
			routeToNode = true
			backOff()
			return
		end

		local ready = self:TakePrefetchedPath(requestedDestination or goal, repathDistance)
		if not ready then return end
		routeToNode = false

		dropRoute()
		path = ready
		local list = self:GetMovementWaypoints(ready)
		waypoints = list
		index = self:AdvanceWaypoint(list, 2)
		routeGoal = goal
		failures = 0
		nextRequestAt = os.clock() + repathInterval
		blockedConnection = ready.Blocked:Connect(function(at: number)
			blockedAt = if blockedAt then math.min(blockedAt, at) else at
		end)
	end

	local function requestRoute(goal: Vector3)
		if self._prefetch then return end
		if os.clock() < nextRequestAt then return end

		local destination = goal
		if routeToNode then
			local node = HallwayGraphService:FindNearestNode(goal)
			if node then
				destination = node.Position + Vector3.yAxis * PATROL_NODE_HEIGHT
			end
		end
		requestedDestination = destination
		self:PrefetchPath(destination)
	end

	while true do
		local goal = getGoal()

		local committed = false
		local target = self.Target
		if commits and target and self:IsValidTarget(target) then
			local position = (getAliveRoot(target) :: BasePart).Position
			if horizontal(self.RootPart.Position - position).Magnitude <= commitDistance then
				goal, committed = position, true
			end
		end

		if not goal then return finish("Lost") end
		if not committed then
			if hasArrived and hasArrived() then return finish("Reached") end
			local reach = horizontal(self.RootPart.Position - goal).Magnitude
			if arriveDistance and reach <= arriveDistance then return finish("Reached") end
		end

		local distance = horizontal(self.RootPart.Position - goal).Magnitude
		if distance <= closeDistance then
			closePursuit = true
		elseif distance > closeDistance + DIRECT_PURSUIT_HYSTERESIS then
			closePursuit = false
		end

		local extendedGoal = self:_extendPast(goal)

		collectRoute(goal)
		if not routeGoal or (goal - routeGoal).Magnitude > repathDistance then
			requestRoute(goal)
		end

		local sighted = if canMoveDirectly then canMoveDirectly() else false
		if sighted then
			lastSeen = goal
		end
		local direct = if canMoveDirectly
			then sighted and (closePursuit or os.clock() >= directBlockedUntil)
			else closePursuit

		local chargeGoal = nil :: Vector3?
		if not direct and not sighted and lastSeen and os.clock() >= directBlockedUntil then
			if horizontal(self.RootPart.Position - lastSeen).Magnitude <= self:_getReachDistance() then
				lastSeen = nil
			else
				chargeGoal = lastSeen
			end
		end

		if direct then
			self.Humanoid:MoveTo(extendedGoal)
		elseif chargeGoal then
			self:MoveThrough(chargeGoal, goal)
		else
			local list = waypoints
			if list and blockedAt and blockedAt >= index then
				dropRoute()
				list = nil
				backOff()
			end
			if list then
				index = self:AdvanceWaypoint(list, index)
				if index >= #list and self:GetWaypointDistance(list[#list].Position) <= self:_getReachDistance() then
					dropRoute()
					list = nil
				end
			end

			if list then
				local waypoint = list[index]
				if waypoint.Action == Enum.PathWaypointAction.Jump then
					self.Humanoid.Jump = true
				end
				local following = list[index + 1]
				self:MoveThrough(waypoint.Position, if following then following.Position else goal)
			else
				self.Humanoid:MoveTo(extendedGoal)
			end
		end

		if (self.RootPart.Position - anchor).Magnitude >= PURSUIT_PROGRESS then
			anchor, movedAt = self.RootPart.Position, os.clock()
		elseif os.clock() - movedAt >= PURSUIT_STALL_GRACE then
			anchor, movedAt = self.RootPart.Position, os.clock()
			if (direct or chargeGoal) and not closePursuit then
				directBlockedUntil = os.clock() + DIRECT_STALL_RETRY
			elseif not direct and not chargeGoal then
				dropRoute()
				backOff()
			end
		end

		task.wait(MOVEMENT_POLL_INTERVAL)
	end
end

function NPC:HasLineOfSight(part: BasePart): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self.Model, part.Parent }
	params.RespectCanCollide = true

	local origin = self.RootPart.Position
	return workspace:Raycast(origin, part.Position - origin, params) == nil
end

function NPC:HasLineOfSightToPlayer(player: Player): boolean
	local root = getAliveRoot(player)
	return root ~= nil and not Vanished.Is(root.Parent) and self:HasLineOfSight(root)
end

local PURSUIT_SIGHT_PARTS = { "Head", "HumanoidRootPart", "RightFoot", "Right Leg" }

function NPC:HasPursuitSight(player: Player): boolean
	local root = getAliveRoot(player)
	if not root then return false end
	local character = root.Parent :: Model
	if Vanished.Is(character) then return false end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self.Model }
	params.RespectCanCollide = true

	local base = self:_pathOrigin()
	local origins = {
		base,
		base + Vector3.yAxis * 1.5,
		base - Vector3.yAxis * 2.5,
	}
	for _, name in PURSUIT_SIGHT_PARTS do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			for _, origin in origins do
				local hit = workspace:Raycast(origin, part.Position - origin, params)
				if not hit or hit.Instance:IsDescendantOf(character) then
					return true
				end
			end
		end
	end
	return false
end

function NPC:GiveUpOn(player: Player?)
	if not player then return end
	self._unreachable[player] = os.clock() + UNREACHABLE_MEMORY
	if self.Target == player then
		self.Target = nil
	end
end

function NPC:_hasGivenUpOn(player: Player): boolean
	local until_ = self._unreachable[player]
	if not until_ then return false end
	if os.clock() < until_ then return true end

	self._unreachable[player] = nil
	return false
end

function NPC:IsValidTarget(player: Player): boolean
	if self:_hasGivenUpOn(player) then return false end

	local root = getAliveRoot(player)
	if not root then return false end
	if Vanished.Is(root.Parent) then return false end
	if self.Config.RespectsSafeRooms and RoomService:IsInRoom(player) then return false end
	return (root.Position - self.RootPart.Position).Magnitude <= self.Config.GiveUpRange
end

function NPC:GetTargetPosition(player: Player): Vector3?
	if not self:IsValidTarget(player) then return nil end
	return (getAliveRoot(player) :: BasePart).Position
end

function NPC:IsTouchingPlayer(player: Player): boolean
	local root = getAliveRoot(player)
	if not root then return false end
	if Vanished.Is(root.Parent) then return false end
	if (self.RootPart.Position - root.Position).Magnitude <= CONTACT_ROOT_DISTANCE then return true end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { root.Parent }
	params.MaxParts = 1

	local padding = Vector3.one * CONTACT_PADDING
	local boundsCFrame, boundsSize = self.Model:GetBoundingBox()
	if #workspace:GetPartBoundsInBox(boundsCFrame, boundsSize + padding, params) == 0 then
		return false
	end

	for _, descendant in self.Model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local overlaps = workspace:GetPartBoundsInBox(descendant.CFrame, descendant.Size + padding, params)
			if #overlaps > 0 then
				return true
			end
		end
	end
	return false
end

function NPC:CanSee(player: Player): boolean
	local root = getAliveRoot(player)
	if not root then return false end
	if Vanished.Is(root.Parent) then return false end
	if self.Config.RespectsSafeRooms and RoomService:IsInRoom(player) then return false end

	local origin = self.RootPart.Position
	if (root.Position - origin).Magnitude > self.Config.DetectionRange then return false end
	if not isWithinCone(origin, self.RootPart.CFrame.LookVector, root.Position, self.Config.FieldOfView) then
		return false
	end
	return self:HasLineOfSight(root)
end

function NPC:_isFacedBy(player: Player, point: Vector3): boolean
	local eye, look = EnemyObservationService:GetView(player)
	if not (eye and look) then return false end
	if not isWithinCone(eye, look, point, FALLBACK_FIELD_OF_VIEW) then return false end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	params.RespectCanCollide = true

	local result = workspace:Raycast(eye, point - eye, params)
	return result == nil or result.Instance:IsDescendantOf(self.Model)
end

function NPC:IsObservedBy(player: Player): boolean
	local root = getAliveRoot(player)
	if not root then return false end

	local boundsCFrame, boundsSize = self.Model:GetBoundingBox()
	local destination = boundsCFrame.Position
	local radius = boundsSize.Magnitude / 2
	if (destination - root.Position).Magnitude - radius > (self.Config.ObservationRange :: number) then return false end
	if EnemyObservationService:IsObservedBy(player, self.Model) then return true end
	if EnemyObservationService:IsReporting(player) then return false end
	return self:_isFacedBy(player, destination)
end

function NPC:IsObserved(): boolean
	for _, player in Players:GetPlayers() do
		if self:IsObservedBy(player) then
			self._observedUntil = os.clock() + (self.Config.ObservationHold or 0)
			return true
		end
	end
	return self._observedUntil ~= nil and os.clock() < self._observedUntil
end

function NPC:CanAcquire(): boolean
	return self.AcquireAfter == nil or os.clock() >= self.AcquireAfter
end

function NPC:_findNearest(predicate: (Player) -> boolean): Player?
	if not self:CanAcquire() then return nil end

	local nearest, nearestDistance = nil, math.huge
	local origin = self.RootPart.Position

	for _, player in Players:GetPlayers() do
		local root = getAliveRoot(player)
		if root and not self:_hasGivenUpOn(player) and predicate(player) then
			local distance = (root.Position - origin).Magnitude
			if distance < nearestDistance then
				nearest, nearestDistance = player, distance
			end
		end
	end
	return nearest
end

function NPC:GetNearestVisibleTarget(): Player?
	return self:_findNearest(function(player)
		return self:CanSee(player)
	end)
end

function NPC:GetNearestTarget(): Player?
	return self:_findNearest(function(player)
		return self:IsValidTarget(player)
	end)
end

function NPC:Attack(player: Player)
	local root = getAliveRoot(player)
	if not root then return end
	if self.Config.RespectsSafeRooms and RoomService:IsInRoom(player) then return end
	if Vanished.Is(root.Parent) then return end

	DeathService:Strike(player, self.Model, self.EnemyId)
end

function NPC.SharedStates.Idle(_changeState: StateMachine.ChangeState, npc: any)
	npc:StopMoving()
	npc.Target = nil
	task.wait(math.random() * (npc.Config.IdleTimeMax - npc.Config.IdleTimeMin) + npc.Config.IdleTimeMin)
	return npc.Config.IdleNextState, npc
end

function NPC.SharedStates.Wander(_changeState: StateMachine.ChangeState, npc: any)
	npc:SetSpeed(npc.Config.WalkSpeed)

	for _ = 1, WANDER_ATTEMPTS do
		local angle = math.random() * math.pi * 2
		local distance = math.random() * npc.Config.WanderRadius
		local goal = npc.HomePosition + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		if npc:WalkTo(goal) then break end
		task.wait(0.2)
	end

	return "Idle", npc
end

local function chooseDestination(current: any, memory: any, minimumDistance: number): any
	local origin = current.Position
	local now = os.clock()

	local candidates, cumulative, total = {}, {}, 0
	for _, node in HallwayGraphService:Get() do
		if node == current or not node.CanBeDestination then continue end
		if (node.Position - origin).Magnitude < minimumDistance then continue end

		local blockedUntil = memory.Blocked[node]
		if blockedUntil then
			if now >= blockedUntil then
				memory.Blocked[node] = nil
			else
				continue
			end
		end

		local weight = 1 + DangerMapService:GetDanger(node.Position) * DangerConfig.PatrolDangerWeight

		local visitedAt = memory.Visited[node]
		if visitedAt then
			local age = memory.Step - visitedAt
			if age < DangerConfig.PatrolVisitMemory then
				weight *= 1 - DangerConfig.PatrolVisitPenalty * (1 - age / DangerConfig.PatrolVisitMemory)
			end
		end

		total += weight
		table.insert(candidates, node)
		table.insert(cumulative, total)
	end

	if total <= 0 then return nil end

	local roll = math.random() * total
	local low, high = 1, #cumulative
	while low < high do
		local middle = (low + high) // 2
		if cumulative[middle] < roll then
			low = middle + 1
		else
			high = middle
		end
	end
	return candidates[low]
end

local function markVisited(memory: any, node: any)
	memory.Step += 1
	memory.Visited[node] = memory.Step
end

function NPC.SharedStates.Patrol(changeState: StateMachine.ChangeState, npc: any)
	npc.Target = nil
	npc.Animator:Resume()
	npc:SetSpeed(npc.Config.WalkSpeed)

	local current = HallwayGraphService:FindNearestNode(npc.RootPart.Position)
	if not current then
		return NPC.SharedStates.Wander(changeState, npc)
	end

	local memory = npc._patrol
	if not memory then
		memory = { Visited = {}, Blocked = {}, Step = 0 }
		npc._patrol = memory
	end

	local minimumTrip = DangerMapService:GetExtent() * DangerConfig.PatrolMinTripFraction

	while true do
		task.wait()

		local destination = chooseDestination(current, memory, minimumTrip)
			or chooseDestination(current, memory, 0)
		if not destination then return "Idle", npc end

		local route = HallwayGraphService:FindPath(current, destination)
		if not route then
			memory.Blocked[destination] = os.clock() + PATROL_BLOCKED_MEMORY
			continue
		end

		local index = 2
		local failures = 0

		while index <= #route do
			task.wait()

			local nextNode = route[index]
			local path = npc:ComputePath(nextNode.Position + Vector3.yAxis * PATROL_NODE_HEIGHT)
			local reached = false

			if path then
				local upcoming = route[index + 1]
				local nextGoal = upcoming and upcoming.Position + Vector3.yAxis * PATROL_NODE_HEIGHT
				reached = npc:WalkPatrolPath(path, nextGoal and function()
					return nextGoal
				end) == "Reached"
				path:Destroy()
			end

			if reached then
				current = nextNode
				markVisited(memory, current)
				index += 1
				failures = 0
			else
				memory.Blocked[nextNode] = os.clock() + PATROL_BLOCKED_MEMORY
				task.wait(PATROL_BLOCKED_WAIT)

				local reacquired = HallwayGraphService:FindNearestNode(npc.RootPart.Position)
				if not reacquired then return "Idle", npc end
				if reacquired ~= current then
					current = reacquired
					markVisited(memory, current)
				end

				failures += 1
				if failures >= PATROL_REPLAN_FAILURES then break end

				local replanned = HallwayGraphService:FindPath(current, destination)
				if not replanned then break end
				route, index = replanned, 2
			end
		end
	end
end

function NPC.SharedStates.Stunned(_changeState: StateMachine.ChangeState, npc: any, duration: number)
	npc.Target = nil
	npc:SetForcedDoorway(nil)
	npc:SetSpeed(0)
	npc:StopMoving()
	npc.Animator:Pause()

	task.wait(duration)

	npc.Animator:Resume()
	return "Idle", npc
end

function NPC.SharedStates.RoomReaction(_changeState: StateMachine.ChangeState, npc: any, room: Model)
	npc.Target = nil
	if npc.StopMirroring then
		npc:StopMirroring()
	end
	npc:ReactAtRoomDoor(room)
	return "Patrol", npc
end

function NPC.SharedStates.Despawn(_changeState: StateMachine.ChangeState, npc: any)
	npc:Despawn()
	coroutine.yield()
end

return NPC
