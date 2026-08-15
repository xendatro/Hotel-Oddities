--- @class Mimic
--- Wears a player. It takes the name and avatar of someone already in the server when it spawns, and
--- of whoever it kills after that, so the copy is always of a face you have seen.
---
--- Its tell is meant to be behavioural rather than visual, which is why it does not charge on sight
--- like a `Chaser`. Each encounter rolls one act: delayed key-copying, emotes, periodic spinning, or
--- an AFK stance that slowly notices somebody who lingers. This half owns the act and every chase;
--- only the key-copying movement is handed to the copied player's client, where it can arrive smooth.
---
--- Contact alone is never an attack. Entering its close range or retreating after engaging starts a real
--- chase; the Mimic still has to catch the player before it can kill them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local MimicConfig = require(ReplicatedStorage.Configs.MimicConfig)
local MimicMotion = require(ReplicatedStorage.Modules.MimicMotion)
local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local EnemyDiscoveryService = require(ServerStorage.Services.EnemyDiscoveryService)
local NPC = require(ServerStorage.Classes.NPC)
local RoomService = require(ServerStorage.Services.RoomService)

local PERCEPTION_INTERVAL = 0.25
local SUPERVISE_INTERVAL = 0.1 -- how often the act is re-examined while the client does the moving
local LOOK_AROUND_DISTANCE = 10
local SIGHT_GRACE = 1.5 -- seconds it will keep mirroring a target it can no longer see
local NOTICED_ANGLE = 65 -- degrees within which a target counts as having looked at the mimic
local HANDBACK_SWEEP_DELAY = 0.5 -- generous room for a round trip; see `StopMirroring`
local AFK_SETTLE_POLL = 0.05
local AFK_DRIFT_REACHED = 1 -- studs of the settling step left that count as having taken it
local AFK_DRIFT_TIMEOUT = 2.5 -- and how long it is given before that is called close enough
local AFK_SETTLE_TURN_TIMEOUT = 6 -- a slow turn is still a turn; nothing waits on one for ever

local Mirror = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Enemies")
	:WaitForChild("Mirror") :: RemoteEvent

local Mimic = NPC.extend("Mimic")

local ENCOUNTER_MODES = { "Mirror", "Emote", "Spin", "Afk" }
local HEAD_TURN_ATTRIBUTE = "MimicHeadTurnTarget"
local HEAD_TURN_DURATION_ATTRIBUTE = "MimicHeadTurnDuration"

local function randomRange(minimum: number, maximum: number): number
	return minimum + math.random() * (maximum - minimum)
end

