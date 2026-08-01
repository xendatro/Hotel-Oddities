--- @class Blind
--- Has no visual perception at all. It wanders until a noise reaches it, approaches its best estimate
--- of where that noise came from, and waits there listening when the trail goes quiet. Corners do not
--- muffle sound; walls only matter because it still has to path around them. Contact is fatal, even
--- when the player it finds was not the one it originally heard.

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

--- What it thinks it heard. Nearby sounds are exact; distance stretches a stable sideways error so
--- successive footsteps move the estimate smoothly instead of rolling a new zigzag every pulse.
local function estimatePosition(npc: any, noise): Vector3
	if not npc.HearingErrorDirection or npc.HeardSource ~= noise.Source then
		local angle = math.random() * math.pi * 2
		npc.HearingErrorDirection = Vector3.new(math.cos(angle), 0, math.sin(angle))
	end

	local config = npc.Config
	local distance = (noise.Position - npc.RootPart.Position).Magnitude
	local errorAlpha = math.clamp(
		(distance - config.HearingAccurateRange)
			/ (config.HearingErrorMaxDistance - config.HearingAccurateRange),
		0,
		1
	)
	return noise.Position + npc.HearingErrorDirection * config.HearingErrorMax * errorAlpha
end

--- Follows successive noises rather than a player. Silence freezes the goal at the last place heard;
--- arriving there starts a short listening search instead of granting knowledge of where anybody went.
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
	return "Idle", npc
end

function Blind.new(model: Model, config)
	local self = NPC.new(model, config, Blind)
	self.HeardNoise = nil
	self.HeardPosition = nil
	self.HeardSource = nil
	self.HearingErrorDirection = nil
	return self
end

function Blind:BuildStateMachine(): StateMachine.StateMachine
	local npc = self

	return StateMachine.new({
		Idle = NPC.SharedStates.Idle,
		Wander = NPC.SharedStates.Wander,
		Despawn = NPC.SharedStates.Despawn,
		Investigate = investigate,
		Attack = attack,
		Search = search,
		Stunned = NPC.SharedStates.Stunned,
	}, {
		-- A sound only pulls it away from quiet work. During an investigation, the evaluator updates
		-- `HeardPosition` in place so `Pursue` can repath without restarting the whole state every step.
		Noise = { "Idle", "Wander", "Search" },
		Contact = { "Idle", "Wander", "Investigate", "Search" },
		Impact = { "Idle", "Wander", "Investigate", "Attack", "Search" },
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

				local noise = NoiseService:GetLatest(npc.RootPart.Position, lastSequence, function(candidate)
					return candidate.Source == nil or npc:IsValidTarget(candidate.Source)
				end)
				if not noise then continue end

				lastSequence = noise.Sequence
				npc.HeardPosition = estimatePosition(npc, noise)
				npc.HeardNoise = noise
				npc.HeardSource = noise.Source
				npc.Target = noise.Source
				npc.StateMachine:SetState("Investigate", "Noise", npc)
			end
		end,
	}, "Idle", self)
end

return Blind
