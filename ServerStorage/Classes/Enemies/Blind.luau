local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local HeartbeatConfig = require(ReplicatedStorage.Configs.HeartbeatConfig)
local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local HearingService = require(ServerStorage.Services.HearingService)
local NPC = require(ServerStorage.Classes.NPC)

local PERCEPTION_INTERVAL = 0.1
local CONTACT_GRACE = 0.15
local COAST_MINIMUM_SPEED = 0.2
local PURSUIT_ATTRIBUTE = HeartbeatConfig.PursuitAttribute

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
	npc.HeardDistance = 0
	npc.HeardPosition = npc:GetTargetPosition(player) or npc.RootPart.Position
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

	local velocity = npc.RootPart.AssemblyLinearVelocity
	local heading = Vector3.new(velocity.X, 0, velocity.Z)
	if heading.Magnitude < 1 then
		local look = npc.RootPart.CFrame.LookVector
		heading = Vector3.new(look.X, 0, look.Z)
	end
	if heading.Magnitude < 1e-3 then return false end
	heading = heading.Unit

	local room = npc:GetClearRun(heading, range)
	if room < (npc.Config.OvershootMinimum or 0) then
		print("[Blind] no coast, clear run", math.floor(room + 0.5), "studs")
		return false
	end
	print("[Blind] coasting past for", math.floor(room + 0.5), "studs")

	local start = npc.RootPart.Position
	local stop = start + heading * room
	local heardAt = npc.LastNoiseAt

	local deadline = os.clock() + (room / base) * 4 + 0.5
	local interrupted = false

	while npc.Active and os.clock() < deadline do
		local offset = npc.RootPart.Position - start
		local travelled = Vector3.new(offset.X, 0, offset.Z):Dot(heading)
		local progress = math.clamp(travelled / room, 0, 1)
		if progress >= 1 then break end

		npc:SetSpeed(base * math.max(1 - progress, COAST_MINIMUM_SPEED))
		npc.Humanoid:MoveTo(stop)

		if npc.LastNoiseAt ~= heardAt then
			interrupted = true
			break
		end
		RunService.Heartbeat:Wait()
	end

	npc:SetSpeed(0)
	npc:StopMoving()
	print("[Blind] coast ended, interrupted =", interrupted)
	return interrupted
end

local function followsTrail(npc: any, noise, distance: number, now: number): boolean
	if not npc.HeardNoise or npc.HeardSource == noise.Source then return true end
	if now - (npc.LastNoiseAt or 0) >= npc.Config.TrailSilenceTime then return true end
	return distance < (npc.HeardDistance or math.huge)
end

local function hear(npc: any, noise, distance: number)
	if not npc.Active then
		print("[Blind] heard noise but npc inactive")
		return
	end
	local now = os.clock()
	if not followsTrail(npc, noise, distance, now) then
		print("[Blind] ignored noise from", noise.Source, "- already following a closer trail")
		return
	end

	local hadTrail = npc.HeardNoise ~= nil
	local changedSource = hadTrail and npc.HeardSource ~= noise.Source

	if changedSource then
		npc.Determination = 0
		npc.DeterminationUpdatedAt = now
	end

	addDetermination(npc, noise, distance, now)
	npc.HeardPosition = noise.Position
	npc.HeardNoise = noise
	npc.HeardSource = noise.Source
	npc.HeardDistance = distance
	npc.Target = noise.Source

	local close = noise.Source ~= nil and distance <= (npc.Config.PursueRange or 0)
	if close then
		npc.Determination = 1
		npc.DeterminationUpdatedAt = now
	end

	if not close and not isHighlyCertain(npc) and (not hadTrail or changedSource) then
		npc.FlinchPending = true
	end

	local before = npc.StateMachine.State
	if close then
		npc.FlinchPending = false
		npc.StateMachine:SetState("Pursue", "Close", npc, noise.Source)
	else
		npc.StateMachine:SetState("Investigate", "Noise", npc)
	end
	print("[Blind] heard noise from", noise.Source, "dist", math.floor(distance + 0.5), "close =", close, "state", before, "->", npc.StateMachine.State)
end

local function stopListening(npc: any)
	npc.Animator:StopOverride()
end

