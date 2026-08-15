--- @class NPC
--- Base chassis for every enemy: locomotion, perception, combat, and lifecycle. Behaviour lives in
--- the `StateMachine` a subclass returns from `BuildStateMachine` -- states are what the NPC is
--- doing, evaluators are perception loops that run alongside them, and the reasons table decides
--- which interruptions may override which states. A wandering horror, a set-path patroller and an
--- ambient prop are all the same chassis with different states and a different config.

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

local WAYPOINT_REACHED_DISTANCE = 1.25 -- the floor on it; see `_getReachDistance` for what widens it
local POLL_OVERSHOOT_ALLOWANCE = 1.5 -- polls' worth of travel a waypoint window has to be able to catch
local MAX_REACH_FRACTION = 0.75 -- of the waypoint spacing, so a leg is never skipped outright
local DEFAULT_WAYPOINT_SPACING = 4 -- what Roblox spaces waypoints at when a config names nothing
local WAYPOINT_PROGRESS = 0.5 -- studs of gain on a waypoint that counts as making ground
local WAYPOINT_STALL_GRACE = 1.5 -- seconds of making none before a leg is called blocked
local MOVE_REFRESH_INTERVAL = 4 -- seconds between re-issued goals; `Humanoid:MoveTo` gives up after eight
local MOVEMENT_POLL_INTERVAL = 0.05
local CONTACT_PADDING = 0.25
local CONTACT_ROOT_DISTANCE = 2.25
local DIRECT_PURSUIT_DISTANCE = 15
local DIRECT_PURSUIT_UPDATE_DISTANCE = 1
local DIRECT_PURSUIT_OVERSHOOT = 4
local MAX_BLOCKED_ATTEMPTS = 3 -- consecutive stalled paths before a pursuit gives up
local MAX_PATH_FAILURES = 5 -- consecutive routes a pursuit fails to compute before it writes the target off
local UNREACHABLE_MEMORY = 12 -- seconds a written-off target stays unacquirable; as `PATROL_BLOCKED_MEMORY`
local WANDER_ATTEMPTS = 6
local PREFETCH_LEAD = 2.5 -- seconds of walking left on a route when the next one starts computing
local PREFETCH_ORIGIN_TOLERANCE = 8 -- studs the guessed start of a prefetched route may be out by
local PREFETCH_DESTINATION_TOLERANCE = 1 -- and its guessed destination, unless a caller allows more
-- Degrees of the cone the server falls back to when a client stops reporting what it can see. A shade
-- wider than the default camera, because the cost of being generous is an enemy that waits a moment
-- longer, and the cost of being stingy is one that moves while you are looking at it.
local FALLBACK_FIELD_OF_VIEW = 100
local ROOM_REACTION_DURATION = 3.5
local ROOM_REACTION_TURN_TIME = 0.45
local FORCED_DOORWAY_ATTRIBUTE = "ForcedDoorway"

local PATROL_NODE_HEIGHT = 3 -- studs above a corridor node the walk goal is put, clear of the slab
local PATROL_BLOCKED_WAIT = 0.4 -- seconds before a patrol that could not path anywhere tries again
local PATROL_TIE_JITTER = 0.05 -- so two equally good corners are not always resolved the same way
local PATROL_BLOCKED_MEMORY = 12 -- seconds a corner it could not reach stays unattractive
local PATROL_BLOCKED_PENALTY = 8 -- and what it costs: more than every other term put together

local ENEMY_TAG = "Enemy" -- carried by every live enemy model, so tools can raycast for them
local OBSERVABLE_TAG = "Observable" -- this enemy reacts to being seen, so clients should report it

local NPC = {}
NPC.__index = NPC

--- States any subclass can drop straight into its own `States` table.
NPC.SharedStates = {}

-- Live enemies by model, so a tool that hits a rig can reach the NPC driving it.
local ByModel: { [Model]: any } = {}

-- The root part of a player's character, or nil while they are dead or respawning.
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

-- Whether `point` falls inside a horizontal cone of `fieldOfView` degrees opening along `lookVector`.
local function isWithinCone(origin: Vector3, lookVector: Vector3, point: Vector3, fieldOfView: number): boolean
	if fieldOfView >= 360 then return true end

	local offset = Vector3.new(point.X - origin.X, 0, point.Z - origin.Z)
	local facing = Vector3.new(lookVector.X, 0, lookVector.Z)
	if offset.Magnitude < 1e-3 or facing.Magnitude < 1e-3 then return true end

	local angle = math.deg(math.acos(math.clamp(offset.Unit:Dot(facing.Unit), -1, 1)))
	return angle <= fieldOfView / 2
end

--- Creates a subclass of NPC with the inheritance chain wired up.
--- @param className string
function NPC.extend(className: string)
	local class = setmetatable({}, { __index = NPC })
	class.__index = class
	class.ClassName = className
	return class
end

