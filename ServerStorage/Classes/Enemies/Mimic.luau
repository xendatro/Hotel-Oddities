local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local AnimationConfig = require(ReplicatedStorage.Configs.AnimationConfig)
local MimicConfig = require(ReplicatedStorage.Configs.MimicConfig)
local MimicMotion = require(ReplicatedStorage.Modules.MimicMotion)
local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local MathService = require(ReplicatedStorage.Services.MathService)
local Chaser = require(ServerStorage.Classes.Enemies.Chaser)
local EnemyDiscoveryService = require(ServerStorage.Services.EnemyDiscoveryService)
local HallwayGraphService = require(ServerStorage.Services.HallwayGraphService)
local NPC = require(ServerStorage.Classes.NPC)
local RoomService = require(ServerStorage.Services.RoomService)

local PERCEPTION_INTERVAL = 0.25
local SUPERVISE_INTERVAL = 0.1
local LOOK_AROUND_DISTANCE = 10
local SIGHT_GRACE = 1.5
local NOTICED_ANGLE = 65
local HANDBACK_SWEEP_DELAY = 0.5
local AFK_SETTLE_POLL = 0.05
local AFK_DRIFT_REACHED = 1
local AFK_DRIFT_TIMEOUT = 2.5
local AFK_SETTLE_TURN_TIMEOUT = 6

local Mirror = CommunicationService.Get("Enemies", "Mirror") :: RemoteEvent
local Reveal = CommunicationService.Get("Enemies", "MimicReveal") :: RemoteEvent

local Mimic = NPC.extend("Mimic", Chaser)

local ENCOUNTER_MODES = { "Withdraw", "Shadow", "Wallface", "Turnaway", "Passerby", "Blocker", "Afk" }
local RADIO_TOOL_NAME = "Walkie Talkie"
local VERIFIED_GLYPH = 0xE000

local HEAD_LOCK_ATTRIBUTE = "MimicHeadLockUserId"
local ATTACK_ACTIVE_ATTRIBUTE = "MimicAttackActive"
local CHASE_TARGET_ATTRIBUTE = "ChaseTargetUserId"

local randomRange = MathService.RandomRange
local flatten = MathService.Horizontal

local function angleBetween(from: Vector3, to: Vector3): number
	local a, b = flatten(from), flatten(to)
	if a.Magnitude < 1e-3 or b.Magnitude < 1e-3 then return 0 end
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
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

local function updateEncounter(npc: any, target: Player, encounter: any): string?
	local position = npc:GetTargetPosition(target)
	if not position then return "Idle" end

	local now = os.clock()
	local distance = flatten(npc.RootPart.Position - position).Magnitude
	encounter.LastKnown = position
	encounter.Closest = math.min(encounter.Closest, distance)

	if encounter.Noticed and distance <= npc.Config.EngageRange then
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

local function isNearOccupiedRoom(npc: any): boolean
	return RoomService:IsNearOccupiedRoom(
		npc.RootPart.Position,
		npc.Config.AfkRoomBuffer or npc.Config.AfkNoticeRange
	)
end

local function watchBystander(npc: any, excluded: Player, state: any): (string?, Player?)
	local candidate = findBystander(npc, excluded)
	if not candidate then
		if state.Player then
			state.Player = nil
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
		return nil, nil
	end

	state.TurnStartedAt = state.TurnStartedAt or now
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
	npc:ClearFacing()
	npc.EncounterMode = nil
	npc._revealed = false
	npc.Model:SetAttribute(CHASE_TARGET_ATTRIBUTE, nil)
	npc.Animator:StopOverride()
	npc:StopFloat()
	npc:SetAttackActive(false)
	npc:SetHeadLock(nil)
	npc:StopMirroring()
	return nextState, npc, ...
end

local function beginEncounter(npc: any, target: Player, speed: number?)
	npc.Target = target
	npc:SetAttackActive(false)
	npc:StopMirroring()
	npc:SetHeadLock(nil)
	npc.Animator:Resume()
	npc:SetSpeed(speed or npc.Config.WalkSpeed)
