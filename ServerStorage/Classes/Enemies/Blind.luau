--- @class Blind
--- Has no visual perception at all. It hunts a trail of sounds, never a player: every footstep replaces
--- its destination, and silence leaves it committed to that final point. Sustained sound escalates it
--- from a cautious investigation into a faster-than-player frenzy; stopping makes that certainty and
--- speed fall away. Contact is fatal, even when the player it finds was not the one it originally heard.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local NoiseService = require(ServerStorage.Services.NoiseService)
local NPC = require(ServerStorage.Classes.NPC)

local PERCEPTION_INTERVAL = 0.1

local Blind = NPC.extend("Blind")

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

local function addDetermination(npc: any, noise, now: number)
	updateDetermination(npc, now)
	local distance = (noise.Position - npc.RootPart.Position).Magnitude
	local strength = 1 - math.clamp(distance / math.max(noise.Radius, 1e-3), 0, 1)
	local config = npc.Config
	local gained = config.DeterminationPerNoiseMin
		+ (config.DeterminationPerNoiseMax - config.DeterminationPerNoiseMin) * strength
	npc.Determination = math.min(npc.Determination + gained, 1)
	npc.LastNoiseAt = now
end

local function getTouchingPlayer(npc: any): Player?
	for _, player in Players:GetPlayers() do
		if npc:IsValidTarget(player) and npc:IsTouchingPlayer(player) then
			return player
		end
	end
	return nil
end

--- What it thinks it heard. Nearby sounds are exact; distance stretches one stable random offset so
--- successive footsteps move the estimate smoothly instead of rolling a new zigzag every pulse.
--- Determination squeezes that error toward zero. Its random scale has a floor, so one distant sound
--- cannot reveal somebody perfectly by luck.
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

--- Follows successive noises rather than a player. Silence freezes the goal at the final footstep;
--- arriving at the end of that lost trail starts a short listening search.
local function investigate(_changeState: StateMachine.ChangeState, npc: any)
	npc.Animator:Resume()
	setInvestigateSpeed(npc)

	local caught = nil :: Player?
	local lastKnown = npc.HeardPosition or npc.RootPart.Position
	npc:Pursue(function()
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
		caught = getTouchingPlayer(npc)
		return caught ~= nil
	end, function()
		return true
	end)

	if caught then
		return "Attack", npc, caught
	end

	return "Search", npc, lastKnown
end

--- Kills only while contact is real. Losing that contact provides a last-known position, not sight.
local function attack(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	npc:StopMoving()

	if not npc:IsValidTarget(target) or not npc:IsTouchingPlayer(target) then
		return "Search", npc, npc.RootPart.Position
	end

	local position = npc:GetTargetPosition(target) :: Vector3
	npc:FaceTowards(position)
	npc:Attack(target)
	task.wait(npc.Config.AttackCooldown)
	return "Idle", npc
end

--- Stands at the last sound and listens. A fresh noise interrupts this immediately.
local function search(_changeState: StateMachine.ChangeState, npc: any, lastKnown: Vector3)
	npc.Target = nil
	npc.Animator:Resume()
	npc:SetSpeed(npc.Config.WalkSpeed)
	npc:WalkTo(lastKnown)
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
	return "Idle", npc
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
		Attack = attack,
		Search = search,
		Stunned = NPC.SharedStates.Stunned,
	}, {
		-- A sound only pulls it away from quiet work. During an investigation, the evaluator updates
		-- `HeardPosition` in place so `Pursue` can repath without restarting the whole state every step.
		Noise = { "Idle", "Wander", "Patrol", "Search" },
		Contact = { "Idle", "Wander", "Patrol", "Investigate", "Search" },
		Impact = { "Idle", "Wander", "Patrol", "Investigate", "Attack", "Search" },
	}, {
		Hearing = function()
			local lastSequence = 0
			while true do
				task.wait(PERCEPTION_INTERVAL)
				local now = os.clock()
				updateDetermination(npc, now)
				if npc.StateMachine.State == "Investigate" then
					setInvestigateSpeed(npc)
				end

				local touching = getTouchingPlayer(npc)
				if touching then
					npc.StateMachine:SetState("Attack", "Contact", npc, touching)
					continue
				end

				local noise = NoiseService:GetLatest(npc.RootPart.Position, lastSequence, function(candidate)
					return candidate.Source == nil or npc:IsValidTarget(candidate.Source)
				end)
				if noise then
					lastSequence = noise.Sequence
					if npc.HeardNoise and npc.HeardSource ~= noise.Source then
						npc.Determination = 0
						npc.DeterminationUpdatedAt = now
					end
					addDetermination(npc, noise, now)
					npc.HeardPosition = estimatePosition(npc, noise)
					npc.HeardNoise = noise
					npc.HeardSource = noise.Source
					npc.Target = noise.Source
					npc.StateMachine:SetState("Investigate", "Noise", npc)
				end
			end
		end,
	}, "Idle", self)
end

return Blind
