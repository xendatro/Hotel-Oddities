--- @class Chaser
--- The plain hunter. Wanders its spawn area until a player crosses the cone in front of it, then
--- runs them down. Ducking into a `Room` breaks its line: it holds the spot it last saw you for
--- `LoseInterestTime` before drifting back to wandering.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local NPC = require(ServerStorage.Classes.NPC)

local PERCEPTION_INTERVAL = 0.25
local LOOK_AROUND_DISTANCE = 10

local Chaser = NPC.extend("Chaser")

--- Runs `target` down until it is caught, reaches a safe room, or outruns `GiveUpRange`.
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
	end, 0, function()
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
	if not npc:IsTouchingPlayer(target) then
		return "Chase", npc, target
	end

	npc:Attack(target)
	task.wait(npc.Config.AttackCooldown)
	return "Idle", npc
end

--- Sweeps to where the target was last seen and loiters there, giving perception a window to
--- re-acquire them when they leave the room.
local function search(_changeState: StateMachine.ChangeState, npc: any, lastKnown: Vector3)
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

function Chaser.new(model: Model, config)
	return NPC.new(model, config, Chaser)
end

function Chaser:BuildStateMachine(): StateMachine.StateMachine
	local npc = self

	return StateMachine.new({
		Idle = NPC.SharedStates.Idle,
		Wander = NPC.SharedStates.Wander,
		Patrol = NPC.SharedStates.Patrol,
		Despawn = NPC.SharedStates.Despawn,
		Chase = chase,
		Attack = attack,
		Search = search,
		Stunned = NPC.SharedStates.Stunned,
	}, {
		-- Spotting a player pulls the chaser off anything idle, but never out of a swing.
		Perception = { "Idle", "Wander", "Patrol", "Search" },
		-- A trap or a paper ball lands whatever it is doing, but cannot re-stun a stunned chaser.
		Impact = { "Idle", "Wander", "Patrol", "Search", "Chase", "Attack" },
	}, {
		Perception = function()
			while true do
				task.wait(PERCEPTION_INTERVAL)
				local target = npc:GetNearestVisibleTarget()
				if target then
					npc.StateMachine:SetState("Chase", "Perception", npc, target)
				end
			end
		end,
	}, "Idle", self)
end

return Chaser
