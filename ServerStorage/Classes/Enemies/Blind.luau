local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local HearingService = require(ServerStorage.Services.HearingService)
local NPC = require(ServerStorage.Classes.NPC)
local RoomService = require(ServerStorage.Services.RoomService)

local traceStart = os.clock()
local function trace(npc: any, message: string)
	if not FLAGS.BlindTrace then return end
	print(string.format(
		"[Blind] %6.2fs %-10s spd=%5.1f det=%.2f | %s",
		os.clock() - traceStart,
		tostring(npc.StateMachine and npc.StateMachine.State),
		npc.Humanoid.WalkSpeed,
		npc.Determination or 0,
		message
	))
end

local PERCEPTION_INTERVAL = 0.1
local CONTACT_GRACE = 0.15

local Blind = NPC.extend("Blind")

local function isHighlyCertain(npc: any): boolean
	return npc.Determination >= npc.Config.FrenzyThreshold
end

local function updateDetermination(npc: any, now: number)
	local updatedAt = npc.DeterminationUpdatedAt or now
	local decayAfter = (npc.LastNoiseAt or now) + npc.Config.DeterminationSilenceGrace
	local decayFrom = math.max(updatedAt, decayAfter)
	if now > decayFrom then
		npc.Determination = math.max(
			npc.Determination - (now - decayFrom) * npc.Config.DeterminationDecay,
			0
		)
	end
	npc.DeterminationUpdatedAt = now
end

local function setInvestigateSpeed(npc: any)
	local config = npc.Config
	local speed = if npc.Determination >= config.FrenzyThreshold
		then config.ChaseSpeed
		elseif npc.Determination >= config.AlertThreshold then config.AlertSpeed
		else config.InvestigateSpeed
	if npc.Humanoid.WalkSpeed ~= speed then
		npc:SetSpeed(speed)
	end
end

local function addDetermination(npc: any, noise, distance: number, now: number)
	updateDetermination(npc, now)
	local config = npc.Config
	local pursueRange = config.PursueRange or 0
	local edge = math.max(noise.Radius, pursueRange + 1e-3)
	local strength = 1 - math.clamp((distance - pursueRange) / (edge - pursueRange), 0, 1)
	local gained = config.DeterminationPerNoiseMin
		+ (config.DeterminationPerNoiseMax - config.DeterminationPerNoiseMin) * strength
	npc.Determination = math.min(npc.Determination + gained, 1)
	npc.LastNoiseAt = now
end

local function registerContact(npc: any, player: Player)
	local now = os.clock()
	npc.Determination = 1
	npc.DeterminationUpdatedAt = now
	npc.LastNoiseAt = now
	npc.Target = player
	npc.HeardSource = player
	npc.HeardPosition = npc:GetTargetPosition(player) or npc.RootPart.Position
end

local function estimatePosition(npc: any, noise): Vector3
	if not npc.HearingErrorDirection
		or npc.HearingErrorScale == nil
		or npc.HeardSource ~= noise.Source then
		local angle = math.random() * math.pi * 2
		npc.HearingErrorDirection = Vector3.new(math.cos(angle), 0, math.sin(angle))
		npc.HearingErrorScale = npc.Config.HearingErrorMinScale
			+ math.random() * (1 - npc.Config.HearingErrorMinScale)
	end

	local config = npc.Config
	local distance = (noise.Position - npc.RootPart.Position).Magnitude
	local errorAlpha = math.clamp(
		(distance - config.HearingAccurateRange)
			/ (config.HearingErrorMaxDistance - config.HearingAccurateRange),
		0,
		1
	)
	local maximumError = math.min(
		config.HearingErrorMax * errorAlpha,
		math.max(distance - config.InvestigateRange, 0)
	)
	local uncertainty = 1 - npc.Determination
	return noise.Position + npc.HearingErrorDirection * maximumError * npc.HearingErrorScale * uncertainty
end

local function notice(npc: any)
	local goal = npc.HeardPosition
	if not goal then return end

	local turnTime = npc.Config.NoticeTurnTime or 0
	if turnTime > 0 then
		npc:TurnTowardsSmooth(goal, turnTime)
	else
		npc:FaceTowards(goal)
	end
