--- @class NPC
--- Base chassis for every enemy: locomotion, perception, combat, and lifecycle. Behaviour lives in
--- the `StateMachine` a subclass returns from `BuildStateMachine` -- states are what the NPC is
--- doing, evaluators are perception loops that run alongside them, and the reasons table decides
--- which interruptions may override which states. A wandering horror, a set-path patroller and an
--- ambient prop are all the same chassis with different states and a different config.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local NpcAnimator = require(ServerStorage.Classes.NpcAnimator)
local RoomService = require(ServerStorage.Services.RoomService)

local WAYPOINT_TIMEOUT_SCALE = 2 -- multiple of the ideal travel time before a waypoint is abandoned
local WAYPOINT_TIMEOUT_PADDING = 0.75
local WAYPOINT_REACHED_DISTANCE = 2
local STRAIGHT_PATH_DOT_THRESHOLD = 0.98
local MOVEMENT_POLL_INTERVAL = 0.05
local CONTACT_PADDING = 0.25
local CONTACT_ROOT_DISTANCE = 2.25
local DIRECT_PURSUIT_DISTANCE = 15
local DIRECT_PURSUIT_UPDATE_DISTANCE = 1
local DIRECT_PURSUIT_OVERSHOOT = 4
local MAX_BLOCKED_ATTEMPTS = 3 -- consecutive stalled paths before a pursuit gives up
local WANDER_ATTEMPTS = 6

local ENEMY_TAG = "Enemy" -- carried by every live enemy model, so tools can raycast for them
local IGNORE_TAG = "Ignore" -- on a character: enemies cannot target or see them (the spell book)

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
	self.Animator = NpcAnimator.new(model)
	self.HomePosition = model:GetPivot().Position
	self.Target = nil :: Player?
	self.Active = false
	self.StateMachine = self:BuildStateMachine()

	return self
end

