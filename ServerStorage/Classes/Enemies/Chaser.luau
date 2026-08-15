--- @class Chaser
--- The plain hunter. Wanders its spawn area until a player crosses the cone in front of it, then
--- runs them down. Ducking into a `Room` breaks its line and sends it straight back to its patrol.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local NPC = require(ServerStorage.Classes.NPC)
local RoomService = require(ServerStorage.Services.RoomService)

local PERCEPTION_INTERVAL = 0.25
local CHASE_TARGET_ATTRIBUTE = "ChaseTargetUserId"

local Chaser = NPC.extend("Chaser")

local function clearChaseTarget(npc: any)
	npc.Model:SetAttribute(CHASE_TARGET_ATTRIBUTE, nil)
end

local function idle(changeState: StateMachine.ChangeState, npc: any)
	clearChaseTarget(npc)
	return NPC.SharedStates.Idle(changeState, npc)
end

local function wander(changeState: StateMachine.ChangeState, npc: any)
	clearChaseTarget(npc)
	return NPC.SharedStates.Wander(changeState, npc)
end

local function patrol(changeState: StateMachine.ChangeState, npc: any)
	clearChaseTarget(npc)
	return NPC.SharedStates.Patrol(changeState, npc)
end

local function stunned(changeState: StateMachine.ChangeState, npc: any, duration: number)
	clearChaseTarget(npc)
	return NPC.SharedStates.Stunned(changeState, npc, duration)
end

local function despawn(changeState: StateMachine.ChangeState, npc: any)
	clearChaseTarget(npc)
	return NPC.SharedStates.Despawn(changeState, npc)
end

--- Runs `target` down until it is caught, reaches a safe room, or outruns `GiveUpRange`.
local function chase(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	npc.Target = target
	npc.Model:SetAttribute(CHASE_TARGET_ATTRIBUTE, target.UserId)
	npc.Animator:Resume()
	npc:SetSpeed(npc.Config.ChaseSpeed)

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
	end, 0, function()
		return npc:IsTouchingPlayer(target)
	end, function()
		return npc:HasLineOfSightToPlayer(target)
	end)

	if result == "Reached" then
		return "Attack", npc, target
	end
	if safeRoom then
		return "RoomReaction", npc, safeRoom
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

--- Drops the target and resumes patrolling as soon as the chase ends.
local function search(_changeState: StateMachine.ChangeState, npc: any, _lastKnown: Vector3)
	clearChaseTarget(npc)
	npc.Target = nil
	npc.Animator:Resume()
	npc:SetSpeed(npc.Config.WalkSpeed)
	return "Patrol", npc
end

local function roomReaction(changeState: StateMachine.ChangeState, npc: any, room: Model)
	clearChaseTarget(npc)
	return NPC.SharedStates.RoomReaction(changeState, npc, room)
end

function Chaser.new(model: Model, config)
	return NPC.new(model, config, Chaser)
end

function Chaser:BuildStateMachine(): StateMachine.StateMachine
	local npc = self

	return StateMachine.new({
		Idle = idle,
		Wander = wander,
		Patrol = patrol,
		Despawn = despawn,
		Chase = chase,
		Attack = attack,
		Search = search,
		RoomReaction = roomReaction,
		Stunned = stunned,
	}, {
		-- Spotting a player pulls the chaser off anything idle, but never out of a swing.
		Perception = { "Idle", "Wander", "Patrol", "Search" },
		-- A trap or a paper ball lands whatever it is doing, but cannot re-stun a stunned chaser.
		Impact = { "Idle", "Wander", "Patrol", "Search", "Chase", "Attack", "RoomReaction" },
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
