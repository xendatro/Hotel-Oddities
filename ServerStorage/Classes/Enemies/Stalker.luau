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
--- Looked at by anybody, it breaks and runs toward the furthest hidden point `HideSpotService` can
--- offer. The run only has to carry it beyond everybody's sight: the moment nobody can see it, it
--- leaves entirely. Holding it in view for all of `FleeTime` also forces it out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local EnemyDiscoveryService = require(ServerStorage.Services.EnemyDiscoveryService)
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
local SPRINT_POLL = 0.05 -- seconds between movement checks on a long run
local SPRINT_REACHED_DISTANCE = 2 -- studs of a waypoint that counts as having got there
local SPRINT_PROGRESS = 0.5 -- studs of gain on a waypoint that counts as making ground
local SPRINT_STUCK_GRACE = 1.5 -- seconds of making none before a run is called stuck
local MOVE_REFRESH = 4 -- seconds between re-issued goals; `Humanoid:MoveTo` gives up after eight
local LOOK_AROUND_DISTANCE = 10 -- studs out in front the search glances are aimed

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

--- Walks one computed path to `destination` the whole way, however long that takes. Returns "Reached",
--- "NoPath" where the map would not produce a route, "Stuck" where it stopped making ground, or
--- "Abandoned" where `shouldStop` cut it short.
---
--- `NPC:Pursue` is the obvious thing to use here and it is the wrong shape for it. Pursue is built to
--- chase somebody: it re-paths as they move, and it allows each waypoint twice its *estimated* travel
--- time before calling the path blocked. That estimate is `distance / WalkSpeed`, which is a guess at
--- physics -- fair for a target ten studs off, a coin toss for a hundred-stud corridor. Guess low and
--- the retreat becomes the one thing a retreat cannot be: a short run, a stall, a re-path, another
--- short run.
---
--- So there is no clock in here. It gives up when it stops making ground, which is the only thing worth
--- giving up over, and it re-issues its goal often enough that Roblox's own eight-second `MoveTo`
--- cutoff never lands halfway along a corridor.
function Stalker:_sprintTo(destination: Vector3, shouldStop: () -> boolean): string
	local path = self:ComputePath(destination)
	if not path then return "NoPath" end

	local waypoints = self:GetMovementWaypoints(path)
	path:Destroy()

	for index = 2, #waypoints do
		local waypoint = waypoints[index]
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			self.Humanoid.Jump = true
		end

		self.Humanoid:MoveTo(waypoint.Position)
		local closest = math.huge
		local progressedAt = os.clock()
		local refreshAt = os.clock() + MOVE_REFRESH

		while true do
			local distance = self:GetWaypointDistance(waypoint.Position)
			if distance <= SPRINT_REACHED_DISTANCE then break end
			if shouldStop() then return "Abandoned" end

			if distance < closest - SPRINT_PROGRESS then
				closest, progressedAt = distance, os.clock()
			elseif os.clock() - progressedAt >= SPRINT_STUCK_GRACE then
				return "Stuck"
			end

			if os.clock() >= refreshAt then
				refreshAt = os.clock() + MOVE_REFRESH
				self.Humanoid:MoveTo(waypoint.Position)
			end
			task.wait(SPRINT_POLL)
		end
	end

	return "Reached"
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

--- Caught. Sprints toward hidden ground until it actually leaves every player's view, then disappears.
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

	while not shouldDespawn() do
		-- The agent radius goes along because an unreachable hiding place does not read as a bad choice,
		-- it reads as a bug: the navmesh holds walkable ground a full radius off every wall, so a spot
		-- tucked any tighter than that is one nothing can be routed to.
		local spot = HideSpotService:Find(npc.Config.AgentParams.AgentRadius)
		if spot then
			local from = npc.RootPart.Position
			local result = npc:_sprintTo(spot, function()
				return shouldDespawn()
			end)

			-- The whole enemy hangs off this run working, and there is no way to tell from watching it
			-- whether a retreat that ended early ran out of map, out of navmesh or out of patience.
			if result == "NoPath" or result == "Stuck" then
				local covered = (npc.RootPart.Position - from).Magnitude
				warn(
					`[enemies] stalker retreat came up {result} `
						.. `after {math.floor(covered)} of {math.floor((spot - from).Magnitude)} studs`
				)
			end
		end

		-- No path, or it reached that point while somebody could still see it. Try another while watched.
		if shouldDespawn() then break end
		task.wait(RETRY_INTERVAL)
	end

	return "Despawn", npc
end

--- Sweeps the spot a target got away from and has a look round it, which is the one thing it does that
--- is not either patient or violent. Turning up nothing, it goes quiet and starts again on whoever is
--- nearest.
local function search(_changeState: StateMachine.ChangeState, npc: any, lastKnown: Vector3)
	releaseCamera(npc)
	npc.Target = nil
	npc.Animator:Resume()
	npc:SetSpeed(npc.Config.WalkSpeed)
	npc:WalkTo(lastKnown)
	npc:StopMoving()

	local until_ = os.clock() + npc.Config.LoseInterestTime
	while os.clock() < until_ do
		local offset = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * LOOK_AROUND_DISTANCE
		npc:FaceTowards(npc.RootPart.Position + offset)
		task.wait(npc.Config.SearchLookInterval)
	end

	return "Idle", npc
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
