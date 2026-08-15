--- @class Stalker
--- Walks behind you. It picks somebody, gets onto their back a few studs back and keeps station there
--- at exactly their own speed, so walking away is not an answer -- it is not chasing you, it is waiting
--- for you to keep not turning around. Left alone for `StrikeTime` it stops being patient, and the
--- charge that follows is faster than anything the follow suggested it could do. Nothing calls that off
--- once it starts.
---
--- The counter is turning your head, and the game being first person is what makes that a real cost:
--- there is no over-the-shoulder view to catch it in, so the only way to know it is there is to stop
--- looking where you are going. It follows close because of that rather than in spite of it -- when you
--- do turn round, it is already an arm's length away.
---
--- Looked at by anybody, it breaks away from whoever is looking and runs for the nearest cover
--- `HideSpotService` can offer. The run only has to carry it out of sight -- the moment nobody can see
--- it, it leaves entirely -- so it goes round the corner rather than to the far end of the building,
--- and every step of it is away from the eyes that caught it. Holding it in view for all of `FleeTime`
--- also forces it out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local EnemyDiscoveryService = require(ServerStorage.Services.EnemyDiscoveryService)
local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local HideSpotService = require(ServerStorage.Services.HideSpotService)
local NPC = require(ServerStorage.Classes.NPC)

local FaceStalker = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Enemies")
	:WaitForChild("FaceStalker") :: RemoteEvent

local PERCEPTION_INTERVAL = 0.25
local HOLD_INTERVAL = 0.1 -- seconds between checks while it stands on a target's back
local FOLLOW_HYSTERESIS = 2 -- extra studs a target must open up before a held follow starts moving again
local RETRY_INTERVAL = 0.25 -- seconds before trying for cover again when a retreat did not come off

-- Studs of straight-line ground it tries to put between itself and a watcher on the spot, longest
-- first. Several lengths because the clearance test is a blockcast down the whole span at the rig's
-- full width, and twenty studs of that is a thing a hotel corridor rarely has in any direction -- so
-- asking only for the long one is how it ends up with no goal at all, standing still through the third
-- of a second the pathfinder takes to answer. A short goal it can actually take beats a long one it
-- cannot, by the width of the entire problem.
local RETREAT_STEPS = { 20, 12, 6 }
local RETREAT_SPREAD = { 0, 30, -30, 60, -60, 90, -90 } -- degrees off dead-away, tried in order when blocked
local RETREAT_TIME = 0.6 -- seconds spent running blind before it looks for cover again
local MAX_BLIND_RETREAT = 2 -- and the longest that ever grows to, however often cover lies behind them
local HEADING_SPEED = 6 -- studs/s under which it is not going anywhere in particular
local RETREAT_REFRESH = 0.25 -- seconds between away-goals while the pathfinder is still thinking
-- How much of its current clearance a route is allowed to give back before it counts as heading for
-- somebody rather than away from them, and the ceiling on that in studs. A fraction rather than a
-- distance because the same route means opposite things from different starting points: three studs
-- off somebody is a corner being rounded when it begins six studs behind them, and is running at them
-- when it begins at the far end of the hallway.
local ROUTE_APPROACH_FRACTION = 0.5
local ROUTE_CLEARANCE = 12
local ROUTE_LOOKAHEAD = 30 -- studs of a route that have to lead away before it is committed to
local ROUTE_DETOUR_LIMIT = 1.7 -- times the straight line a route may be before it is going round somebody
local ROUTE_DETOUR_FLOOR = 15 -- studs under which that ratio means nothing: short routes bend for doorways
local MAX_RETREAT_ATTEMPTS = 5 -- legs in a row that gain no ground before a retreat gives up on its spot
local RETREAT_PROGRESS = 4 -- studs closer to the spot that makes an interrupted leg count as progress
local REPATH_WAIT = 0.1 -- seconds before a blocked retreat is re-pathed around whatever stopped it

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