end

local function endEncounter(npc: any, target: Player, encounter: any, outcome: string?)
	npc:ClearFacing()
	if outcome == "Chase" then return "Chase", npc, target end
	if outcome == "Search" then return "Search", npc, encounter.LastKnown end
	return finishEncounter(npc, "Idle")
end

local function loiter(_changeState: StateMachine.ChangeState, npc: any)
	npc.Target = nil
	npc.EncounterMode = nil
	npc:SetAttackActive(false)
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
	npc:SetAttackActive(false)
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

local function graphGoal(npc: any, score: (Vector3) -> number): Vector3?
	local start = HallwayGraphService:FindNearestNode(npc.RootPart.Position)
	if not start then return nil end

	local best, bestScore = nil, -math.huge
	local function consider(node: any)
		if node == start then return end
		local value = score(node.Position)
		if value > bestScore then best, bestScore = node, value end
	end

	for neighbor in start.Neighbors do
		consider(neighbor)
		for far in neighbor.Neighbors do
			consider(far)
		end
	end

	return best and best.Position
end

local function withdraw(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	beginEncounter(npc, target, npc.Config.RetreatSpeed or npc.Config.WalkSpeed)

	local encounter = newEncounter(npc)
	local outcome = nil :: string?
	local goal = nil :: Vector3?

	local function watch(): Vector3?
		local result = updateEncounter(npc, target, encounter)
		if result then
			outcome = result
			return nil
		end

		local position = npc:GetTargetPosition(target)
		if not position then
			outcome = "Idle"
			return nil
		end

		npc:SetFacing(position - npc.RootPart.Position)

		if flatten(npc.RootPart.Position - position).Magnitude >= MimicConfig.WithdrawGap then
			goal = nil
			return nil
		end

		if not goal or flatten(npc.RootPart.Position - goal).Magnitude < 4 then
			goal = graphGoal(npc, function(candidate: Vector3)
				return (candidate - position).Magnitude
			end)
		end
		return goal
	end

	while outcome == nil do
		if watch() == nil and outcome ~= nil then break end
		if goal then
			npc:Pursue(watch, 4)
		else
			npc:StopMoving()
			task.wait(SUPERVISE_INTERVAL)
		end
	end

	return endEncounter(npc, target, encounter, outcome)
end

local function shadow(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	beginEncounter(npc, target)

	local encounter = newEncounter(npc)
	local outcome = nil :: string?

	local function watch(): Vector3?
		local result = updateEncounter(npc, target, encounter)
		if result then
			outcome = result
			return nil
		end

		local position = npc:GetTargetPosition(target)
		if not position then
			outcome = "Idle"
			return nil
		end

		npc:SetFacing(position - npc.RootPart.Position)
		return position
	end

	while outcome == nil do
		local result = npc:Pursue(watch, MimicConfig.ShadowGap)
		if outcome ~= nil then break end

		if result == "Reached" then
			npc:StopMoving()
			task.wait(SUPERVISE_INTERVAL)
		end
	end

	return endEncounter(npc, target, encounter, outcome)
end

local function approach(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	beginEncounter(npc, target)

	local encounter = newEncounter(npc)
	local outcome = nil :: string?

	local function watch(): Vector3?
		local result = updateEncounter(npc, target, encounter)
		if result then
			outcome = result
			return nil
		end
		return npc:GetTargetPosition(target)
	end

	local result = npc:Pursue(watch, MimicConfig.ApproachStopDistance)

	while result == "Reached" and outcome == nil do
		npc:StopMoving()
		npc:SetHeadLock(target)
		if watch() == nil then break end
		task.wait(SUPERVISE_INTERVAL)
	end

	return endEncounter(npc, target, encounter, outcome)
end

local function lookAndPerform(
	_changeState: StateMachine.ChangeState,
	npc: any,
	target: Player,
	mode: string
)
	npc.Target = target
	npc:SetAttackActive(false)
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
			npc:SetHeadLock(nil)
			if not turningToTarget and now >= nextEmoteAt then
				npc.Animator:PlayEmote()
				nextEmoteAt = now + randomRange(MimicConfig.ModeEmoteDelayMin, MimicConfig.ModeEmoteDelayMax)
			end
		elseif spinUntil > now then
			npc:SetHeadLock(nil)
		elseif spinUntil > 0 then
			npc:StopMirroring()
			spinUntil = 0
			turningToTarget = true
			nextSpinAt = now + randomRange(MimicConfig.SpinDelayMin, MimicConfig.SpinDelayMax)
		elseif not turningToTarget and now >= nextSpinAt then
			npc:SetHeadLock(nil)
			spinUntil = now + MimicConfig.SpinDuration
			npc:StartSpinning(target)
		else
			npc:SetHeadLock(nil)
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

local function driftAside(npc: any)
	local cframe = npc.RootPart.CFrame
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

local function standing(npc: any, target: Player, pose: (Vector3) -> Vector3?)
	local encounter = newEncounter(npc)
	local outcome = nil :: string?

	beginEncounter(npc, target)
	npc:StopMoving()

	while true do
		local result = updateEncounter(npc, target, encounter)
		if result then
			outcome = result
			break
		end

		local position = npc:GetTargetPosition(target)
		if not position then break end

		local direction = pose(position)
		if not direction then break end
		npc:SetFacing(direction)

		npc:StopMoving()
		task.wait(SUPERVISE_INTERVAL)
	end

	return endEncounter(npc, target, encounter, outcome)
end

local function wallface(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	local wall = findWallDirection(npc, target)
	return standing(npc, target, function()
		return wall
	end)
end

local function turnaway(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	return standing(npc, target, function(position: Vector3)
		local toward = position - npc.RootPart.Position
		return if npc:IsObserved() then -toward else toward
	end)
end

local function passerby(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	beginEncounter(npc, target)
	npc:ClearFacing()

	local encounter = newEncounter(npc)
	local outcome = nil :: string?
	local goal = nil :: Vector3?

	local function watch(): Vector3?
		local result = updateEncounter(npc, target, encounter)
		if result then
			outcome = result
			return nil
		end

		local position = npc:GetTargetPosition(target)
		if not position then
			outcome = "Idle"
			return nil
		end

		if not goal then
			local origin = npc.RootPart.Position
			local through = flatten(position - origin)
			if through.Magnitude < 1e-3 then
				outcome = "Idle"
				return nil
			end
			through = through.Unit

			goal = graphGoal(npc, function(candidate: Vector3)
				local offset = flatten(candidate - origin)
				if offset.Magnitude < 1e-3 then return -math.huge end
				return offset:Dot(through)
			end)
		end
		return goal
	end

	while outcome == nil do
		if watch() == nil then break end
		if npc:Pursue(watch, 4) == "Reached" then goal = nil end
	end

	return endEncounter(npc, target, encounter, outcome)
end

local function blocker(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	beginEncounter(npc, target)

	local encounter = newEncounter(npc)
	local outcome = nil :: string?
	local goal = nil :: Vector3?

	local function watch(): Vector3?
		local result = updateEncounter(npc, target, encounter)
		if result then
			outcome = result
			return nil
		end

		local position = npc:GetTargetPosition(target)
		if not position then
			outcome = "Idle"
			return nil
		end

		npc:SetFacing(position - npc.RootPart.Position)

		if not goal then
			local root = target.Character and target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local heading = root and flatten(root.AssemblyLinearVelocity)
			if not heading or heading.Magnitude < 1 then
				heading = root and flatten(root.CFrame.LookVector)
			end
			if not heading or heading.Magnitude < 1e-3 then return nil end
			heading = heading.Unit

			goal = graphGoal(npc, function(candidate: Vector3)
				local offset = flatten(candidate - position)
				if offset.Magnitude < 1e-3 then return -math.huge end
				return offset:Dot(heading) - offset.Magnitude * 0.25
			end)
		end
		return goal
	end

	while outcome == nil do
		if watch() == nil and outcome ~= nil then break end
		if goal then
			if npc:Pursue(watch, 4) == "Reached" then
				npc:StopMoving()
				task.wait(SUPERVISE_INTERVAL)
			end
		else
			npc:StopMoving()
			task.wait(SUPERVISE_INTERVAL)
		end
	end

	return endEncounter(npc, target, encounter, outcome)
end

local function afkIdle(_changeState: StateMachine.ChangeState, npc: any)
	npc.Target = nil
	npc:SetAttackActive(false)
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

	local until_ = os.clock() + randomRange(npc.Config.AfkIdleTimeMin, npc.Config.AfkIdleTimeMax)

	while os.clock() < until_ do
		if isNearOccupiedRoom(npc) then return finishEncounter(npc, "Patrol") end
		task.wait(SUPERVISE_INTERVAL)
	end

	npc._nextAfkRollAt = os.clock()
		+ randomRange(npc.Config.AfkPatrolTimeMin, npc.Config.AfkPatrolTimeMax)
	return finishEncounter(npc, "Patrol")
end

local function findAfkPlayers(npc: any): { Player }
	local players: { Player } = {}
	for _, player in Players:GetPlayers() do
		local position = npc:GetTargetPosition(player)
		if position
			and flatten(position - npc.RootPart.Position).Magnitude <= npc.Config.DetectionRange
		then
			table.insert(players, player)
		end
	end
	return players
end

local function afk(_changeState: StateMachine.ChangeState, npc: any, _target: Player?)
	npc.Target = nil
	npc:SetAttackActive(false)
	npc:StopMirroring()
	npc.Animator:Resume()
	npc:SetSpeed(npc.Config.WalkSpeed)
	npc:StopMoving()

	local config = npc.Config
	npc:SetHeadLock(nil)
	local encounters: { [Player]: { NoticedAt: number?, TurnStartedAt: number? } } = {}

	while true do
		if isNearOccupiedRoom(npc) then return finishEncounter(npc, "Patrol") end
		local now = os.clock()
		local activeNoticing = false
		local winner: Player? = nil
		local winnerAt: number? = nil
		local seen: { [Player]: boolean } = {}

		for _, player in findAfkPlayers(npc) do
			seen[player] = true
			local encounter = encounters[player]
			if not encounter then
				encounter = { NoticedAt = nil, TurnStartedAt = nil }
				encounters[player] = encounter
			end

			local position = npc:GetTargetPosition(player)
			if not position then continue end
			local distance = flatten(position - npc.RootPart.Position).Magnitude
			if distance <= config.AfkNoticeRange then
				encounter.NoticedAt = encounter.NoticedAt or now
			elseif distance > config.AfkNoticeRange + 6 then
				encounter.NoticedAt, encounter.TurnStartedAt = nil, nil
			end

			local noticing = encounter.NoticedAt ~= nil
				and now - (encounter.NoticedAt :: number) >= config.AfkNoticeTime
			if not noticing then continue end
			activeNoticing = true
			encounter.TurnStartedAt = encounter.TurnStartedAt or now
			local turnStartedAt = encounter.TurnStartedAt :: number
			local progress = math.clamp(
				(now - turnStartedAt) / config.AfkTurnTime,
				0,
				1
			)

			local triggerAt = nil :: number?
			if progress >= config.AfkChaseTurnFraction and isFleeing(npc, player) then
				triggerAt = now
			elseif progress >= 0.995 then
				triggerAt = turnStartedAt + config.AfkTurnTime * 0.995
			end
			if triggerAt and (winnerAt == nil or triggerAt < winnerAt) then
				winner, winnerAt = player, triggerAt
			end
		end

		for player in encounters do
			if not seen[player] then encounters[player] = nil end
		end

		if winner then return "Chase", npc, winner end
		if not next(seen) then return finishEncounter(npc, "Idle") end
		if activeNoticing then
			RunService.Heartbeat:Wait()
		else
			task.wait(SUPERVISE_INTERVAL)
		end
	end
end

local function stalk(changeState: StateMachine.ChangeState, npc: any, target: Player?)
	if npc.EncounterMode == "Afk" then return afk(changeState, npc, target) end
	if not target then return finishEncounter(npc, "Idle") end
	if npc.EncounterMode == "Emote" then return lookAndPerform(changeState, npc, target, "Emote") end
	if npc.EncounterMode == "Spin" then return lookAndPerform(changeState, npc, target, "Spin") end
	if npc.EncounterMode == "Approach" then return approach(changeState, npc, target) end
	if npc.EncounterMode == "Withdraw" then return withdraw(changeState, npc, target) end
	if npc.EncounterMode == "Shadow" then return shadow(changeState, npc, target) end
	if npc.EncounterMode == "Wallface" then return wallface(changeState, npc, target) end
	if npc.EncounterMode == "Turnaway" then return turnaway(changeState, npc, target) end
	if npc.EncounterMode == "Passerby" then return passerby(changeState, npc, target) end
	if npc.EncounterMode == "Blocker" then return blocker(changeState, npc, target) end
	return mirror(changeState, npc, target)
end

local function chase(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	npc.Target = target
	npc:SetAttackActive(true)
	npc:StopMirroring()
	npc:SetNetworkOwner(nil)
	npc.Animator:Resume()
	npc.Model:SetAttribute(CHASE_TARGET_ATTRIBUTE, target.UserId)

	local start = npc:GetTargetPosition(target)
	if start then
		npc:PrefetchPath(start)
	end

	if not npc._revealed then
		npc._revealed = true
		npc:SetSpeed(0)
		npc:StopMoving()
		npc.Animator:PlayOverride(AnimationConfig.Animations.Fly)
		npc:StartFloat()
		npc:SetHeadLock(target)
		Reveal:FireClient(target, npc.Model)
		task.wait(MimicConfig.RevealHoldTime)
		npc:SetHeadLock(nil)
	end

	EnemyDiscoveryService:GrantEvent(target, npc.EnemyId)

	local nextState, _, argument = Chaser.Chase(_changeState, npc, target, false)
	if nextState ~= "Attack" then
		npc.EncounterMode = nil
		npc._revealed = false
	end
	return nextState, npc, argument
end

local function attack(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	npc:StopMirroring()

	local position = npc:GetTargetPosition(target)
	if not position then
		npc.EncounterMode = nil
		return "Search", npc, npc.RootPart.Position
	end

	if (npc.RootPart.Position - position).Magnitude > npc.Config.AttackRange
		and not npc:IsTouchingPlayer(target)
	then
		npc:PrefetchPath(position)
		return "Chase", npc, target
	end

	npc:Attack(target)
	npc:AssumeIdentity(target)
	task.wait(npc.Config.AttackCooldown)
	return finishEncounter(npc, "Idle")
end

local function search(_changeState: StateMachine.ChangeState, npc: any, _lastKnown: Vector3)
	npc.Target = nil
	npc._revealed = false
	npc.Model:SetAttribute(CHASE_TARGET_ATTRIBUTE, nil)
	npc.Animator:StopOverride()
	npc:StopFloat()
	npc:SetAttackActive(false)
	npc.Animator:Resume()
	npc:StopMirroring()
	npc:SetSpeed(npc.Config.WalkSpeed)
	return "Patrol", npc
end

local function stunned(changeState: StateMachine.ChangeState, npc: any, duration: number)
	npc.EncounterMode = nil
	npc._revealed = false
	npc.Model:SetAttribute(CHASE_TARGET_ATTRIBUTE, nil)
	npc.Animator:StopOverride()
	npc:StopFloat()
	npc:SetAttackActive(false)
	npc:StopMirroring()
	return NPC.SharedStates.Stunned(changeState, npc, duration)
end

function Mimic.new(model: Model, config)
	local self = NPC.new(model, config, Mimic)

	self.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	self.Humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged

	self.Identity = nil :: Player?
	self.Mirroring = nil :: Player?
	self.MirroringMode = nil :: string?
	self.EncounterMode = nil :: string?
	self._revealed = false
	self._baseHipHeight = nil :: number?
	self._floatTween = nil :: Tween?
	self._floatBob = nil :: RBXScriptConnection?
	self._chaseFace = nil :: Model?
	self.Model:SetAttribute(ATTACK_ACTIVE_ATTRIBUTE, false)
	self._nextAfkRollAt = os.clock()
		+ randomRange(config.AfkPatrolTimeMin, config.AfkPatrolTimeMax) * math.random()
	self._facingAlign = nil :: AlignOrientation?
	self._appliedIdentity = nil :: Player?
	self._swapping = false
	self.Model:SetAttribute(HEAD_LOCK_ATTRIBUTE, nil)

	return self
end

function Mimic:SetHeadLock(target: Player?)
	self.Model:SetAttribute(HEAD_LOCK_ATTRIBUTE, if target then target.UserId else nil)
end

function Mimic:SetAttackActive(active: boolean)
	self.Model:SetAttribute(ATTACK_ACTIVE_ATTRIBUTE, active)
end

local function buildChaseFace(head: BasePart): Model
	local scale = head.Size.Y / 1.2
	local front = -head.Size.Z / 2

	local face = Instance.new("Model")
	face.Name = "MimicFace"

	local function addPart(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, className: string?)
		local part = Instance.new(className or "Part") :: Part
		part.Name = name
		part.Size = size * scale
		part.Color = color
		part.Material = material
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false
		part.CFrame = head.CFrame * offset
		part.Parent = face
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = part
		weld.Parent = part
		return part
	end

	for _, side in { -1, 1 } do
		addPart(
			"EyeLining",
			Vector3.new(0.34, 0.4, 0.06),
			CFrame.new(side * 0.22 * scale, 0.14 * scale, front - 0.015 * scale),
			Color3.new(0, 0, 0),
			Enum.Material.SmoothPlastic
		)
		addPart(
			"Eye",
			Vector3.new(0.2, 0.26, 0.08),
			CFrame.new(side * 0.22 * scale, 0.14 * scale, front - 0.045 * scale),
			Color3.fromRGB(255, 20, 20),
			Enum.Material.Neon
		)
	end

	local mouthY = -0.3 * scale
	addPart(
		"Mouth",
		Vector3.new(0.7, 0.32, 0.06),
		CFrame.new(0, mouthY, front - 0.015 * scale),
		Color3.new(0, 0, 0),
		Enum.Material.SmoothPlastic
	)
	local toothColor = Color3.fromRGB(235, 235, 220)
	local toothHeight = 0.15
	local halfWidth = 0.045
	local function addTooth(x: number, y: number, pointDown: boolean)
		for _, side in { -1, 1 } do
			local yaw = side * math.pi / 2 * (if pointDown then 1 else -1)
			local roll = if pointDown then math.pi else 0
			addPart(
				"Tooth",
				Vector3.new(0.05, toothHeight, halfWidth),
				CFrame.new(x + side * halfWidth / 2 * scale, y, front - 0.04 * scale)
					* CFrame.Angles(0, 0, roll)
					* CFrame.Angles(0, yaw, 0),
				toothColor,
				Enum.Material.SmoothPlastic,
				"WedgePart"
			)
		end
	end

	for index = 0, 3 do
		local x = (-0.24 + index * 0.16) * scale
		addTooth(x, mouthY + 0.085 * scale, true)
		addTooth(x, mouthY - 0.085 * scale, false)
	end

	return face
end

function Mimic:ShowChaseFace()
	if self._chaseFace then return end
	local head = self.Model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then return end

	local face = buildChaseFace(head)
	face.Parent = self.Model
	self._chaseFace = face
end

function Mimic:HideChaseFace()
	if self._chaseFace then
		self._chaseFace:Destroy()
		self._chaseFace = nil
	end
end

function Mimic:StartFloat()
	if self._baseHipHeight ~= nil then return end
	self._baseHipHeight = self.Humanoid.HipHeight
	self._laneProbeDrop = MimicConfig.FloatHipRise
	self:ShowChaseFace()

	if self._floatTween then self._floatTween:Cancel() end
	local middle = self._baseHipHeight + MimicConfig.FloatHipRise - MimicConfig.FloatBobAmplitude
	self._floatTween = TweenService:Create(
		self.Humanoid,
		TweenInfo.new(MimicConfig.FloatRiseTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ HipHeight = middle }
	)
	self._floatTween:Play()

	local bobFrom = os.clock() + MimicConfig.FloatRiseTime
	self._floatBob = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - bobFrom
		if elapsed < 0 then return end
		self.Humanoid.HipHeight = middle
			+ MimicConfig.FloatBobAmplitude * math.sin(elapsed * math.pi * 2 / MimicConfig.FloatBobPeriod)
	end)
end

function Mimic:StopFloat()
	local base = self._baseHipHeight
	self._baseHipHeight = nil
	self._laneProbeDrop = nil
	self:HideChaseFace()
	if self._floatBob then
		self._floatBob:Disconnect()
		self._floatBob = nil
	end
	if self._floatTween then
		self._floatTween:Cancel()
		self._floatTween = nil
	end
	if base == nil then return end

	self._floatTween = TweenService:Create(
		self.Humanoid,
		TweenInfo.new(MimicConfig.FloatSettleTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ HipHeight = base }
	)
	self._floatTween:Play()
end

function Mimic:_StartClientControl(target: Player, mode: string)
	if self.Mirroring == target and self.MirroringMode == mode then return end

	self:StopMirroring()
	self:SetHeadLock(nil)
	self.Mirroring = target
	self.MirroringMode = mode
	if mode == "Mirror" then
		self.Model:SetAttribute("LookMirrorUserId", target.UserId)
	end
	self.Humanoid.AutoRotate = false
	self:SetNetworkOwner(target)
	if mode ~= "Spin" then
		self.Animator:Stop()
	end
	Mirror:FireClient(target, self.Model, mode)
end

function Mimic:StartMirroring(target: Player)
	self:_StartClientControl(target, "Mirror")
end

function Mimic:StartSpinning(target: Player)
	self:_StartClientControl(target, "Spin")
end

function Mimic:StopMirroring()
	self:SetHeadLock(nil)
	self.Model:SetAttribute("LookMirrorUserId", nil)
	self.Humanoid.AutoRotate = true
	if not self.Mirroring then return end

	local target = self.Mirroring
	self.Mirroring = nil
	self.MirroringMode = nil
	Mirror:FireClient(target, nil)
	self:SetNetworkOwner(nil)
	self.Animator:Start()
	self.Animator:ClearForeignTracks()
	task.delay(HANDBACK_SWEEP_DELAY, function()
		if self.Active and not self.Mirroring then
			self.Animator:ClearForeignTracks()
		end
	end)
end

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

function Mimic:_facingConstraint(): AlignOrientation
	local align = self._facingAlign
	if align then return align end

	local attachment = Instance.new("Attachment")
	attachment.Name = "MimicFacing"
	attachment.Parent = self.RootPart

	align = Instance.new("AlignOrientation")
	align.Name = "MimicFacing"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = false
	align.MaxTorque = MimicConfig.FacingTorque
	align.Responsiveness = MimicConfig.FacingResponsiveness
	align.Enabled = false
	align.Parent = self.RootPart

	self._facingAlign = align
	return align
end

function Mimic:SetFacing(direction: Vector3?)
	local flat = direction and Vector3.new(direction.X, 0, direction.Z)
	if not flat or flat.Magnitude < 1e-3 then return end

	local align = self:_facingConstraint()
	align.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
	align.Enabled = true
	self.Humanoid.AutoRotate = false
end

function Mimic:ClearFacing()
	if self._facingAlign then
		self._facingAlign.Enabled = false
	end
	self.Humanoid.AutoRotate = true
end

function Mimic:_copyBadge(identity: Player)
	local name = identity.DisplayName
	if identity.HasVerifiedBadge then
		name ..= " " .. utf8.char(VERIFIED_GLYPH)
	end
	self.Humanoid.DisplayName = name
end

function Mimic:_copyRadio(identity: Player)
	local existing = self.Model:FindFirstChild(RADIO_TOOL_NAME)

	local character = identity.Character
	local held = character and character:FindFirstChild(RADIO_TOOL_NAME)
	if not (held and held:IsA("Tool")) then
		if existing then existing:Destroy() end
		self.Animator:StopHold()
		return
	end
	if existing then
		self.Animator:PlayHold(AnimationConfig.Animations.ToolHold)
		return
	end

	local template = ReplicatedStorage:FindFirstChild("Tools")
	template = template and template:FindFirstChild(RADIO_TOOL_NAME)
	if not (template and template:IsA("Tool")) then return end

	local copy = template:Clone()
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.Massless = true
		end
	end
	copy.Parent = self.Model

	self.Animator:PlayHold(AnimationConfig.Animations.ToolHold)
end

function Mimic:AssumeIdentity(player: Player)
	self.Identity = player
	if self._swapping then return end
	self._swapping = true

	task.spawn(function()
		while self.Active and self.Identity and self.Identity ~= self._appliedIdentity do
			local identity = self.Identity :: Player
			self.Model.Name = identity.Name
			self:_copyBadge(identity)

			local description = getDescription(identity)
			if description then
				pcall(self.Humanoid.ApplyDescription, self.Humanoid, description)
				self.Animator:Reload()
			end

			self:_copyRadio(identity)
			self._appliedIdentity = identity
		end
		self._swapping = false
	end)
end

function Mimic:Start()
	NPC.Start(self)

	self.Animator:PreloadOverride(AnimationConfig.Animations.Fly)

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
	self._revealed = false
	self.Model:SetAttribute(CHASE_TARGET_ATTRIBUTE, nil)
	self.Animator:StopOverride()
	self:StopFloat()
	self:SetAttackActive(false)
	self:StopMirroring()
	NPC.Despawn(self)
end

function Mimic:BuildStateMachine(): StateMachine.StateMachine
	local npc = self

	local function walkingFreely(state: (...any) -> ...any)
		return function(...)
			npc:ClearFacing()
			return state(...)
		end
	end

	return StateMachine.new({
		Idle = walkingFreely(loiter),
		AfkIdle = walkingFreely(afkIdle),
		Wander = walkingFreely(NPC.SharedStates.Wander),
		Patrol = walkingFreely(NPC.SharedStates.Patrol),
		Despawn = NPC.SharedStates.Despawn,
		Stalk = stalk,
		Chase = walkingFreely(chase),
		Attack = walkingFreely(attack),
		Search = walkingFreely(search),
		Stunned = walkingFreely(stunned),
	}, {
		Perception = { "Idle", "Wander", "Patrol", "Search", "AfkIdle" },
		Impact = { "Idle", "AfkIdle", "Wander", "Patrol", "Search", "Stalk", "Chase", "Attack" },
	}, {
		Perception = function()
			while true do
				task.wait(PERCEPTION_INTERVAL)

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

				if state == "AfkIdle" and npc.EncounterMode == "Afk" and findNearbyPlayer(npc) then
					npc.StateMachine:SetState("Stalk", "Perception", npc)
				elseif target and npc.EncounterMode and state == "Search" then
					npc.StateMachine:SetState("Stalk", "Perception", npc, target)
				elseif target and not npc.EncounterMode and canStartEncounter then
					npc.EncounterMode = npc:RollEncounterMode(false)
					npc.StateMachine:SetState("Stalk", "Perception", npc, target)
				elseif not target
					and not npc.EncounterMode
					and canStartEncounter
					and not findNearbyPlayer(npc)
					and not isNearOccupiedRoom(npc)
					and os.clock() >= npc._nextAfkRollAt
				then
					npc.EncounterMode = "Afk"
					npc.StateMachine:SetState("AfkIdle", "Perception", npc)
				end
			end
		end,
	}, "Idle", self)
end

return Mimic
