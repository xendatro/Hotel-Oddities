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

local function chase(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	npc.Target = target
	npc.Model:SetAttribute(CHASE_TARGET_ATTRIBUTE, target.UserId)
	npc.Animator:Resume()
	npc:SetSpeed(npc.Config.ChaseSpeed)

	local lastKnown = npc.RootPart.Position
	local safeRoom = nil :: Model?
	local unseenSince = nil :: number?
	local result = npc:Pursue(function()
		if RoomService:IsInRoom(target) then
			safeRoom = RoomService:GetRoom(target)
			return nil
		end
		local loseSightTime = npc.Config.ChaseLoseSightTime
		if loseSightTime then
			if npc:HasPursuitSight(target) then
				unseenSince = nil
			else
				unseenSince = unseenSince or os.clock()
				if os.clock() - unseenSince >= loseSightTime then
					return nil
				end
			end
		end
		local position = npc:GetTargetPosition(target)
		if position then
			lastKnown = position
		end
		return position
	end, nil, nil, function()
		return npc:HasPursuitSight(target)
	end)

	if result == "Reached" then
		return "Attack", npc, target
	end
	if safeRoom then
		return "RoomReaction", npc, safeRoom
	end
	return "Search", npc, lastKnown
end

local function attack(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	local position = npc:GetTargetPosition(target)
	if not position then
		return "Search", npc, npc.RootPart.Position
	end

	if not npc:IsTouchingPlayer(target) then
		return "Chase", npc, target
	end

	npc:Attack(target)
	task.wait(npc.Config.AttackCooldown)
	return "Idle", npc
end

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

Chaser.Chase = chase

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
		Perception = { "Idle", "Wander", "Patrol", "Search" },
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