local function investigate(_changeState: StateMachine.ChangeState, npc: any)
	stopListening(npc)
	npc.Animator:Resume()
	setInvestigateSpeed(npc)

	if npc.FlinchPending then
		npc.FlinchPending = false
		notice(npc)
	end

	local result = npc:Pursue(function()
		local goal = npc.HeardPosition
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
		local heard = npc.HeardSource
		return heard ~= nil and npc:IsValidTarget(heard) and npc:HasPursuitSight(heard)
	end)

	print("[Blind] investigate pursue result:", result)
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
	stopListening(npc)
	npc:BeginChase(target)

	local giveUpRange = npc.Config.PursuitGiveUpRange or npc.Config.GiveUpRange
	local lastKnown = npc:GetTargetPosition(target) or npc.RootPart.Position

	local result = npc:Pursue(function()
		local position = npc:GetTargetPosition(target)
		if not position then
			return nil
		end
		if (position - npc.RootPart.Position).Magnitude > giveUpRange then
			return nil
		end
		lastKnown = position
		return position
	end, nil, nil, function()
		return npc:HasPursuitSight(target)
	end)

	if result == "Reached" then
		return "Attack", npc, target
	end
	if coastPast(npc) then
		return "Investigate", npc
	end
	return "Search", npc, lastKnown
end

local function attack(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	stopListening(npc)
	local entered = os.clock()
	local touching = npc:IsValidTarget(target) and npc:IsTouchingPlayer(target)

	local deadline = entered + CONTACT_GRACE
	while not touching and os.clock() < deadline do
		task.wait()
		touching = npc:IsValidTarget(target) and npc:IsTouchingPlayer(target)
	end

	if not isHighlyCertain(npc) or not touching then
		if npc:IsValidTarget(target) then
			local position = npc:GetTargetPosition(target)
			local giveUpRange = npc.Config.PursuitGiveUpRange or npc.Config.GiveUpRange
			if position and (position - npc.RootPart.Position).Magnitude <= giveUpRange then
				return "Pursue", npc, target
			end
		end
		return "Search", npc, npc.RootPart.Position
	end

	npc:Attack(target)
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

	local animations = npc.Config.Animations
	local listenId = animations and animations.Listen
	local listenTrack = if listenId then npc.Animator:PlayOverride(listenId) else nil
	local listenTime = math.max(npc.Config.SearchTime, listenTrack and listenTrack.Length or 0)
	print("[Blind] Search reached point, listening for", listenTime, "seconds")
	task.wait(listenTime)
	stopListening(npc)
	print("[Blind] Search finished, listen override stopped")
	npc.HeardNoise = nil
	npc.HeardPosition = nil
	npc.HeardSource = nil
	npc.HeardDistance = nil
	npc.Determination = 0
	npc.LastNoiseAt = nil
	npc.DeterminationUpdatedAt = nil
	npc.FlinchPending = false
	return "Idle", npc
end

function Blind.new(model: Model, config)
	local self = NPC.new(model, config, Blind)
	local listenId = self.Config.Animations and self.Config.Animations.Listen
	if listenId then
		self.Animator:PreloadOverride(listenId)
	end
	self.HeardNoise = nil
	self.HeardPosition = nil
	self.HeardSource = nil
	self.HeardDistance = nil
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
		Stunned = function(changeState: StateMachine.ChangeState, target: any, duration: number)
			stopListening(target)
			return NPC.SharedStates.Stunned(changeState, target, duration)
		end,
	}, {
		Noise = { "Idle", "Wander", "Patrol", "Search" },
		Close = { "Idle", "Wander", "Patrol", "Search", "Investigate" },
		Contact = { "Idle", "Wander", "Patrol", "Investigate", "Pursue", "Search" },
		Impact = { "Idle", "Wander", "Patrol", "Investigate", "Pursue", "Attack", "Search" },
	}, {
		Hearing = function()
			HearingService:AddEar(npc.Model, {
				GetPosition = function()
					return if npc.Active then npc.RootPart.Position else nil
				end,

				Accepts = function(noise)
					if noise.Source == nil or npc:IsValidTarget(noise.Source) then
						return true
					end
					print("[Blind] deaf to", noise.Source.Name, "- givenUp =", npc:_hasGivenUpOn(noise.Source))
					return false
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

				local state = npc.StateMachine.State
				npc.Model:SetAttribute(
					PURSUIT_ATTRIBUTE,
					if state == "Pursue" or state == "Attack" then true else nil
				)
				if state == "Investigate" then
					setInvestigateSpeed(npc)
				end
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