--- Returns this NPC's behaviour. Subclasses override this; the base is a harmless wanderer.
function NPC:BuildStateMachine(): StateMachine.StateMachine
	return StateMachine.new({
		Idle = NPC.SharedStates.Idle,
		Wander = NPC.SharedStates.Wander,
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

	ByModel[self.Model] = nil
	self.Model:RemoveTag(ENEMY_TAG)

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

--- Turns to face a point without moving. Yaw only.
function NPC:FaceTowards(position: Vector3)
	local origin = self.RootPart.Position
	local flat = Vector3.new(position.X, origin.Y, position.Z)
	if (flat - origin).Magnitude < 1e-3 then return end
	self.RootPart.CFrame = CFrame.lookAt(origin, flat)
end

--- A computed path to `destination`, or nil if none exists. Callers own the returned path.
function NPC:ComputePath(destination: Vector3): Path?
	local path = PathfindingService:CreatePath(self.Config.AgentParams)
	local ok = pcall(path.ComputeAsync, path, self.RootPart.Position, destination)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		path:Destroy()
		return nil
	end
	return path
end

-- Removes intermediate waypoints from straight stretches so the Humanoid does not brake every few
-- studs. Corners and special actions remain explicit movement goals.
local function getMovementWaypoints(path: Path)
	local waypoints = path:GetWaypoints()
	if #waypoints <= 2 then return waypoints end

	local simplified = { waypoints[1] }
	for index = 2, #waypoints - 1 do
		local previous = simplified[#simplified]
		local current = waypoints[index]
		local nextWaypoint = waypoints[index + 1]
		local incoming = current.Position - previous.Position
		local outgoing = nextWaypoint.Position - current.Position
		local isStraight = current.Action == Enum.PathWaypointAction.Walk
			and nextWaypoint.Action == Enum.PathWaypointAction.Walk
			and incoming.Magnitude > 1e-3
			and outgoing.Magnitude > 1e-3
			and incoming.Unit:Dot(outgoing.Unit) >= STRAIGHT_PATH_DOT_THRESHOLD

		if not isStraight then
			table.insert(simplified, current)
		end
	end
	table.insert(simplified, waypoints[#waypoints])
	return simplified
end

-- Walks the waypoints of `path`, polling `shouldAbandon` between each. Returns "Reached" once the
-- last waypoint lands, "Abandoned" if the caller bailed out, or "Blocked" if a waypoint timed out.
function NPC:_walkPath(path: Path, shouldAbandon: (() -> boolean)?): string
	local waypoints = getMovementWaypoints(path)
	for index = 2, #waypoints do
		if shouldAbandon and shouldAbandon() then return "Abandoned" end

		local waypoint = waypoints[index]
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			self.Humanoid.Jump = true
		end

		local distance = (waypoint.Position - self.RootPart.Position).Magnitude
		local timeout = distance / math.max(self.Humanoid.WalkSpeed, 1) * WAYPOINT_TIMEOUT_SCALE + WAYPOINT_TIMEOUT_PADDING
		local expiresAt = os.clock() + timeout

		self.Humanoid:MoveTo(waypoint.Position)
		while (waypoint.Position - self.RootPart.Position).Magnitude > WAYPOINT_REACHED_DISTANCE do
			if shouldAbandon and shouldAbandon() then return "Abandoned" end
			if os.clock() >= expiresAt then return "Blocked" end
			task.wait(MOVEMENT_POLL_INTERVAL)
		end
	end
	return "Reached"
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
function NPC:Pursue(
	getGoal: () -> Vector3?,
	arriveDistance: number,
	hasArrived: (() -> boolean)?,
	canMoveDirectly: (() -> boolean)?
): string
	local blockedAttempts = 0
	local directGoal = nil :: Vector3?

	while true do
		local goal = getGoal()
		if not goal then return "Lost" end
		if hasArrived and hasArrived() then return "Reached" end

		local distance = (self.RootPart.Position - goal).Magnitude
		if distance <= arriveDistance then return "Reached" end
		if distance <= DIRECT_PURSUIT_DISTANCE and canMoveDirectly and canMoveDirectly() then
			blockedAttempts = 0
			if not directGoal or (goal - directGoal).Magnitude >= DIRECT_PURSUIT_UPDATE_DISTANCE then
				directGoal = goal
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

		local path = self:ComputePath(goal)
		if not path then
			blockedAttempts += 1
			if blockedAttempts >= MAX_BLOCKED_ATTEMPTS then return "Blocked" end
			task.wait(self.Config.RepathInterval)
			continue
		end

		local repathAt = os.clock() + self.Config.RepathInterval
		local arrived = false
		local result = self:_walkPath(path, function()
			local current = getGoal()
			if not current then return true end
			if hasArrived and hasArrived() then
				arrived = true
				return true
			end
			if (self.RootPart.Position - current).Magnitude <= arriveDistance then return true end
			return os.clock() >= repathAt and (current - goal).Magnitude > self.Config.RepathDistance
		end)
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
	return root ~= nil and self:HasLineOfSight(root)
end

--- Whether a player is worth pursuing at all: alive, out of a safe room, and still in range.
--- Deliberately ignores facing and sight, so an acquired target cannot be shaken by ducking behind
--- a corner -- only by reaching a room or outrunning `GiveUpRange`.
function NPC:IsValidTarget(player: Player): boolean
	local root = getAliveRoot(player)
	if not root then return false end
	if (root.Parent :: Model):HasTag(IGNORE_TAG) then return false end
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
	if (root.Parent :: Model):HasTag(IGNORE_TAG) then return false end
	if self.Config.RespectsSafeRooms and RoomService:IsInRoom(player) then return false end

	local origin = self.RootPart.Position
	if (root.Position - origin).Magnitude > self.Config.DetectionRange then return false end
	if not isWithinCone(origin, self.RootPart.CFrame.LookVector, root.Position, self.Config.FieldOfView) then
		return false
	end
	return self:HasLineOfSight(root)
end

--- Whether a player's client reports any visible portion of this NPC on screen. Reports identify
--- server-created enemy models and expire quickly; range remains server-authoritative.
function NPC:IsObservedBy(player: Player): boolean
	local root = getAliveRoot(player)
	if not root then return false end

	local boundsCFrame, boundsSize = self.Model:GetBoundingBox()
	local destination = boundsCFrame.Position
	local radius = boundsSize.Magnitude / 2
	if (destination - root.Position).Magnitude - radius > (self.Config.ObservationRange :: number) then return false end
	return EnemyObservationService:IsObservedBy(player, self.Model)
end

--- Whether any player is looking at this NPC.
function NPC:IsObserved(): boolean
	for _, player in Players:GetPlayers() do
		if self:IsObservedBy(player) then
			return true
		end
	end
	return false
end

-- Nearest player satisfying `predicate`, if any.
function NPC:_findNearest(predicate: (Player) -> boolean): Player?
	local nearest, nearestDistance = nil, math.huge
	local origin = self.RootPart.Position

	for _, player in Players:GetPlayers() do
		local root = getAliveRoot(player)
		if root and predicate(player) then
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

	local humanoid = (root.Parent :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid
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

--- Held in place for `duration` seconds, then dropped back to Idle. What the bear trap and the
--- paper ball put an enemy into; enter it with the `Impact` reason so it can cut off a chase.
function NPC.SharedStates.Stunned(_changeState: StateMachine.ChangeState, npc: any, duration: number)
	npc.Target = nil
	npc:SetSpeed(0)
	npc:StopMoving()
	npc.Animator:Pause()

	task.wait(duration)

	npc.Animator:Resume()
	return "Idle", npc
end

--- Terminal state: tears the NPC down and never resolves, so the machine stops here.
function NPC.SharedStates.Despawn(_changeState: StateMachine.ChangeState, npc: any)
	npc:Despawn()
	coroutine.yield()
end

return NPC