end

local function coastPast(npc: any): boolean
	local range = npc.Config.OvershootRange or 0
	local base = npc.Humanoid.WalkSpeed
	if range <= 0 or base <= 0 then return false end

	local look = npc.RootPart.CFrame.LookVector
	local heading = Vector3.new(look.X, 0, look.Z)
	if heading.Magnitude < 1e-3 then return false end
	heading = heading.Unit

	local room = npc:GetClearRun(heading, range)
	if room < (npc.Config.OvershootMinimum or 0) then
		trace(npc, string.format("no room to run out, %.1f studs clear", room))
		return false
	end

	local start = npc.RootPart.Position
	local stop = start + heading * room
	local heardAt = npc.LastNoiseAt
	trace(npc, string.format("running out %.1f studs past the sound at %.1f", room, base))

	local deadline = os.clock() + (room / base) * 3 + 0.5
	local interrupted = false

	while npc.Active and os.clock() < deadline do
		local offset = npc.RootPart.Position - start
		local travelled = Vector3.new(offset.X, 0, offset.Z):Dot(heading)
		local progress = math.clamp(travelled / room, 0, 1)
		if progress >= 1 then break end

		npc:SetSpeed(base * math.cos(progress * math.pi / 2))
		npc.Humanoid:MoveTo(stop)

		if npc.LastNoiseAt ~= heardAt then
			interrupted = true
			break
		end
		RunService.Heartbeat:Wait()
	end

	npc:SetSpeed(0)
	npc:StopMoving()
	return interrupted
end

local function hear(npc: any, noise, distance: number)
	if not npc.Active then return end
	local now = os.clock()

	local hadTrail = npc.HeardNoise ~= nil
	local changedSource = hadTrail and npc.HeardSource ~= noise.Source

	if changedSource then
		npc.Determination = 0
		npc.DeterminationUpdatedAt = now
	end

	addDetermination(npc, noise, distance, now)
	npc.HeardPosition = estimatePosition(npc, noise)
	npc.HeardNoise = noise
	npc.HeardSource = noise.Source
	npc.Target = noise.Source

	local close = noise.Source ~= nil and distance <= (npc.Config.PursueRange or 0)
	if close then
		npc.Determination = 1
		npc.DeterminationUpdatedAt = now
	end

	if not close and not isHighlyCertain(npc) and (not hadTrail or changedSource) then
		npc.FlinchPending = true
	end

	if close then
		npc.FlinchPending = false
		npc.StateMachine:SetState("Pursue", "Close", npc, noise.Source)
	else
		npc.StateMachine:SetState("Investigate", "Noise", npc)
	end
end

local function investigate(_changeState: StateMachine.ChangeState, npc: any)
	npc.Animator:Resume()
	setInvestigateSpeed(npc)

	if npc.FlinchPending then
		npc.FlinchPending = false
		notice(npc)
	end

	local lastKnown = npc.HeardPosition or npc.RootPart.Position
	local safeRoom = nil :: Model?
	local result = npc:Pursue(function()
		if npc.HeardSource and RoomService:IsInRoom(npc.HeardSource) then
			safeRoom = RoomService:GetRoom(npc.HeardSource)
			return nil
		end
		local goal = npc.HeardPosition
		if goal then
			lastKnown = goal
		end
		if goal
			and npc.LastNoiseAt
			and os.clock() - npc.LastNoiseAt >= npc.Config.TrailSilenceTime
			and (npc.RootPart.Position - goal).Magnitude <= npc.Config.InvestigateRange then
			return nil
		end
		return goal
	end, nil, function()
		local heard = npc.HeardSource
		return heard ~= nil and npc:IsValidTarget(heard) and npc:IsTouchingPlayer(heard)
	end, function()
		return true
	end)

	if safeRoom then
		return "RoomReaction", npc, safeRoom
	end

	local caught = npc.HeardSource
	if result == "Reached" and caught and npc:IsValidTarget(caught) and npc:IsTouchingPlayer(caught) then
		registerContact(npc, caught)
		return "Attack", npc, caught
	end

	if coastPast(npc) then
		return "Investigate", npc
	end

	return "Search", npc, npc.RootPart.Position