--- Builds an NPC around an already-cloned model which is already parented to workspace.
--- @param model Model -- an R15 rig with a `Humanoid`, `HumanoidRootPart` and stock `Animate` script
--- @param config EnemyConfigs.EnemyConfig
--- @param class any -- the subclass to instantiate as; defaults to NPC itself
function NPC.new(model: Model, config: EnemyConfigs.EnemyConfig, class: any?)
	local self = setmetatable({}, class or NPC)

	self.Model = model
	self.Config = config
	self.Humanoid = model.Humanoid :: Humanoid
	self.RootPart = model.HumanoidRootPart :: BasePart
	self.Animator = NpcAnimator.new(model, config.Animations)
	self.HomePosition = model:GetPivot().Position
	self.Target = nil :: Player?
	self.AcquireAfter = nil :: number? -- set by the director; see `CanAcquire`
	self._observedUntil = nil :: number? -- see `IsObserved`
	self._unreachable = {} :: { [Player]: number } -- players written off, and when they stop being
	self._patrol = nil :: any -- corridors walked so far, kept across interruptions; see `SharedStates.Patrol`
	self._prefetch = nil :: any -- the route being worked out ahead of time; see `PrefetchPath`
	self.Active = false
	self.StateMachine = self:BuildStateMachine()

	return self
end

--- Returns this NPC's behaviour. Subclasses override this; the base is a harmless wanderer.
function NPC:BuildStateMachine(): StateMachine.StateMachine
	return StateMachine.new({
		Idle = NPC.SharedStates.Idle,
		Wander = NPC.SharedStates.Wander,
		Patrol = NPC.SharedStates.Patrol,
		Despawn = NPC.SharedStates.Despawn,
	}, {}, {}, "Idle", self)
end

--- The NPC driving `model`, or nil if that model is not a live enemy. Lets a tool that struck a rig
--- reach the behaviour behind it.
function NPC.FromModel(model: Instance?): any?
	return model and ByModel[model] or nil
end

--- Brings the NPC to life. Call once the model is pivoted and parented into the world.
function NPC:Start()
	if self.Active then return end
	self.Active = true

	ByModel[self.Model] = self
	self.Model:AddTag(ENEMY_TAG)
	-- Having an observation range at all is what declares that this enemy cares about being looked
	-- at. The tag is what makes a client's view report about this model legal, so an enemy that would
	-- ignore the answer never costs anybody the raycasts to produce it.
	if self.Config.ObservationRange then
		self.Model:AddTag(OBSERVABLE_TAG)
	end

	self.HomePosition = self.RootPart.Position
	self.Humanoid.WalkSpeed = self.Config.WalkSpeed
	self.Animator:Start()
	self.StateMachine:Start()
end

--- Removes the NPC from the world. Enemies despawn rather than die -- spawning is expected to churn.
--- Safe to call from inside a state; the teardown is deferred off the calling thread.
function NPC:Despawn()
	if not self.Active then return end
	self.Active = false
	self:SetForcedDoorway(nil)

	ByModel[self.Model] = nil
	self:_discardPrefetch()
	self.Model:RemoveTag(ENEMY_TAG)
	self.Model:RemoveTag(OBSERVABLE_TAG)

	task.defer(function()
		self.StateMachine:Stop()
		self.Animator:Destroy()
		self.Model:Destroy()
	end)
end

--- Locomotion ----------------------------------------------------------------------------------

function NPC:SetSpeed(speed: number)
	self.Humanoid.WalkSpeed = speed
end

function NPC:StopMoving()
	self.Humanoid:MoveTo(self.RootPart.Position)
end

function NPC:SetForcedDoorway(doorway: Model?)
	self.Model:SetAttribute(FORCED_DOORWAY_ATTRIBUTE, doorway and doorway.Name or nil)
end

--- Hands simulation of this rig to `player`, or back to the server with nil. An enemy whose movement
--- is driven by one client has to be owned by that client, or every frame of it arrives late.
function NPC:SetNetworkOwner(player: Player?)
	for _, descendant in self.Model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:CanSetNetworkOwnership() then
			descendant:SetNetworkOwner(player)
		end
	end
end

--- Turns to face a point without moving. Yaw only.
function NPC:FaceTowards(position: Vector3)
	local origin = self.RootPart.Position
	local flat = Vector3.new(position.X, origin.Y, position.Z)
	if (flat - origin).Magnitude < 1e-3 then return end
	self.RootPart.CFrame = CFrame.lookAt(origin, flat)
end

--- Turns in place over a few frames, so arriving at a doorway does not end in a body snap.
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

--- Walks to the hall side of a room door, settles, and plays the temporary reaction emote. The
--- movement is still a normal path through the hallway; this only supplies the shared destination
--- and timing so each enemy can replace the reaction state later without changing chase logic.
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

-- Throws away a prefetched route. One still being computed is left to its own thread, which checks
-- whether it is still wanted and tidies up after itself.
function NPC:_discardPrefetch()
	local entry = self._prefetch
	if not entry then return end
	self._prefetch = nil
	if entry.Done and entry.Path then
		entry.Path:Destroy()
	end
end