--- The spot on `target`'s back it wants to stand on, along with where `target` actually is -- the
--- second is what it turns to face while it waits, which is not the same place. Both nil once they
--- stop being worth following.
function Stalker:_getFollowPosition(target: Player): (Vector3?, Vector3?)
	local position = self:GetTargetPosition(target)
	if not position then return nil, nil end

	local root = (target.Character :: Model).HumanoidRootPart :: BasePart
	local facing = flatten(root.CFrame.LookVector)
	if facing.Magnitude < 1e-3 then return position, position end
	return position - facing.Unit * self.Config.FollowDistance, position
end

-- Where the nearest pair of eyes is, and how far off they are. Nil when nobody is alive to look.
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

-- Whether a route sets off away from everybody, judged once and only over its first stretch.
--
-- A hiding place picked away from the eyes watching can still sit at the end of a loop whose only
-- entrance is back past them -- a dead-end hallway is exactly that, the way on is behind the person
-- looking -- and reading the opening of the route is what catches it before a step is taken.
--
-- Only the opening, for two reasons. In a maze this dense nearly every route brushes past the middle
-- somewhere, so judging the whole thing refuses all of them; and what happens forty studs along is
-- mostly hypothetical anyway, because the point of the run is to break the sight line, and once that
-- happens this is gone. What must not happen is setting off towards somebody.
--
-- Judged here rather than while running, because a rule applied mid-route turns the retreat round in
-- the middle of a corridor -- and a Stalker that keeps reversing reads as a broken one, whatever the
-- reversal was protecting. A route is committed to once it is taken.
--
-- The bar is a fraction of present clearance rather than a distance, because the same three studs mean
-- opposite things from different starting points: a corner being rounded when it begins an arm's
-- length behind somebody, and a charge when it begins at the far end of the hallway.
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

	-- And the length of the whole thing against the straight line to it, which is what catches the
	-- rest: a hiding place forty studs off that costs a hundred and forty studs of walking is one
	-- whose only entrance is somewhere else entirely, and in a corridor that somewhere else is back
	-- past the person looking. Cheap, and it needs no idea where anybody is -- a route that doubles
	-- back is a route that doubles back.
	local direct = (destination - origin).Magnitude
	return direct < ROUTE_DETOUR_FLOOR or travelled <= direct * ROUTE_DETOUR_LIMIT
end

-- Works out a route to `destination` without standing still for it. `PathfindingService` takes
-- anything from a tenth of a second to two seconds to answer in a hotel this size, and it yields, so
-- asking for a route on the thread that is supposed to be running is how a retreat ends up standing
-- in plain view thinking. The answer arrives on its own thread while this one keeps putting ground
-- between it and whoever is looking.
--
function Stalker:_computeWhileMoving(destination: Vector3, shouldStop: () -> boolean): Path?
	local path, finished = nil :: Path?, false
	task.spawn(function()
		path = self:ComputePath(destination)
		finished = true
	end)

	while not finished do
		-- Being done with the retreat mid-answer must not mean waiting for the answer: the whole point
		-- of a Stalker leaving is that it leaves the moment nobody can see it. The route it no longer
		-- wants is left to the thread still working it out, which tidies up after itself.
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

--- Runs to `destination` and keeps running to it: a leg that ends blocked is re-pathed from wherever
--- it stopped rather than handed back, so the retreat only ends by arriving, by no longer being
--- needed, or by genuinely having nowhere left to try.
---
--- That matters more here than anywhere else the chassis walks. The one thing certain to be near a
--- fleeing Stalker's route is the person it is fleeing, and a body moving next to the route sets off
--- Roblox's blocked signal on it -- so treating one blocked leg as a failed retreat means the retreats
--- most worth completing are the ones that get abandoned ten studs in. Only legs that gain no ground
--- count against it, which is what tells being shoved about in a doorway apart from being walked past.
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
			return "PastThem" -- somewhere else, rather than set off towards the person it is fleeing
		end

		-- The chassis watches this signal too, and abandons the leg on it. Listening as well is how a
		-- leg that ended obstructed is told from one that ended stalled, which is the whole difference
		-- between somebody having walked past and this having lost a shoving match with a door frame.
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