local function flatten(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

-- Degrees between two directions, ignoring height.
local function angleBetween(from: Vector3, to: Vector3): number
	local a, b = flatten(from), flatten(to)
	if a.Magnitude < 1e-3 or b.Magnitude < 1e-3 then return 0 end
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end

local function headRotation(npc: any, position: Vector3): CFrame
	local relative = npc.RootPart.CFrame:VectorToObjectSpace(position - npc.RootPart.Position)
	local horizontal = Vector3.new(relative.X, 0, relative.Z)
	if horizontal.Magnitude < 1e-3 then return CFrame.identity end

	local yaw = math.clamp(math.atan2(-relative.X, -relative.Z), -math.rad(80), math.rad(80))
	local pitch = math.clamp(
		math.atan2(relative.Y, horizontal.Magnitude),
		-math.rad(35),
		math.rad(35)
	)
	return CFrame.Angles(-pitch, yaw, 0)
end

local function isFleeing(npc: any, player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return false end

	local away = flatten(root.Position - npc.RootPart.Position)
	local velocity = flatten(root.AssemblyLinearVelocity)
	return away.Magnitude > 1e-3
		and velocity.Magnitude >= npc.Config.RunSpeed
		and velocity.Unit:Dot(away.Unit) >= 0.35
end

local function isRetreating(npc: any, player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return false end

	local away = flatten(root.Position - npc.RootPart.Position)
	local velocity = flatten(root.AssemblyLinearVelocity)
	return away.Magnitude > 1e-3
		and velocity.Magnitude >= npc.Config.RetreatSpeed
		and velocity:Dot(away.Unit) >= npc.Config.RetreatSpeed
end

local function newEncounter(npc: any)
	return {
		Closest = math.huge,
		CloseSince = nil :: number?,
		LastDistance = math.huge,
		LastKnown = npc.RootPart.Position,
		LostSightAt = nil :: number?,
		Noticed = false,
		TurnedAwayAt = nil :: number?,
		Engaged = false,
	}
end

--- Shared engagement rules for the three player-facing acts. The close threshold starts pursuit;
--- it is not the attack hitbox, so the Mimic still has to catch the player.
local function updateEncounter(npc: any, target: Player, encounter: any): string?
	local position = npc:GetTargetPosition(target)
	if not position then return "Idle" end

	local now = os.clock()
	local distance = flatten(npc.RootPart.Position - position).Magnitude
	encounter.LastKnown = position
	encounter.Closest = math.min(encounter.Closest, distance)

	if distance <= npc.Config.EngageRange then
		encounter.Engaged = true
		if distance <= npc.Config.StrikeRange then
			encounter.CloseSince = encounter.CloseSince or now
			if now - encounter.CloseSince >= npc.Config.CloseTime then
				return "Chase"
			end
		else
			encounter.CloseSince = nil
		end
	else
		encounter.CloseSince = nil
	end

	if encounter.Engaged
		and isRetreating(npc, target)
		and distance <= (npc.Config.RunawayRange or npc.Config.EngageRange)
	then
		return "Chase"
	end

	if encounter.Engaged
		and distance - encounter.Closest >= npc.Config.RetreatSlack
		and isRetreating(npc, target)
	then
		return "Chase"
	end

	if npc:HasLineOfSightToPlayer(target) then
		encounter.LostSightAt = nil
	else
		encounter.LostSightAt = encounter.LostSightAt or now
		if now - encounter.LostSightAt >= SIGHT_GRACE then
			return "Search"
		end
	end

	-- The character can go between the position read at the top of this and here -- a death, a respawn --
	-- and an act that errors out of its own state leaves the mimic standing in a corridor for good.
	local character = target.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return "Idle" end

	local away = angleBetween(root.CFrame.LookVector, npc.RootPart.Position - position)
	if away <= NOTICED_ANGLE then
		encounter.Noticed, encounter.TurnedAwayAt = true, nil
	elseif encounter.Engaged and encounter.Noticed and away >= npc.Config.TurnAwayAngle then
		encounter.TurnedAwayAt = encounter.TurnedAwayAt or now
		if now - encounter.TurnedAwayAt >= npc.Config.TurnAwayGrace and isFleeing(npc, target) then
			return "Chase"
		end
	else
		encounter.TurnedAwayAt = nil
	end

	encounter.LastDistance = distance
	if distance > npc.Config.DetectionRange then return "Idle" end
	return nil
end

local function findBystander(npc: any, excluded: Player): Player?
	local nearest, nearestDistance = nil, npc.Config.BystanderRange
	for _, player in Players:GetPlayers() do
		if player ~= excluded and npc:IsValidTarget(player) and npc:HasLineOfSightToPlayer(player) then
			local position = npc:GetTargetPosition(player)
			local distance = position and flatten(npc.RootPart.Position - position).Magnitude
			if distance and distance <= nearestDistance then
				nearest, nearestDistance = player, distance
			end
		end
	end
	return nearest
end

local function findNearbyPlayer(npc: any): Player?
	local player = npc:GetNearestTarget()
	if not player then return nil end

	local position = npc:GetTargetPosition(player)
	if position and flatten(npc.RootPart.Position - position).Magnitude <= npc.Config.DetectionRange then
		return player
	end
	return nil
end

--- The copied player owns the rig, so the server takes it back for the brief turn toward a second
--- player. If that player leaves, the original act resumes; if they run once the turn is half done,
--- this is a real chase rather than a contact kill.
local function watchBystander(npc: any, excluded: Player, state: any): (string?, Player?)
	local candidate = findBystander(npc, excluded)
	if not candidate then
		if state.Player then
			state.Player = nil
			npc:SetHeadTurn(nil)
			if npc:IsValidTarget(excluded) then npc:StartMirroring(excluded) end
		end
		return nil, nil
	end

	local now = os.clock()
	if state.Player ~= candidate then
		state.Player = candidate
		state.NoticedAt = now
		state.TurnStartedAt = nil
		npc:StopMirroring()
		npc:SetSpeed(npc.Config.WalkSpeed)
		npc:StopMoving()
	end

	if now - state.NoticedAt < npc.Config.BystanderNoticeTime then return nil, nil end

	local position = npc:GetTargetPosition(candidate)
	if not position then
		state.Player = nil
		npc:SetHeadTurn(nil)
		return nil, nil
	end

	state.TurnStartedAt = state.TurnStartedAt or now
	npc:SetHeadTurn(position, npc.Config.BystanderTurnTime)
	local progress = math.clamp(
		(now - state.TurnStartedAt) / npc.Config.BystanderTurnTime,
		0,
		1
	)

	if progress >= npc.Config.BystanderChaseTurnFraction and isFleeing(npc, candidate) then
		return "Chase", candidate
	end
	if progress >= 0.995 then return "Chase", candidate end
	return nil, nil
end

local function finishEncounter(npc: any, nextState: string, ...: any)
	npc.EncounterMode = nil
	npc:SetHeadTurn(nil)
	npc:StopMirroring()
	return nextState, npc, ...
end

--- Stands around the way a player does between decisions: turning to look at something, hopping for
--- no reason. A humanoid holding perfectly still is the fastest way to read as an NPC.
local function loiter(_changeState: StateMachine.ChangeState, npc: any)
	npc.Target = nil
	npc.EncounterMode = nil
	npc.Animator:Resume()
	npc:StopMirroring()
	npc:SetSpeed(npc.Config.WalkSpeed)
	npc:StopMoving()

	local config = npc.Config
	local until_ = os.clock() + randomRange(config.IdleTimeMin, config.IdleTimeMax)
	local lookAt = npc.RootPart.Position + npc.RootPart.CFrame.LookVector * LOOK_AROUND_DISTANCE
	local nextGlanceAt = 0

	local deltaTime = RunService.Heartbeat:Wait()
	while os.clock() < until_ do
		local now = os.clock()
		if now >= nextGlanceAt then
			local angle = math.rad(randomRange(-config.GlanceAngle, config.GlanceAngle) * 2)
			local look = CFrame.Angles(0, angle, 0) * npc.RootPart.CFrame.LookVector
			lookAt = npc.RootPart.Position + look * LOOK_AROUND_DISTANCE
			nextGlanceAt = now + randomRange(config.GlanceInterval, config.GlanceInterval * 2)

			if math.random() < config.IdleJumpChance then
				npc.Humanoid.Jump = true
			end
		end

		npc.RootPart.CFrame = MimicMotion.Turn(npc.RootPart.CFrame, lookAt - npc.RootPart.Position, deltaTime)
		deltaTime = RunService.Heartbeat:Wait()
	end

	return finishEncounter(npc, config.IdleNextState)
end

local function mirror(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	npc.Target = target
	npc.Animator:Resume()
	npc:SetSpeed(npc.Config.WalkSpeed)
	npc:StopMoving()
	npc:StartMirroring(target)

	local encounter = newEncounter(npc)
	local bystander = {}
	while true do
		local result = updateEncounter(npc, target, encounter)
		if result == "Chase" then return "Chase", npc, target end
		if result == "Search" then return "Search", npc, encounter.LastKnown end
		if result == "Idle" then return finishEncounter(npc, "Idle") end
		local bystanderState, bystanderTarget = watchBystander(npc, target, bystander)
		if bystanderState then return "Chase", npc, bystanderTarget end
		task.wait(SUPERVISE_INTERVAL)
	end
end

local function lookAndPerform(
	_changeState: StateMachine.ChangeState,
	npc: any,
	target: Player,
	mode: string
)
	npc.Target = target
	npc:StopMirroring()
	npc.Animator:Resume()
	npc:SetSpeed(npc.Config.WalkSpeed)
	npc:StopMoving()
	local position = npc:GetTargetPosition(target)
	local turningToTarget = position ~= nil

	local encounter = newEncounter(npc)
	local nextEmoteAt = os.clock() + randomRange(MimicConfig.ModeEmoteDelayMin, MimicConfig.ModeEmoteDelayMax)
	local nextSpinAt = os.clock() + randomRange(MimicConfig.SpinDelayMin, MimicConfig.SpinDelayMax)
	local spinUntil = 0

	while true do
		local result = updateEncounter(npc, target, encounter)
		if result == "Chase" then return "Chase", npc, target end
		if result == "Search" then return "Search", npc, encounter.LastKnown end
		if result == "Idle" then return finishEncounter(npc, "Idle") end

		position = npc:GetTargetPosition(target)
		if not position then return finishEncounter(npc, "Idle") end
		local now = os.clock()
		if turningToTarget and spinUntil <= now then
			local look = position - npc.RootPart.Position
			npc.RootPart.CFrame = MimicMotion.Turn(
				npc.RootPart.CFrame,
				look,
				SUPERVISE_INTERVAL,
				MimicConfig.InteractionTurnRate
			)
			turningToTarget = angleBetween(npc.RootPart.CFrame.LookVector, look)
				> MimicConfig.InteractionTurnTolerance
		end

		if mode == "Emote" then
			npc:SetHeadTurn(nil)
			if not turningToTarget and now >= nextEmoteAt then
				npc.Animator:PlayEmote()
				nextEmoteAt = now + randomRange(MimicConfig.ModeEmoteDelayMin, MimicConfig.ModeEmoteDelayMax)
			end
		elseif spinUntil > now then
			npc:SetHeadTurn(nil)
		elseif spinUntil > 0 then
			npc:StopMirroring()
			spinUntil = 0
			turningToTarget = true
			nextSpinAt = now + randomRange(MimicConfig.SpinDelayMin, MimicConfig.SpinDelayMax)
		elseif not turningToTarget and now >= nextSpinAt then
			npc:SetHeadTurn(nil)
			spinUntil = now + MimicConfig.SpinDuration
			npc:StartSpinning(target)
		else
			npc:SetHeadTurn(nil)
		end
		task.wait(SUPERVISE_INTERVAL)
	end
end

local function findWallDirection(npc: any, target: Player?): Vector3
	local origin = npc.RootPart.Position
	local targetPosition = target and npc:GetTargetPosition(target)
	local away = targetPosition and flatten(origin - targetPosition)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { npc.Model }
	if target and target.Character then
		table.insert(params.FilterDescendantsInstances, target.Character)
	end
	params.RespectCanCollide = true

	local bestDirection, bestDistance = nil, math.huge
	for index = 0, 7 do
		local direction = CFrame.Angles(0, index * math.pi / 4, 0) * npc.RootPart.CFrame.LookVector
		direction = flatten(direction).Unit
		if away and direction:Dot(away.Unit) < 0.25 then continue end
		local hit = workspace:Raycast(origin, direction * npc.Config.AfkWallDistance, params)
		if hit and (hit.Position - origin).Magnitude < bestDistance then
			bestDirection, bestDistance = direction, (hit.Position - origin).Magnitude
		end
	end

	return bestDirection or if away and away.Magnitude > 1e-3 then away.Unit else -npc.RootPart.CFrame.LookVector
end

-- A couple of steps off the middle of the corridor. Walked rather than pathed: this is two or three
-- studs of drift, and asking the navmesh for it would cost more standing still than the whole move is
-- worth. Skipped entirely if there is anything in the way, since the point is to look unhurried.
local function driftAside(npc: any)
	local cframe = npc.RootPart.CFrame
	-- Weighted forward, because this is a walk that wandered rather than a sidestep. `AutoRotate` turns
	-- the body onto whatever it ends up walking, so the mix is also how far off its old heading it
	-- comes to rest: mostly-sideways would have it finishing square across the corridor.
	local direction = flatten(
		cframe.RightVector * (if math.random() < 0.5 then -1 else 1) * randomRange(0.3, 0.7)
			+ cframe.LookVector * randomRange(0.6, 1)
	)
	if direction.Magnitude < 1e-3 then return end
	direction = direction.Unit

	local distance = randomRange(npc.Config.AfkDriftMin, npc.Config.AfkDriftMax)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { npc.Model }
	params.RespectCanCollide = true
	local reach = distance + npc.Config.AgentParams.AgentRadius
	if workspace:Raycast(npc.RootPart.Position, direction * reach, params) then return end

	local goal = npc.RootPart.Position + direction * distance
	npc.Humanoid:MoveTo(goal)

	local until_ = os.clock() + AFK_DRIFT_TIMEOUT
	while flatten(npc.RootPart.Position - goal).Magnitude > AFK_DRIFT_REACHED
		and os.clock() < until_
	do
		task.wait(AFK_SETTLE_POLL)
	end
end

-- Round to `direction` at an idle pace. Everything the mimic does to its own facing goes through
-- `MimicMotion.Turn` for the same reason: a rotation that lands in a single frame is the one thing in
-- the whole act that could not have been done by somebody holding a mouse.
local function turnSlowly(npc: any, direction: Vector3)
	local deltaTime = RunService.Heartbeat:Wait()
	local until_ = os.clock() + AFK_SETTLE_TURN_TIMEOUT
	while angleBetween(npc.RootPart.CFrame.LookVector, direction) > MimicConfig.InteractionTurnTolerance
		and os.clock() < until_
	do
		npc.RootPart.CFrame = MimicMotion.Turn(
			npc.RootPart.CFrame,
			direction,
			deltaTime,
			npc.Config.AfkSettleTurnRate
		)
		deltaTime = RunService.Heartbeat:Wait()
	end
end

--- Comes to rest the way somebody does when they stop paying attention, rather than arriving at a
--- pose. Whatever it was walking carries on for a step or two off the centre line, and only some
--- encounters turn to face anything at all -- the rest stop where the last step left them, which is
--- what being interrupted mid-corridor actually looks like.
---
--- The snap this replaces was the worst tell the Mimic had. Every other part of the act is judged over
--- seconds and can be argued with; a body that changes heading between one frame and the next is not a
--- player at any speed, and anybody walking behind it saw the whole thing happen.
local function afkIdle(_changeState: StateMachine.ChangeState, npc: any)
	npc.Target = nil
	npc:StopMirroring()
	npc.Animator:Resume()
	npc:SetSpeed(npc.Config.WalkSpeed)

	if math.random() < npc.Config.AfkDriftChance then
		driftAside(npc)
	end
	npc:StopMoving()
	npc:SetSpeed(0)

	if math.random() < npc.Config.AfkFaceWallChance then
		turnSlowly(npc, findWallDirection(npc, nil))
	end

	while true do
		task.wait(SUPERVISE_INTERVAL)
	end
end

local function afk(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	npc.Target = target
	npc:StopMirroring()
	npc.Animator:Resume()
	npc:SetSpeed(npc.Config.WalkSpeed)
	npc:StopMoving()

	local config = npc.Config
	local noticedAt = nil :: number?
	local turnStartedAt = nil :: number?
	local watchingSince = nil :: number? -- when its head first came off the wall; never unset in here

	while true do
		local position = npc:GetTargetPosition(target)
		if not position then return finishEncounter(npc, "Idle") end

		local now = os.clock()
		local distance = flatten(position - npc.RootPart.Position).Magnitude
		if distance > config.DetectionRange then return finishEncounter(npc, "Idle") end

		if distance <= config.AfkNoticeRange then
			noticedAt = noticedAt or now
		elseif distance > config.AfkNoticeRange + 6 then
			-- Backing off buys off the charge it was working up to. It does not buy back the attention:
			-- a head that swings home the moment you retreat is the mechanism announcing itself, where
			-- one that stays on you is a guest who has clocked you and has not decided what to do about
			-- it yet. Only the encounter ending puts the head back, which `finishEncounter` does.
			noticedAt, turnStartedAt = nil, nil
		end

		local noticing = noticedAt ~= nil and now - (noticedAt :: number) >= config.AfkNoticeTime
		if noticing then
			watchingSince = watchingSince or now
		end

		if watchingSince then
			-- The first turn is the slow one it was authored to be. Once it has had that long to come
			-- round, it keeps up with a moving player at an ordinary glance rather than trailing them by
			-- most of a turn -- which is what following somebody actually looks like.
			npc:SetHeadTurn(position, if now - watchingSince >= config.AfkTurnTime
				then MimicConfig.HeadTurnDefaultDuration
				else config.AfkTurnTime)
		end

		if noticing then
			turnStartedAt = turnStartedAt or now
			local progress = math.clamp((now - (turnStartedAt :: number)) / config.AfkTurnTime, 0, 1)
			if progress >= config.AfkChaseTurnFraction and isFleeing(npc, target) then
				return "Chase", npc, target
			end
			if progress >= 0.995 then return "Chase", npc, target end
			RunService.Heartbeat:Wait()
		else
			task.wait(SUPERVISE_INTERVAL)
		end
	end
end

local function stalk(changeState: StateMachine.ChangeState, npc: any, target: Player)
	if npc.EncounterMode == "Emote" then return lookAndPerform(changeState, npc, target, "Emote") end
	if npc.EncounterMode == "Spin" then return lookAndPerform(changeState, npc, target, "Spin") end
	if npc.EncounterMode == "Afk" then return afk(changeState, npc, target) end
	return mirror(changeState, npc, target)
end

--- The act is over. Runs `target` down until it is caught, reaches a safe room, or outruns `GiveUpRange`.
local function chase(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	npc.Target = target
	npc:StopMirroring() -- takes the rig, and its animation, back before anything is asked of either
	-- And claims it, which `StopMirroring` only does for an act that had actually been handed out. An
	-- unanchored humanoid standing next to somebody is given to that player's machine by default, and a
	-- chase run from here against a rig simulated over there is a `MoveTo` that has to fly out and a
	-- position that arrives back late: the pursuit judges its progress on stale ground, calls legs
	-- stalled that were not, and the run comes out as a series of lunges. The acts that never mirror --
	-- the emote, the spin, the AFK stance -- are the ones that reached a chase still owned by the player
	-- they were chasing, which is exactly where that stutter was.
	npc:SetNetworkOwner(nil)
	npc.Animator:Resume()
	npc:SetSpeed(npc.Config.ChaseSpeed)

	-- The act it is dropping has had it standing still for a while, so the first route of the chase can
	-- be worked out during the moment it takes to drop it rather than after. `ComputeAsync` is the one
	-- thing here that can take the better part of a second, and spending it stood in front of somebody
	-- who has just started running is most of what a chase that opens badly actually is.
	local start = npc:GetTargetPosition(target)
	if start then
		npc:PrefetchPath(start)
	end

	-- The only moment a player can be said to have met a Mimic. Everything before this looked like
	-- another guest, which is why `DiscoveryConfig` gives this one no sighting rule at all: unlocking
	-- its card for having looked at it would print the word "Mimic" in the index before the disguise
	-- had ever worked on anybody. It is discovered by dropping the act, or by killing you, and by
	-- nothing else.
	EnemyDiscoveryService:GrantEvent(target, npc.EnemyId)

	local lastKnown = npc.RootPart.Position
	local safeRoom = nil :: Model?
	local result = npc:Pursue(function()
		if RoomService:IsInRoom(target) then
			safeRoom = RoomService:GetRoom(target)
			return nil
		end
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
	npc.EncounterMode = nil
	if safeRoom then
		return "RoomReaction", npc, safeRoom
	end
	return "Search", npc, lastKnown
end

--- Lands the killing blow and puts on the victim, or drops back to chasing if they slipped out of reach.
local function attack(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	npc:StopMirroring()
	npc:StopMoving()

	local position = npc:GetTargetPosition(target)
	if not position then
		npc.EncounterMode = nil
		return "Search", npc, npc.RootPart.Position
	end

	-- Reach, not contact. Two humanoids that run into each other shove each other apart, so a strict
	-- touch test flickers off the moment it lands -- which sends this straight back to `Chase` to
	-- re-path from a standstill, and reads as the mimic pulling up next to you and hesitating.
	if (npc.RootPart.Position - position).Magnitude > npc.Config.AttackRange
		and not npc:IsTouchingPlayer(target)
	then
		-- Going straight back out is the one bounce this cannot avoid, so it does not also pay for a
		-- route from a standstill: the chase it returns to starts with one already in hand.
		npc:PrefetchPath(position)
		return "Chase", npc, target
	end

	npc:Attack(target)
	npc:AssumeIdentity(target)
	task.wait(npc.Config.AttackCooldown)
	return finishEncounter(npc, "Idle")
end

--- Drops the target and resumes patrolling as soon as the chase ends.
local function search(_changeState: StateMachine.ChangeState, npc: any, _lastKnown: Vector3)
	npc.Target = nil
	npc.Animator:Resume()
	npc:StopMirroring()
	npc:SetSpeed(npc.Config.WalkSpeed)
	return "Patrol", npc
end

local function roomReaction(changeState: StateMachine.ChangeState, npc: any, room: Model)
	npc.EncounterMode = nil
	return NPC.SharedStates.RoomReaction(changeState, npc, room)
end

--- Held still by a trap or a paper ball. Takes the rig back first: a stunned mimic that a client is
--- still driving would keep swivelling on the spot.
local function stunned(changeState: StateMachine.ChangeState, npc: any, duration: number)
	npc.EncounterMode = nil
	npc:StopMirroring()
	return NPC.SharedStates.Stunned(changeState, npc, duration)
end

function Mimic.new(model: Model, config)
	local self = NPC.new(model, config, Mimic)

	self.Identity = nil :: Player?
	self.Mirroring = nil :: Player?
	self.MirroringMode = nil :: string?
	self.EncounterMode = nil :: string?
	self._nextAfkRollAt = os.clock() + randomRange(3, 6)
	self._appliedIdentity = nil :: Player?
	self._swapping = false
	self.Model:SetAttribute("MimicHeadTurn", true)
	self.Model:SetAttribute(HEAD_TURN_ATTRIBUTE, CFrame.identity)
	self.Model:SetAttribute(HEAD_TURN_DURATION_ATTRIBUTE, MimicConfig.HeadTurnDefaultDuration)

	return self
end

--- Movement -------------------------------------------------------------------------------------

function Mimic:SetHeadTurn(position: Vector3?, duration: number?)
	local target = if position then headRotation(self, position) else CFrame.identity
	local turnDuration = duration or MimicConfig.HeadTurnDefaultDuration
	self.Model:SetAttribute(HEAD_TURN_ATTRIBUTE, target)
	self.Model:SetAttribute(HEAD_TURN_DURATION_ATTRIBUTE, turnDuration)
end

--- Hands `target`'s own client the job of moving this mimic, and the rig to simulate it with. Their
--- machine knows their input on the frame they make it and renders the answer on the frame it
--- simulates it, which is the only way the mirroring arrives smooth on the screen that matters.
---
--- Only the act is delegated. Damage, the decision to charge, and the chase itself stay here, so the
--- worst a client that refuses to play along gets is a mimic that stands there until it charges.
function Mimic:_StartClientControl(target: Player, mode: string)
	if self.Mirroring == target and self.MirroringMode == mode then return end

	self:StopMirroring()
	self:SetHeadTurn(nil)
	self.Mirroring = target
	self.MirroringMode = mode
	self.Humanoid.AutoRotate = false -- the client aims it by hand, at the person it is copying
	if mode ~= "Spin" then
		self.Animator:Stop() -- mirrored locomotion is animated where its speed is known that frame
	end
	self:SetNetworkOwner(target)
	Mirror:FireClient(target, self.Model, mode)
end

function Mimic:StartMirroring(target: Player)
	self:_StartClientControl(target, "Mirror")
end

function Mimic:StartSpinning(target: Player)
	self:_StartClientControl(target, "Spin")
end

--- Takes the rig back. Safe to call when nothing is mirroring, which is why every other state opens
--- with it: a state can be cancelled mid-act, so this cannot live at the end of the stalk.
function Mimic:StopMirroring()
	self:SetHeadTurn(nil)
	self.Humanoid.AutoRotate = true
	if not self.Mirroring then return end

	local target = self.Mirroring
	self.Mirroring = nil
	self.MirroringMode = nil
	Mirror:FireClient(target, nil) -- ahead of the rest, so it stops driving at the first moment it can
	self:SetNetworkOwner(nil)
	self.Animator:Start()
	-- Whatever that client was playing is still on the rig and it can no longer stop it, ownership
	-- having gone. Left there it blends against the chase this hands back to, which is a mimic that
	-- charges you without ever putting its legs into it.
	--
	-- Swept twice, because the clip it started on its last frame of ownership is still on the wire
	-- while this runs, and nothing that arrives after the first sweep is ever cleared by it.
	self.Animator:ClearForeignTracks()
	task.delay(HANDBACK_SWEEP_DELAY, function()
		if self.Active and not self.Mirroring then
			self.Animator:ClearForeignTracks()
		end
	end)
end

--- Identity -------------------------------------------------------------------------------------

-- A player's live appearance, straight off their character where possible so the copy matches what
-- everyone in the server has actually been looking at.
local function getDescription(player: Player): HumanoidDescription?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if humanoid then
		local ok, description = pcall(humanoid.GetAppliedDescription, humanoid)
		if ok then return description end
	end

	local ok, description = pcall(Players.GetHumanoidDescriptionFromUserId, Players, player.UserId)
	return if ok then description else nil
end

--- Someone worth impersonating: preferably a player this mimic cannot currently see, so it does not
--- change face in front of the person it is copying. Falls back to anyone alive.
function Mimic:PickIdentity(): Player?
	local unseen, anyone = {}, {}

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
		if humanoid and humanoid.Health > 0 and player ~= self.Identity then
			table.insert(anyone, player)
			if not self:CanSee(player) then
				table.insert(unseen, player)
			end
		end
	end

	local candidates = if #unseen > 0 then unseen else anyone
	return if #candidates > 0 then candidates[math.random(#candidates)] else nil
end

--- Takes `player`'s name and avatar. Applying the description yields on asset loads, so the swap runs
--- off the state machine's thread -- a state cancelled mid-swap would leave a half-dressed mimic. A
--- second identity arriving during a swap is picked up by the same thread rather than racing it.
function Mimic:AssumeIdentity(player: Player)
	self.Identity = player
	if self._swapping then return end
	self._swapping = true

	task.spawn(function()
		while self.Active and self.Identity and self.Identity ~= self._appliedIdentity do
			local identity = self.Identity :: Player
			self.Model.Name = identity.Name
			self.Humanoid.DisplayName = identity.DisplayName

			local description = getDescription(identity)
			if description then
				pcall(self.Humanoid.ApplyDescription, self.Humanoid, description)
				self.Animator:Reload() -- the description may have brought its own animation package
			end
			self._appliedIdentity = identity
		end
		self._swapping = false
	end)
end

--- Lifecycle ------------------------------------------------------------------------------------

function Mimic:Start()
	NPC.Start(self)

	local identity = self:PickIdentity()
	if identity then
		self:AssumeIdentity(identity)
	end
end

function Mimic:RollEncounterMode(allowAfk: boolean?): string
	if allowAfk ~= false then return ENCOUNTER_MODES[math.random(#ENCOUNTER_MODES)] end
	return ENCOUNTER_MODES[math.random(#ENCOUNTER_MODES - 1)]
end

function Mimic:Despawn()
	self:StopMirroring()
	NPC.Despawn(self)
end

function Mimic:BuildStateMachine(): StateMachine.StateMachine
	local npc = self

	return StateMachine.new({
		Idle = loiter,
		AfkIdle = afkIdle,
		Wander = NPC.SharedStates.Wander,
		Patrol = NPC.SharedStates.Patrol,
		Despawn = NPC.SharedStates.Despawn,
		Stalk = stalk,
		Chase = chase,
		Attack = attack,
		Search = search,
		RoomReaction = roomReaction,
		Stunned = stunned,
	}, {
		-- Spotting someone starts the act, but nothing interrupts the act except the act ending.
		Perception = { "Idle", "Wander", "Patrol", "Search", "AfkIdle" },
		-- A trap or a paper ball lands whatever it is doing, including mid-performance.
		Impact = { "Idle", "AfkIdle", "Wander", "Patrol", "Search", "Stalk", "Chase", "Attack", "RoomReaction" },
	}, {
		Perception = function()
			while true do
				task.wait(PERCEPTION_INTERVAL)

				-- Spawning into an empty server, or before anyone has loaded, leaves it wearing its
				-- own face; it puts one on as soon as there is one to take.
				if not npc.Identity then
					local identity = npc:PickIdentity()
					if identity then
						npc:AssumeIdentity(identity)
					end
				end

				local target = npc:GetNearestVisibleTarget()
				local state = npc.StateMachine.State
				local canStartEncounter = state == "Idle"
					or state == "Wander"
					or state == "Patrol"
					or state == "Search"

				if target and state == "AfkIdle" and npc.EncounterMode == "Afk" then
					npc.StateMachine:SetState("Stalk", "Perception", npc, target)
				elseif target and npc.EncounterMode and state == "Search" then
					-- Losing sight briefly does not roll another act when the same interaction resumes.
					npc.StateMachine:SetState("Stalk", "Perception", npc, target)
				elseif target and not npc.EncounterMode and canStartEncounter then
					-- AFK is an ambient stance, so a player already nearby cannot cause a fresh AFK
					-- encounter. The other three modes are locked for the whole interaction.
					npc.EncounterMode = npc:RollEncounterMode(false)
					npc.StateMachine:SetState("Stalk", "Perception", npc, target)
				elseif not target
					and not npc.EncounterMode
					and canStartEncounter
					and not findNearbyPlayer(npc)
					and os.clock() >= npc._nextAfkRollAt
				then
					npc._nextAfkRollAt = os.clock()
						+ randomRange(npc.Config.AfkAmbientRollMin, npc.Config.AfkAmbientRollMax)
					if math.random() < npc.Config.AfkAmbientChance then
						npc.EncounterMode = "Afk"
						npc.StateMachine:SetState("AfkIdle", "Perception", npc)
					end
				end
			end
		end,
	}, "Idle", self)
end

return Mimic