--- Starts working out a route in the background, so a later `ComputePath` for the same trip can be
--- answered without standing still for it. `ComputeAsync` takes anything from a tenth of a second to
--- two in a hotel this size, and that is dead time at the end of every route unless the next one is
--- already in hand. Only one prefetch is held; asking for another replaces it.
--- @param origin Vector3? -- where the NPC will be when it sets off; defaults to where it is now
function NPC:PrefetchPath(destination: Vector3, origin: Vector3?)
	self:_discardPrefetch()

	local entry = { Destination = destination, Origin = origin or self.RootPart.Position, Path = nil :: Path?, Done = false }
	self._prefetch = entry

	task.spawn(function()
		local path = self:_computePath(entry.Origin, destination)
		entry.Path, entry.Done = path, true
		-- Superseded, taken up, or despawned while this was being worked out.
		if self._prefetch ~= entry and path then
			path:Destroy()
		end
	end)
end

--- A computed path to `destination`, or nil if none exists. Callers own the returned path.
---
--- A prefetched route answers this without yielding, provided it was aimed close enough to the same
--- place and set off from close enough to where the NPC actually ended up. `tolerance` widens how far
--- the destination may have moved, for callers chasing something that does not stand still.
function NPC:ComputePath(destination: Vector3, tolerance: number?): Path?
	local entry = self._prefetch
	if entry then
		if (entry.Destination - destination).Magnitude <= (tolerance or PREFETCH_DESTINATION_TOLERANCE)
			and (entry.Origin - self.RootPart.Position).Magnitude <= PREFETCH_ORIGIN_TOLERANCE then
			while not entry.Done do
				task.wait()
			end
			self._prefetch = nil
			-- A prefetch that came back empty was asked from a position this only expected to be in, so
			-- there is still an honest answer to be had from where it is now.
			if entry.Path then return entry.Path end
		else
			self:_discardPrefetch()
		end
	end
	return self:_computePath(self.RootPart.Position, destination)
end

--- Preserves the pathfinder's complete route. Skipping waypoints based only on their angle can turn
--- a gradual route around a wall into a single movement goal through it. The movement loop advances
--- before reaching each waypoint, so following the complete route does not make the Humanoid stop.
function NPC:GetMovementWaypoints(path: Path)
	return path:GetWaypoints()
end

--- Distance from the root to where it will stand after reaching a path waypoint. Pathfinding returns
--- floor positions, while a humanoid's root settles `HipHeight` plus half its own height above them.
function NPC:GetWaypointDistance(position: Vector3): number
	local rootHeight = self.Humanoid.HipHeight + self.RootPart.Size.Y / 2
	local rootPosition = position + Vector3.yAxis * rootHeight
	return (rootPosition - self.RootPart.Position).Magnitude
end

-- How near a waypoint has to be before the leg to it counts as walked.
--
-- It cannot be a fixed radius, because the radius is a window the rig has to be found *inside* on a
-- poll and a fast one steps clean over it: at a flee speed of 32 a poll is 1.6 studs apart, wider than
-- the window, so arrival is missed as often as not. What follows is not a rig that keeps running --
-- it is one that walks past the waypoint, notices it is getting further away, turns round for it, and
-- burns its stall grace doing that at every second corner. Visible as a run that keeps hitching, with
-- nothing logged, because each leg does eventually recover.
--
-- So the window is at least one poll wide with room to spare, and held under the waypoint spacing so a
-- leg is still walked rather than skipped. Advancing early is already the intended behaviour here: the
-- goal is replaced before the humanoid slows for it, which is what keeps a route continuous.
function NPC:_getReachDistance(): number
	local spacing = (self.Config.AgentParams and self.Config.AgentParams.WaypointSpacing) or DEFAULT_WAYPOINT_SPACING
	local perPoll = self.Humanoid.WalkSpeed * MOVEMENT_POLL_INTERVAL * POLL_OVERSHOOT_ALLOWANCE
	return math.clamp(perPoll, WAYPOINT_REACHED_DISTANCE, spacing * MAX_REACH_FRACTION)
end

--- Whether the whole agent, rather than only a sight ray through its center, has an unobstructed
--- horizontal lane to `destination`. This is required before pursuit bypasses the navmesh at close
--- range; otherwise a visible player just beyond a corner can make a wide rig charge into its wall.
function NPC:HasMovementClearance(destination: Vector3): boolean
	local offset = horizontal(destination - self.RootPart.Position)
	if offset.Magnitude < 1e-3 then return true end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter = { self.Model }
	if self.Target and self.Target.Character then
		table.insert(filter, self.Target.Character)
	end
	params.FilterDescendantsInstances = filter
	params.RespectCanCollide = true

	local radius = self.Config.AgentParams.AgentRadius
	local height = math.min(self.Config.AgentParams.AgentHeight, self.RootPart.Size.Y)
	return workspace:Blockcast(
		CFrame.new(self.RootPart.Position),
		Vector3.new(radius * 2, height, radius * 2),
		offset,
		params
	) == nil
end