--- The immediate break, and the fallback when the floor around it offers nowhere to hide: one movement
--- goal set straight away from the nearest pair of eyes, or the nearest angle to it that is not a wall.
--- It is what keeps the first moment of being caught from being a pause -- the cover search runs on
--- this thread, and standing still through it in plain view is the one thing a Stalker must never do.
function Stalker:_retreatFrom(eye: Vector3): boolean
	local origin = self.RootPart.Position
	local away = flatten(origin - eye)
	if away.Magnitude < 1e-3 then return false end
	away = away.Unit

	-- Angle before length: a shorter step in a direction that is genuinely away beats a longer one
	-- that is merely sideways, and every one of these is replaced by a real route in a moment anyway.
	for _, degrees in RETREAT_SPREAD do
		local direction = CFrame.Angles(0, math.rad(degrees), 0) * away
		for _, step in RETREAT_STEPS do
			local goal = origin + direction * step
			-- The blockcast filters out only itself, so the watcher's own body counts as a wall here.
			-- That is exactly the rule wanted: no angle that runs through somebody is away from them.
			if self:HasMovementClearance(goal) then
				self.Humanoid:MoveTo(goal)
				return true
			end
		end
	end
	return false
end

--- Keeps station on `target`'s back for as long as it is allowed to. It ends three ways -- somebody
--- looked at it, it ran out of patience, or the target stopped being valid -- and which one it was is
--- the whole of what this state decides.
local function stalk(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	local config = npc.Config
	npc.Target = target
	npc.Animator:Resume()
	npc:SetSpeed(config.WalkSpeed)

	local strikeAt = os.clock() + randomRange(config.StrikeTimeMin, config.StrikeTimeMax)
	local targetPosition = npc.RootPart.Position
	local ending = nil :: string?

	-- Doubles as the follow goal and as the thing that ends the follow: `Pursue` lets go the moment
	-- this comes back nil, so every reason to stop being here is polled at the rate it walks at.
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
		-- `Pursue` reports letting go of the goal as "Lost", which is also what every reason to stop
		-- following looks like from in there. Out before the retry wait: reacting to having been seen is
		-- the one thing this must not sit on.
		if ending then break end

		if result == "Reached" then
			-- On their back with nowhere left to be. It holds there rather than shuffling into them,
			-- staring at the back of their head, and only takes the follow up again once they have
			-- walked far enough off that there is ground to make up.
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
			task.wait(config.RepathInterval) -- Blocked: no way onto their back from where it is standing
		end
	end

	if ending == "Seen" then return "Flee", npc end
	if ending == "Strike" then return "Reveal", npc, target end
	return "Idle", npc
end

--- Its patience runs out with an introduction, not an off-screen hit: hold still, turn the target's
--- camera around, let them understand what has been behind them, and only then begin the charge.
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

	-- Their camera is being turned onto it as this runs, so this is the first and only time a player
	-- gets a proper look at the thing that has been following them -- and the reason it carries no
	-- sighting rule. Catching it over your shoulder sends it fleeing before anybody could study it;
	-- what teaches you what it is, is it deciding to show you.
	EnemyDiscoveryService:GrantEvent(target, npc.EnemyId)

	task.wait(config.RevealTurnTime + config.RevealHoldTime)

	if not npc:GetTargetPosition(target) then
		releaseCamera(npc)
		return "Idle", npc
	end
	return "Chase", npc, target
end

--- Out of patience. Runs `target` down at a speed the follow gave no hint of, and being looked at stops
--- counting for anything the moment it commits.
local function chase(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	npc.Target = target
	npc.Animator:Resume()
	npc:SetSpeed(npc.Config.ChaseSpeed)

	local lastKnown = npc.RootPart.Position
	local result = npc:Pursue(function()
		local position = npc:GetTargetPosition(target)
		if position then
			lastKnown = position
		end
		return position
	end, npc.Config.AttackRange, function()
		return npc:IsTouchingPlayer(target)
	end, function()
		return npc:HasLineOfSightToPlayer(target)
	end)

	if result == "Reached" then
		return "Attack", npc, target
	end
	return "Search", npc, lastKnown
end

--- Lands the killing blow, or drops back to chasing if the target slipped out of reach first.
local function attack(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	npc:StopMoving()

	local position = npc:GetTargetPosition(target)
	if not position then
		return "Search", npc, npc.RootPart.Position
	end

	npc:FaceTowards(position)
	-- Reach, not contact: two humanoids that run into each other shove each other apart, so a strict
	-- touch test flickers off on the frame it lands and sends this back to `Chase` from a standstill.
	if (npc.RootPart.Position - position).Magnitude > npc.Config.AttackRange
		and not npc:IsTouchingPlayer(target)
	then
		return "Chase", npc, target
	end

	npc:Attack(target)
	npc.RevealTarget = nil -- the client releases on death; the server no longer owns a camera lock
	task.wait(npc.Config.AttackCooldown)
	return "Idle", npc
end

--- Caught. Backs off whoever is looking and runs for the nearest cover that breaks their line, over
--- and over until nothing can see it, and then it is gone. It is not trying to get away from anybody
--- -- it only has to stop being looked at -- so the goal each time is the closest spot out of sight
--- rather than the furthest spot on the map, which is both what it should look like and what keeps
--- the search cheap enough to repeat every couple of seconds.
---
--- If everybody somehow holds sight for `FleeTime`, it gives up and disappears in front of them.
local function flee(_changeState: StateMachine.ChangeState, npc: any)
	local config = npc.Config
	npc.Target = nil
	npc.Animator:Resume()
	npc:SetSpeed(config.FleeSpeed)

	local despawnAt = os.clock() + config.FleeTime
	local function shouldDespawn(): boolean
		return not npc:IsObserved() or os.clock() >= despawnAt
	end

	local options = { Range = config.FleeCoverRange, MinDistance = config.FleeCoverMinDistance }
	local pause = 0 -- seconds the last attempt asked for before another spot is worth looking for
	local turnedBack = 0 -- routes in a row that led back towards somebody

	local function retreatStep()
		local eye = getNearestEye(npc.RootPart.Position)
		if eye then
			npc:_retreatFrom(eye)
		end
	end

	-- Nothing in here may yield without a live movement goal, and that is the whole shape of the loop.
	-- A retreat is one continuous run made of several destinations -- reaching one hiding place while
	-- somebody can still see it means picking another, not arriving -- so every wait, every raycast of
	-- the cover search and every path compute has to happen with the legs already going. A quarter of a
	-- second standing between two spots is not a small pause, it is the thing that looks broken.
	while not shouldDespawn() do
		retreatStep() -- moving before it knows where to, so nothing after this costs ground

		-- The pause is not a wait, it is the blind retreat: a fresh goal directly away every quarter
		-- second for as long as it lasts. That is what it does instead of hunting for cover it has just
		-- been told it cannot use, and what turns a shuttle back and forth across a hallway into a run.
		if pause > 0 then
			local until_ = os.clock() + pause
			while os.clock() < until_ and not shouldDespawn() do
				task.wait(RETREAT_REFRESH)
				retreatStep()
			end
			if shouldDespawn() then break end
			pause = 0
		end

		-- The agent radius goes along because an unreachable hiding place does not read as a bad choice,
		-- it reads as a bug: the navmesh holds walkable ground a full radius off every wall, so a spot
		-- tucked any tighter than that is one nothing can be routed to.
		-- Where it is actually going, while it is going anywhere fast enough for that to mean something.
		-- Standing still it has no heading worth keeping, and its facing is not one: a rig that has just
		-- turned to look at a corner would otherwise pick its next hiding place out of that glance.
		local velocity = flatten(npc.RootPart.AssemblyLinearVelocity)
		options.Heading = if velocity.Magnitude > HEADING_SPEED then velocity else nil

		local spot = HideSpotService:Find(npc.RootPart.Position, config.AgentParams.AgentRadius, options)
		if not spot then
			-- Nowhere near it breaks the line. Keep running the blind way and ask again from there,
			-- which is a different question: cover is a thing you find by moving.
			pause = RETREAT_TIME
			continue
		end

		local from = npc.RootPart.Position
		local result = npc:_sprintTo(spot, shouldDespawn)

		-- The whole enemy hangs off this run working, and there is no way to tell from watching it
		-- whether a retreat that ended early ran out of map, out of navmesh or out of patience.
		if result == "NoPath" or result == "Stuck" or result == "Obstructed" then
			local covered = (npc.RootPart.Position - from).Magnitude
			warn(
				`[enemies] stalker retreat came up {result} `
					.. `after {math.floor(covered)} of {math.floor((spot - from).Magnitude)} studs`
			)
		end

		-- Straight into the next spot when it got to that one: still being seen there means the run is
		-- not over, and a run that is not over should not have a gap in it.
		--
		-- A route that turned back is the one worth answering differently. Somewhere behind the person
		-- looking is where the cover is, and no amount of asking again changes that -- what changes it
		-- is being somewhere else, so each turn back buys a longer blind run away before it looks
		-- again. Two of those and it is round the corner the hallway did not have.
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

--- Drops the target and resumes patrolling as soon as the chase ends.
local function search(_changeState: StateMachine.ChangeState, npc: any, _lastKnown: Vector3)
	releaseCamera(npc)
	npc.Target = nil
	npc.Animator:Resume()
	npc:SetSpeed(npc.Config.WalkSpeed)
	return "Patrol", npc
end

local function stunned(changeState: StateMachine.ChangeState, npc: any, duration: number)
	releaseCamera(npc)
	return NPC.SharedStates.Stunned(changeState, npc, duration)
end

function Stalker.new(model: Model, config)
	local self = NPC.new(model, config, Stalker)
	self.RevealTarget = nil
	return self
end

function Stalker:Start()
	-- No nameplate. A humanoid's name and health render through walls, so a caption hanging in the air
	-- over your shoulder while the thing itself is off the bottom of your screen would give away both
	-- the follow and every hiding place it ever picks.
	self.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	NPC.Start(self)
end

function Stalker:Despawn()
	releaseCamera(self)
	NPC.Despawn(self)
end

function Stalker:BuildStateMachine(): StateMachine.StateMachine
	local npc = self

	return StateMachine.new({
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
	}, {
		-- Picking somebody happens between jobs and never interrupts one.
		Perception = { "Idle", "Wander", "Patrol", "Search" },
		-- Being looked at outranks anything it does quietly. `Stalk` is left out on purpose: it watches
		-- for this itself, so that breaking off a follow is the follow's own business. `Chase` and
		-- `Attack` are left out because by then nobody's eyes matter any more.
		Seen = { "Idle", "Wander", "Patrol", "Search" },
		-- A trap or a paper ball lands whatever it is doing.
		Impact = { "Idle", "Wander", "Patrol", "Search", "Stalk", "Reveal", "Flee", "Chase", "Attack" },
	}, {
		Perception = function()
			while true do
				task.wait(PERCEPTION_INTERVAL)

				if npc:IsObserved() then
					npc.StateMachine:SetState("Flee", "Seen", npc)
					continue
				end

				-- No cone and no sight test: it comes at you from behind, so needing to have seen your
				-- face before it can pick you would be a rule about nothing.
				local target = npc:GetNearestTarget()
				if target then
					npc.StateMachine:SetState("Stalk", "Perception", npc, target)
				end
			end
		end,
	}, "Idle", self)
end

return Stalker
