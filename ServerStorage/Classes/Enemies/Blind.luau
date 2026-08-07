--- @class Blind
--- Has no visual perception at all. It wanders until a noise reaches it, approaches its best estimate
--- of where that noise came from, and tracks the source exactly once it gets close enough to hear
--- where they stopped. Corners do not muffle sound; walls only matter because it still has to path
--- around them. Contact is fatal, even when the player it finds was not the one it originally heard.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local NoiseService = require(ServerStorage.Services.NoiseService)
local NPC = require(ServerStorage.Classes.NPC)

local PERCEPTION_INTERVAL = 0.1

local Blind = NPC.extend("Blind")

local function getTouchingPlayer(npc: any): Player?
	for _, player in Players:GetPlayers() do
		if npc:IsValidTarget(player) and npc:IsTouchingPlayer(player) then
			return player
		end
	end
	return nil
end

--- A source inside the exact-hearing range can still be placed after their last footstep. This closes
--- the gap between the last emitted noise and where a nearby player came to rest.
local function getCloseSourcePosition(npc: any, source: Player?): Vector3?
	if not source then return nil end
	local position = npc:GetTargetPosition(source)
	if not position then return nil end
	if (position - npc.RootPart.Position).Magnitude > npc.Config.HearingAccurateRange then return nil end
	return position
end

--- What it thinks it heard. Nearby sounds are exact; distance stretches one stable random offset so
--- successive footsteps move the estimate smoothly instead of rolling a new zigzag every pulse.
--- The random size means a distant sound can still be pinpointed by luck, while the cap makes sure
--- investigating a guess never leaves it farther from the real sound than when it heard it.
local function estimatePosition(npc: any, noise): Vector3
	if not npc.HearingErrorDirection
		or npc.HearingErrorScale == nil
		or npc.HeardSource ~= noise.Source then
		local angle = math.random() * math.pi * 2
		npc.HearingErrorDirection = Vector3.new(math.cos(angle), 0, math.sin(angle))
		npc.HearingErrorScale = math.random()
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
	return noise.Position + npc.HearingErrorDirection * maximumError * npc.HearingErrorScale
end

--- Follows successive noises rather than a player. Silence freezes the goal unless the source is close
--- enough to place exactly; arriving at a lost trail starts a short listening search.
local function investigate(_changeState: StateMachine.ChangeState, npc: any)
	npc.Animator:Resume()
	npc:SetSpeed(npc.Config.ChaseSpeed)

	local caught = nil :: Player?
	npc:Pursue(function()
		return npc.HeardPosition
	end, npc.Config.InvestigateRange, function()
		caught = getTouchingPlayer(npc)
		return caught ~= nil
	end)

	if caught then
		return "Attack", npc, caught
	end

	local lastKnown = npc.HeardPosition or npc.RootPart.Position
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

--- Stands at the last sound and listens. A fresh noise or a close source interrupts this immediately.
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
	return "Idle", npc
end

function Blind.new(model: Model, config)
	local self = NPC.new(model, config, Blind)
	self.HeardNoise = nil
	self.HeardPosition = nil
	self.HeardSource = nil
	self.HearingErrorDirection = nil
	self.HearingErrorScale = nil
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
		CloseHearing = { "Idle", "Wander", "Patrol", "Search" },
		Contact = { "Idle", "Wander", "Patrol", "Investigate", "Search" },
		Impact = { "Idle", "Wander", "Patrol", "Investigate", "Attack", "Search" },
	}, {
		Hearing = function()
			local lastSequence = 0
			while true do
				task.wait(PERCEPTION_INTERVAL)

				local touching = getTouchingPlayer(npc)
				if touching then
					npc.StateMachine:SetState("Attack", "Contact", npc, touching)
					continue
				end

				local closePosition = getCloseSourcePosition(npc, npc.HeardSource)
				if closePosition then
					npc.HeardPosition = closePosition
					npc.Target = npc.HeardSource
					npc.StateMachine:SetState("Investigate", "CloseHearing", npc)
					continue
				end

				local noise = NoiseService:GetLatest(npc.RootPart.Position, lastSequence, function(candidate)
					return candidate.Source == nil or npc:IsValidTarget(candidate.Source)
				end)
				if not noise then continue end

				lastSequence = noise.Sequence
				npc.HeardPosition = getCloseSourcePosition(npc, noise.Source)
					or estimatePosition(npc, noise)
				npc.HeardNoise = noise
				npc.HeardSource = noise.Source
				npc.Target = noise.Source
				npc.StateMachine:SetState("Investigate", "Noise", npc)
			end
		end,
	}, "Idle", self)
end

return Blind