-- Distance still to be walked from waypoint `index` to the end of `waypoints`, by index.
local function remainingDistances(waypoints: { PathWaypoint }): { number }
	local remaining = table.create(#waypoints, 0)
	for index = #waypoints - 1, 1, -1 do
		remaining[index] = remaining[index + 1]
			+ (waypoints[index + 1].Position - waypoints[index].Position).Magnitude
	end
	return remaining
end

-- Walks the waypoints of `path`, polling `shouldAbandon` between each. Returns "Reached" once the
-- last waypoint lands, "Abandoned" if the caller bailed out, or "Blocked" if it stopped making ground.
--
-- Two things about `Humanoid:MoveTo` shape this loop. It gives up on its own after eight seconds, so
-- a goal has to be re-issued or the rig simply stops mid-corridor. And there is no honest clock to
-- judge the rest by: ideal travel time says nothing about a leg spent walking around a player who is
-- in the doorway. So a leg ends when it stops closing on its goal, not when it runs long.
--
-- `getNextDestination` is where the caller expects to go after this route. Given one, the route there
-- is worked out during the last few seconds of this one, off this thread, so arriving does not mean
-- stopping to think. Asking earlier would only buy a staler answer for a moving goal, and asking on
-- the walking thread is exactly the pause this exists to remove.
function NPC:_walkPath(
	path: Path,
	shouldAbandon: (() -> boolean)?,
	getNextDestination: (() -> Vector3?)?,
	smoothCorners: boolean?
): string
	local waypoints = self:GetMovementWaypoints(path)
	local reachDistance = self:_getReachDistance()
	local remaining = if getNextDestination then remainingDistances(waypoints) else nil
	local blockedAt = nil :: number?
	local blockedConnection = path.Blocked:Connect(function(index)
		blockedAt = if blockedAt then math.min(blockedAt, index) else index
	end)
	local function finish(result: string): string
		blockedConnection:Disconnect()
		return result
	end

	for index = 2, #waypoints do
		if shouldAbandon and shouldAbandon() then return finish("Abandoned") end
		if blockedAt and blockedAt >= index then return finish("Blocked") end

		local waypoint = waypoints[index]
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			self.Humanoid.Jump = true
		end

		local goal = waypoint.Position
		local goalDistance = self:GetWaypointDistance(goal)
		local nextWaypoint = waypoints[index + 1]
		local turnAheadDistance = if smoothCorners
			then self.Config.PatrolTurnAheadDistance or 0
			else 0
		local turningEarly = false

		self.Humanoid:MoveTo(goal)
		local closest = goalDistance
		local progressedAt = os.clock()
		local refreshAt = os.clock() + MOVE_REFRESH_INTERVAL

		if remaining then
			local left = closest + (remaining :: { number })[index]
			if left / math.max(self.Humanoid.WalkSpeed, 1e-3) <= PREFETCH_LEAD then
				local destination = (getNextDestination :: () -> Vector3?)()
				if destination then
					self:PrefetchPath(destination, waypoints[#waypoints].Position)
				end
				remaining = nil
			end
		end

		while true do
			local distance = self:GetWaypointDistance(goal)
			if distance <= reachDistance then break end
			if shouldAbandon and shouldAbandon() then return finish("Abandoned") end
			if blockedAt and blockedAt >= index then return finish("Blocked") end

			if distance < closest - WAYPOINT_PROGRESS then
				closest, progressedAt = distance, os.clock()
			elseif os.clock() - progressedAt >= WAYPOINT_STALL_GRACE then
				return finish("Blocked")
			end

			if not turningEarly
				and nextWaypoint
				and nextWaypoint.Action ~= Enum.PathWaypointAction.Jump
				and self:GetWaypointDistance(waypoint.Position) <= turnAheadDistance
				and self:HasMovementClearance(nextWaypoint.Position)
			then
				goal = nextWaypoint.Position
				turningEarly = true
				closest = self:GetWaypointDistance(goal)
				progressedAt = os.clock()
				self.Humanoid:MoveTo(goal)
			end

			if os.clock() >= refreshAt then
				refreshAt = os.clock() + MOVE_REFRESH_INTERVAL
				self.Humanoid:MoveTo(goal)
			end
			task.wait(MOVEMENT_POLL_INTERVAL)
		end
	end
	return finish("Reached")
end

--- Patrols may opt into a little corner anticipation without changing pursuit movement.
function NPC:WalkPatrolPath(path: Path, getNextDestination: (() -> Vector3?)?): string
	return self:_walkPath(path, nil, getNextDestination, true)
end

--- Walks a single pathed trip to a fixed point. Returns whether it arrived.
function NPC:WalkTo(destination: Vector3): boolean
	local path = self:ComputePath(destination)
	if not path then return false end

	local result = self:_walkPath(path)
	path:Destroy()
	return result == "Reached"
end

--- Chases a moving goal, re-pathing as it drifts. `getGoal` returns nil once the goal stops being
--- valid. When `canMoveDirectly` succeeds at close range, it continuously drives straight at the
--- goal instead of replacing a completed path. Returns "Reached" when `hasArrived` succeeds or it
--- comes within `arriveDistance`, "Lost" when the goal goes invalid, or "Blocked" when the NPC
--- cannot make progress.
---
--- Failing to compute a route enough times running writes the current target off through `GiveUpOn`,
--- so a chase that ends "Blocked" against somebody genuinely unreachable is not started again a
--- moment later by the same perception that started this one.
function NPC:Pursue(
	getGoal: () -> Vector3?,
	arriveDistance: number?,
	hasArrived: (() -> boolean)?,
	canMoveDirectly: (() -> boolean)?
): string
	local blockedAttempts = 0
	local pathFailures, failureTarget = 0, self.Target
	local directGoal = nil :: Vector3?
	local directRefreshAt = 0

	while true do
		local goal = getGoal()
		if not goal then return "Lost" end
		if hasArrived and hasArrived() then return "Reached" end

		local distance = (self.RootPart.Position - goal).Magnitude
		if arriveDistance and distance <= arriveDistance then return "Reached" end
		if distance <= DIRECT_PURSUIT_DISTANCE
			and canMoveDirectly
			and canMoveDirectly()
			and self:HasMovementClearance(goal) then
			blockedAttempts, pathFailures = 0, 0
			-- Re-issued on a clock as well as on drift, because a goal that has stopped moving is
			-- exactly the case that never trips the drift check: a player standing still somewhere
			-- this cannot quite reach would otherwise be charged at once and then watched from a
			-- standstill, `Humanoid:MoveTo` having quietly given up eight seconds in.
			if not directGoal
				or (goal - directGoal).Magnitude >= DIRECT_PURSUIT_UPDATE_DISTANCE
				or os.clock() >= directRefreshAt then
				directGoal = goal
				directRefreshAt = os.clock() + MOVE_REFRESH_INTERVAL
				local direction = goal - self.RootPart.Position
				local movementGoal = if direction.Magnitude > 1e-3
					then goal + direction.Unit * DIRECT_PURSUIT_OVERSHOOT
					else goal
				self.Humanoid:MoveTo(movementGoal)
			end
			task.wait(MOVEMENT_POLL_INTERVAL)
			continue
		end
		directGoal = nil

		-- A prefetched route is worth taking as long as the target has not moved further than a repath
		-- would have been triggered by anyway, which is the drift this pursuit already tolerates.
		local path = self:ComputePath(goal, self.Config.RepathDistance)
		if not path then
			-- A route that cannot be worked out is a different problem from one that cannot be walked,
			-- so it is counted separately. A stalled leg is nearly always something standing in the way
			-- and clears on its own, which is what `blockedAttempts` backs off for. Nothing being
			-- routable to the goal, over and over, is the goal itself being out of reach -- and coming
			-- back to it from the top of the next chase is how an enemy spends a whole round walking to
			-- the same corner and looking around. So that one is given up on rather than retried.
			--
			-- Several in a row, because one means very little: doors move, and the navmesh is a moment
			-- behind them, so a single miss is a beat of bad timing rather than a target it cannot get to.
			--
			-- The patience is per target. A run of failures describes one goal and says nothing about
			-- the next, so a pursuit handed somebody else part way through starts over rather than
			-- writing them off on the strength of what it could not reach before.
			if self.Target ~= failureTarget then
				pathFailures, failureTarget = 0, self.Target
			end
			pathFailures += 1
			if pathFailures >= MAX_PATH_FAILURES then
				self:GiveUpOn(self.Target)
				return "Blocked"
			end
			task.wait(self.Config.RepathInterval)
			continue
		end
		pathFailures = 0

		local repathAt = os.clock() + self.Config.RepathInterval
		local arrived = false
		local repathing = false
		local result = self:_walkPath(path, function()
			local current = getGoal()
			if not current then return true end
			if hasArrived and hasArrived() then
				arrived = true
				return true
			end
			if arriveDistance and (self.RootPart.Position - current).Magnitude <= arriveDistance then
				return true
			end
			if os.clock() < repathAt or (current - goal).Magnitude <= self.Config.RepathDistance then
				return false
			end

			-- A route that has gone stale is not worth stopping for until its replacement is in hand.
			-- Abandoning on the spot puts the NPC back at the top of this loop, where `ComputePath` is
			-- a yield of anything up to a second -- and against somebody running, that condition is met
			-- again every `RepathInterval`, so the chase becomes a walk punctuated by standing still.
			-- The route it is on still points broadly the right way for the moment it takes to work the
			-- next one out, so it keeps walking it and swaps when there is something to swap to.
			if not repathing then
				repathing = true
				self:PrefetchPath(current)
				return false
			end
			local entry = self._prefetch
			return entry == nil or entry.Done
		end, getGoal)
		path:Destroy()

		if arrived then return "Reached" end
		if result == "Blocked" then
			blockedAttempts += 1
			if blockedAttempts >= MAX_BLOCKED_ATTEMPTS then return "Blocked" end
			task.wait(self.Config.RepathInterval)
		else
			blockedAttempts = 0
		end
	end
end

--- Perception ----------------------------------------------------------------------------------

--- Whether nothing solid stands between this NPC and `part`. Other enemies and non-collidable
--- volumes (safe rooms included) do not block sight.
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

--- Stops this NPC pursuing `player` and keeps it from picking them up again for a while. What a
--- pursuit does when it cannot work out a route to somebody at all.
---
--- Ending the chase alone would not settle anything: the enemy walks back onto its patrol, perception
--- finds the same unreachable player from the same corridor a quarter of a second later, and the whole
--- thing runs again for the rest of the round -- which reads as an enemy pacing and staring at nothing.
--- Held for a while rather than for ever, because what puts somebody out of reach is nearly always
--- where they are standing, and they do not stand there all night.
--- @param player Player? -- nil where a pursuit was following something other than a player
function NPC:GiveUpOn(player: Player?)
	if not player then return end
	self._unreachable[player] = os.clock() + UNREACHABLE_MEMORY
	if self.Target == player then
		self.Target = nil
	end
end

-- Whether `player` has been written off as unreachable and is not to be picked up again yet.
function NPC:_hasGivenUpOn(player: Player): boolean
	local until_ = self._unreachable[player]
	if not until_ then return false end
	if os.clock() < until_ then return true end

	self._unreachable[player] = nil
	return false
end

--- Whether a player is worth pursuing at all: alive, out of a safe room, and still in range.
--- Deliberately ignores facing and sight, so an acquired target cannot be shaken by ducking behind
--- a corner -- only by reaching a room or outrunning `GiveUpRange`.
function NPC:IsValidTarget(player: Player): boolean
	if self:_hasGivenUpOn(player) then return false end

	local root = getAliveRoot(player)
	if not root then return false end
	if Vanished.Is(root.Parent) then return false end
	if self.Config.RespectsSafeRooms and RoomService:IsInRoom(player) then return false end
	return (root.Position - self.RootPart.Position).Magnitude <= self.Config.GiveUpRange
end

--- Where to chase a player right now, or nil if they stopped being a valid target.
function NPC:GetTargetPosition(player: Player): Vector3?
	if not self:IsValidTarget(player) then return nil end
	return (getAliveRoot(player) :: BasePart).Position
end

--- Whether any part of this enemy is touching, or within a tiny contact tolerance of, a player's
--- character. This is the arrival condition for enemies that attack on contact.
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

--- Whether this NPC can actually see a player: in range, inside its view cone, and in clear sight.
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

-- Whether this NPC sits in front of `player` and in clear sight of them, judged from what the server
-- knows on its own. The stand-in for a client report that never arrived.
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

--- Whether a player's client reports any visible portion of this NPC on screen. Reports identify
--- server-created enemy models and expire quickly; range remains server-authoritative.
---
--- A client that has gone quiet is not a blind one. Reports expire in a fifth of a second, which a
--- frame hitch or a bad moment on the wire clears easily, and every one of those would otherwise read
--- as permission for something that must not move while watched to move on somebody staring straight
--- at it. So silence falls back to the server's own answer rather than to "no". The game is first
--- person, which is what makes that answer worth having: the character's facing is a fair stand-in
--- for where the camera points, and `GetView` already hands back exactly that when no report is in.
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

--- Whether any player is looking at this NPC.
---
--- `Config.ObservationHold` keeps that true for a moment after the last sighting. Getting the answer
--- here is a chain of intervals -- the client samples at 20Hz, the packet flies, an evaluator polls --
--- and any link can drop a beat, so a single late report otherwise reads as "nobody is watching any
--- more". With the hold it takes a continuous gap to let go, which is the reading that matches what
--- the player is actually doing.
function NPC:IsObserved(): boolean
	for _, player in Players:GetPlayers() do
		if self:IsObservedBy(player) then
			self._observedUntil = os.clock() + (self.Config.ObservationHold or 0)
			return true
		end
	end
	return self._observedUntil ~= nil and os.clock() < self._observedUntil
end

--- Whether this NPC is allowed to pick a target yet. Freshly spawned enemies are blind for a moment:
--- the director keeps a spawn away from everybody and out of sight, but geometry conspires -- a
--- corridor bends back, somebody walks while the placement is being drawn -- and this is what makes
--- "nothing ever starts a chase on the frame it appears" true rather than merely likely.
---
--- Acquisition only. An enemy already chasing somebody is not affected, because losing a target
--- halfway through a chase is a different thing entirely.
function NPC:CanAcquire(): boolean
	return self.AcquireAfter == nil or os.clock() >= self.AcquireAfter
end

-- Nearest player satisfying `predicate`, if any. Anyone this NPC has given up on is skipped: this is
-- the only way into a chase, so it is where writing somebody off has to be honoured, and it is the
-- same kind of gate as `CanAcquire` -- about whether a target may be taken up rather than about
-- whether it can be seen.
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

--- Nearest player this NPC can actually see. Respects its view cone.
function NPC:GetNearestVisibleTarget(): Player?
	return self:_findNearest(function(player)
		return self:CanSee(player)
	end)
end

--- Nearest player worth pursuing, ignoring facing and sight.
function NPC:GetNearestTarget(): Player?
	return self:_findNearest(function(player)
		return self:IsValidTarget(player)
	end)
end

--- Combat -------------------------------------------------------------------------------------

function NPC:Attack(player: Player)
	local root = getAliveRoot(player)
	if not root then return end
	-- Checked here as well as in perception, and not as a formality. Everything that reaches this
	-- line decided to attack at some earlier moment -- a lunge is committed to before it lands -- so
	-- perception refusing to *acquire* a vanished player says nothing about one who vanished while
	-- something was already swinging at them. This is where the promise actually holds.
	if Vanished.Is(root.Parent) then return end

	-- Ahead of the damage rather than after it, so the swing is on screen for the frame that kills:
	-- everything that gets here is lethal by default, and a clip started afterwards plays to a corpse.
	self.Animator:PlayAttack()

	local humanoid = (root.Parent :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid
	DeathService:RecordCause(player, self.EnemyId)
	if self.Config.Damage == math.huge then
		humanoid.Health = 0
	else
		humanoid:TakeDamage(self.Config.Damage)
	end
end

--- Shared states ------------------------------------------------------------------------------

--- Stands still for a random beat, then hands off to `Config.IdleNextState`.
function NPC.SharedStates.Idle(_changeState: StateMachine.ChangeState, npc: any)
	npc:StopMoving()
	npc.Target = nil
	task.wait(math.random() * (npc.Config.IdleTimeMax - npc.Config.IdleTimeMin) + npc.Config.IdleTimeMin)
	return npc.Config.IdleNextState, npc
end

--- Strolls to a random reachable point within `Config.WanderRadius` of where it spawned.
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

--- Which way to go on at a junction. First it may deliberately turn around; otherwise four things
--- decide it, and the first three are deliberately on comparable scales so none simply wins:
---
---  * **Straightness.** Carrying on down the corridor you are already in beats turning, which is what
---    makes a patrol read as walking somewhere rather than milling about.
---  * **Danger.** A thumb on the scale towards the worse half of the hotel. Without this, free-roaming
---    patrols even out across the whole map within a few minutes and the danger field stops
---    describing where anything actually is. With it, they drift out of the quiet wings on their own
---    -- which is also what keeps the entrance calm without anything having to enforce that.
---  * **Which corridors it has already walked.** Not which corners it has stood on -- that distinction
---    is the whole of why patrols used to lap the same ring of hallways for ever. Coming back around a
---    loop to a junction it has been through before, the way straight on and the turn are both equally
---    unvisited *as places*, so a memory of places has nothing to say and straightness wins by a full
---    point, every lap, for ever. As corridors they are not equal at all: straight on repeats one it
---    has just walked and the turn does not. Weighted well above the straightness range, or it could
---    never actually turn a patrol off the corridor it is committed to.
---  * **What it has just failed to reach.** Off that scale on purpose. A corner nothing can path to is
---    not a worse choice than the others, it is not a choice, and the alternative is retrying it every
---    four tenths of a second for the rest of the round. It stays a penalty rather than an exclusion
---    so that a junction whose every exit is blocked still picks one and moves instead of giving up.
local function chooseNextNode(
	config: EnemyConfigs.EnemyConfig,
	previous: any,
	current: any,
	walked: { [any]: { [any]: number } },
	step: number,
	blocked: { [any]: number }
): any
	local best, bestScore = nil, -math.huge
	local now = os.clock()
	if previous
		and current.Neighbors[previous]
		and HallwayGraphService:CountExits(current) >= (config.PatrolTurnAroundMinExits or 3)
		and math.random() < (config.PatrolTurnAroundChance or DangerConfig.PatrolTurnAroundChance)
	then
		return previous
	end

	for neighbor in current.Neighbors do
		local score = DangerMapService:GetDanger(neighbor.Position) * DangerConfig.PatrolDangerWeight
		score += math.random() * PATROL_TIE_JITTER

		if previous then
			local incoming = horizontal(current.Position - previous.Position)
			local outgoing = horizontal(neighbor.Position - current.Position)
			if incoming.Magnitude > 1e-3 and outgoing.Magnitude > 1e-3 then
				score += incoming.Unit:Dot(outgoing.Unit)
			end
		end

		-- Fades out linearly rather than expiring all at once, so a corridor becomes gradually worth
		-- reusing instead of being untouchable and then abruptly free.
		local fromHere = walked[current]
		local lastWalked = fromHere and fromHere[neighbor]
		if lastWalked then
			local age = step - lastWalked
			if age < DangerConfig.PatrolEdgeMemory then
				score -= DangerConfig.PatrolEdgePenalty * (1 - age / DangerConfig.PatrolEdgeMemory)
			end
		end

		local blockedUntil = blocked[neighbor]
		if blockedUntil then
			if now >= blockedUntil then
				blocked[neighbor] = nil
			else
				score -= PATROL_BLOCKED_PENALTY
			end
		end

		if score > bestScore then
			best, bestScore = neighbor, score
		end
	end

	return best
end

-- Records that the corridor between two corners has just been walked. Held both ways round: a
-- corridor is the same corridor whichever end you come at it from, and a patrol that only recognised
-- the direction it first took would happily walk the same stretch back and forth for ever.
local function markWalked(walked: { [any]: { [any]: number } }, from: any, to: any, step: number)
	walked[from] = walked[from] or {}
	walked[to] = walked[to] or {}
	walked[from][to] = step
	walked[to][from] = step
end

--- Walks the corridor graph, corner to corner, indefinitely.
---
--- This is what an enemy does when it has nothing better to do, and it replaces strolling around the
--- point it spawned at. That version never left its own bubble and stopped dead between trips, which
--- reads as a prop idling rather than as something looking for you. Patrolling covers the hotel,
--- keeps moving, and means the corridor you are about to walk into may already have something in it.
---
--- It never resolves on its own -- the machine's evaluators are what pull an enemy out of here, so
--- every reason table that lists `Idle` must list `Patrol` alongside it, or perception can never
--- interrupt a patrol.
---
--- What it has walked outlives any one visit. A patrol is interrupted constantly -- a chase, a trap,
--- a Weeping Angel freezing every time somebody glances down the corridor -- and starting fresh each
--- time hands the next choice to the danger field alone, which is a fixed function of position and
--- returns the same answer every time. That walks it straight back the way it came, so an enemy that
--- is interrupted often paces instead of patrolling. Where it thinks it is *does* get re-read from
--- the world on every entry, because after a chase it is nowhere near where it left off.
function NPC.SharedStates.Patrol(changeState: StateMachine.ChangeState, npc: any)
	npc.Target = nil
	npc.Animator:Resume()
	npc:SetSpeed(npc.Config.WalkSpeed)

	local current = HallwayGraphService:FindNearestNode(npc.RootPart.Position)
	if not current then
		-- No tagged corridors at all. Falling back keeps an untagged or half-built map playable
		-- instead of leaving every enemy standing still wondering where the hallways went.
		return NPC.SharedStates.Wander(changeState, npc)
	end

	local memory = npc._patrol
	if not memory then
		memory = { Walked = {}, Blocked = {}, Step = 0 }
		npc._patrol = memory
	end

	local previous = nil :: any
	local walked: { [any]: { [any]: number } } = memory.Walked
	local blocked: { [any]: number } = memory.Blocked
	local step = memory.Step
	local planned = nil :: any -- the corner picked a leg early, whose route is already in hand

	while true do
		-- One frame, unconditionally. A path to a node it is effectively already standing on comes
		-- back with nothing to walk and returns without yielding, and a loop that can complete an
		-- iteration without yielding is a loop that can lock the server.
		task.wait()
		step += 1
		memory.Step = step

		local nextNode = planned or chooseNextNode(npc.Config, previous, current, walked, step, blocked)
		planned = nil
		if not nextNode then return "Idle", npc end

		local path = npc:ComputePath(nextNode.Position + Vector3.yAxis * PATROL_NODE_HEIGHT)
		local reached = false
		local upcoming = nil :: any

		if path then
			-- Marked on setting off rather than on arriving, because the corner after this one is chosen
			-- now -- while there is still a leg's worth of walking to work out its route in -- and a
			-- choice made without this corridor counted as walked is a choice that turns straight back
			-- down it. A leg that then fails is one it has genuinely just been on, which is what this
			-- record is for; the failure path deliberately keeps history for the same reason.
			markWalked(walked, current, nextNode, step)
			upcoming = chooseNextNode(npc.Config, current, nextNode, walked, step + 1, blocked)
			local nextGoal = upcoming and upcoming.Position + Vector3.yAxis * PATROL_NODE_HEIGHT

			reached = npc:WalkPatrolPath(path, nextGoal and function()
				return nextGoal
			end) == "Reached"
			path:Destroy()
		end

		if reached then
			previous, current = current, nextNode
			planned = upcoming
		else
			-- Blocked, shoved somewhere else, or aimed at a corner nothing can path to. Which of those
			-- it was is not knowable from here, so treat it as all three: the corner goes out of favour
			-- for a while, and where it thinks it is on the graph gets re-read from the world.
			--
			-- What does *not* get thrown away is what it has walked. Clearing that used to feel like the
			-- honest thing to do -- the position was wrong, so the history must be suspect too -- but the
			-- history is the only reason a patrol goes anywhere new, and a failed leg leaves an enemy
			-- somewhere it has genuinely just been rather than somewhere unknown. Wiping it hands the
			-- next choice to the danger field alone, and the danger field is a fixed function of
			-- position: it returns the same answer every time and walks the thing straight back the
			-- way it came. One awkward corner then reads as an enemy pacing its spawn forever.
			blocked[nextNode] = os.clock() + PATROL_BLOCKED_MEMORY
			task.wait(PATROL_BLOCKED_WAIT)

			local reacquired = HallwayGraphService:FindNearestNode(npc.RootPart.Position)
			if not reacquired then return "Idle", npc end

			-- Drifting to a different corner still crossed whatever lies between the two, so that counts
			-- as walked. Otherwise a stretch an enemy repeatedly half-completes stays permanently fresh
			-- and it keeps being drawn back onto it.
			if reacquired ~= current then
				markWalked(walked, current, reacquired, step)
				previous, current = current, reacquired
			end
		end
	end
end

--- Held in place for `duration` seconds, then dropped back to Idle. What the bear trap and the
--- paper ball put an enemy into; enter it with the `Impact` reason so it can cut off a chase.
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

--- Follows a player to the edge of a safe room, then celebrates the escape. It is shared for now so
--- the four pursuit enemies get the same test behavior; an enemy can replace this state when its
--- authored reaction is ready.
function NPC.SharedStates.RoomReaction(_changeState: StateMachine.ChangeState, npc: any, room: Model)
	npc.Target = nil
	if npc.StopMirroring then
		npc:StopMirroring()
	end
	npc:ReactAtRoomDoor(room)
	return "Patrol", npc
end

--- Terminal state: tears the NPC down and never resolves, so the machine stops here.
function NPC.SharedStates.Despawn(_changeState: StateMachine.ChangeState, npc: any)
	npc:Despawn()
	coroutine.yield()
end

return NPC