end

local function pursue(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	npc.Target = target
	npc.Animator:Resume()
	npc:SetSpeed(npc.Config.ChaseSpeed)

	local giveUpRange = npc.Config.PursuitGiveUpRange or npc.Config.GiveUpRange
	local lastKnown = npc:GetTargetPosition(target) or npc.RootPart.Position
	local safeRoom = nil :: Model?
	local reason = "?"
	trace(npc, `Pursue entered on {target.Name}, giveUp={giveUpRange}`)

	local result = npc:Pursue(function()
		if RoomService:IsInRoom(target) then
			safeRoom = RoomService:GetRoom(target)
			reason = "safe room"
			return nil
		end
		local position = npc:GetTargetPosition(target)
		if not position then
			reason = "target no longer valid"
			return nil
		end
		if (position - npc.RootPart.Position).Magnitude > giveUpRange then
			reason = string.format("target %.0f studs away, past giveUp", (position - npc.RootPart.Position).Magnitude)
			return nil
		end
		lastKnown = position
		return position
	end, nil, nil, function()
		return true
	end)

	trace(npc, `Pursue ended result={result} reason={reason}`)

	if result == "Reached" then
		return "Attack", npc, target
	end
	if safeRoom then
		return "RoomReaction", npc, safeRoom
	end
	return "Search", npc, lastKnown
end

local function attack(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	local entered = os.clock()
	local touching = npc:IsValidTarget(target) and npc:IsTouchingPlayer(target)
	trace(npc, `Attack entered, touching={touching} certain={isHighlyCertain(npc)}`)

	local deadline = entered + CONTACT_GRACE
	while not touching and os.clock() < deadline do
		task.wait()
		touching = npc:IsValidTarget(target) and npc:IsTouchingPlayer(target)
	end
	trace(npc, string.format("Attack grace done after %.2fs, touching=%s", os.clock() - entered, tostring(touching)))

	if not isHighlyCertain(npc) or not touching then
		if npc:IsValidTarget(target) then
			local position = npc:GetTargetPosition(target)
			local giveUpRange = npc.Config.PursuitGiveUpRange or npc.Config.GiveUpRange
			if position and (position - npc.RootPart.Position).Magnitude <= giveUpRange then
				trace(npc, "Attack missed -> back to Pursue")
				return "Pursue", npc, target
			end
		end
		trace(npc, "Attack missed and target gone -> Search")
		return "Search", npc, npc.RootPart.Position
	end

	local position = npc:GetTargetPosition(target) :: Vector3
	npc:FaceTowards(position)
	npc:Attack(target)
	trace(npc, `Attack landed, holding AttackCooldown={npc.Config.AttackCooldown}s`)
	task.wait(npc.Config.AttackCooldown)
	return "Idle", npc
end

local function search(_changeState: StateMachine.ChangeState, npc: any, lastKnown: Vector3)
	npc.Target = nil
	npc.Animator:Resume()

	if (npc.RootPart.Position - lastKnown).Magnitude > (npc.Config.InvestigateRange or 0) then
		npc:SetSpeed(npc.Config.WalkSpeed)
		npc:WalkTo(lastKnown)
	end
	npc:StopMoving()

	task.wait(npc.Config.SearchTime)
	npc.HeardNoise = nil
	npc.HeardPosition = nil
	npc.HeardSource = nil
	npc.HearingErrorDirection = nil
	npc.HearingErrorScale = nil
	npc.Determination = 0
	npc.LastNoiseAt = nil
	npc.DeterminationUpdatedAt = nil
	npc.FlinchPending = false
	return "Idle", npc
end

local function roomReaction(changeState: StateMachine.ChangeState, npc: any, room: Model)
	return NPC.SharedStates.RoomReaction(changeState, npc, room)
end

function Blind.new(model: Model, config)
	local self = NPC.new(model, config, Blind)
	self.HeardNoise = nil
	self.HeardPosition = nil
	self.HeardSource = nil
	self.HearingErrorDirection = nil
	self.HearingErrorScale = nil
	self.Determination = 0
	self.LastNoiseAt = nil
	self.DeterminationUpdatedAt = nil
	self.FlinchPending = false
	return self
end

function Blind:BuildStateMachine(): StateMachine.StateMachine
	local npc = self

	return StateMachine.new({
		Idle = NPC.SharedStates.Idle,
		Wander = NPC.SharedStates.Wander,
		Patrol = NPC.SharedStates.Patrol,
		Despawn = NPC.SharedStates.Despawn,
		Investigate = investigate,
		Pursue = pursue,
		Attack = attack,
		Search = search,
		RoomReaction = roomReaction,
		Stunned = NPC.SharedStates.Stunned,
	}, {
		Noise = { "Idle", "Wander", "Patrol", "Search" },
		Close = { "Idle", "Wander", "Patrol", "Search", "Investigate" },
		Contact = { "Idle", "Wander", "Patrol", "Investigate", "Pursue", "Search" },
		Impact = { "Idle", "Wander", "Patrol", "Investigate", "Pursue", "Attack", "Search", "RoomReaction" },
	}, {
		Hearing = function()
			HearingService:AddEar(npc.Model, {
				GetPosition = function()
					return if npc.Active then npc.RootPart.Position else nil
				end,

				GetCooldown = function()
					local config = npc.Config
					if isHighlyCertain(npc) and config.PursuitHearingCooldown then
						return config.PursuitHearingCooldown
					end
					return config.HearingCooldown or PERCEPTION_INTERVAL
				end,

				Accepts = function(noise)
					return noise.Source == nil or npc:IsValidTarget(noise.Source)
				end,

				OnHeard = function(noise, distance)
					hear(npc, noise, distance)
				end,

				IsAlive = function()
					return npc.Active == true and npc.Model.Parent ~= nil
				end,
			})

			while true do
				task.wait(PERCEPTION_INTERVAL)
				updateDetermination(npc, os.clock())
				if npc.StateMachine.State == "Investigate" then
					setInvestigateSpeed(npc)
				end
			end
		end,

		Trace = function()
			if not FLAGS.BlindTrace then return end

			local lastState = nil :: string?
			local since = os.clock()
			local lastPosition = npc.RootPart.Position
			local nextSample = 0

			while true do
				local deltaTime = RunService.Heartbeat:Wait()
				local now = os.clock()

				local state = npc.StateMachine.State
				if state ~= lastState then
					if lastState then
						trace(npc, string.format("%s lasted %.2fs -> %s", lastState, now - since, tostring(state)))
					end
					lastState, since = state, now
					nextSample = 0
				end

				if state == "Investigate" and now >= nextSample then
					nextSample = now + 0.2
					local goal = npc.HeardPosition
					local distance = if goal then (npc.RootPart.Position - goal).Magnitude else -1
					trace(npc, string.format(
						"approach %.1f studs out, moving %.1f",
						distance,
						Vector3.new(
							npc.RootPart.AssemblyLinearVelocity.X,
							0,
							npc.RootPart.AssemblyLinearVelocity.Z
						).Magnitude
					))
				end

				local position = npc.RootPart.Position
				local moved = (position - lastPosition).Magnitude
				local walkable = math.max(npc.Humanoid.WalkSpeed, 1) * deltaTime * 3 + 2
				if moved > walkable then
					trace(npc, string.format(
						"JUMPED %.1f studs in one frame (%.0f studs/s against a walk speed of %.1f)",
						moved,
						moved / math.max(deltaTime, 1e-3),
						npc.Humanoid.WalkSpeed
					))
				end
				lastPosition = position
			end
		end,

		Contact = function()
			while true do
				task.wait(PERCEPTION_INTERVAL)
				if npc.StateMachine.State == "Attack" then continue end

				for _, player in Players:GetPlayers() do
					if not npc:IsValidTarget(player) then continue end
					if not npc:IsTouchingPlayer(player) then continue end

					registerContact(npc, player)
					npc.StateMachine:SetState("Attack", "Contact", npc, player)
					break
				end
			end
		end,
	}, "Idle", self)
end

return Blind
