local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local ObservedFreezeConfig = require(ReplicatedStorage.Configs.ObservedFreezeConfig)
local NPC = require(ServerStorage.Classes.NPC)

local PERCEPTION_INTERVAL = 0.05

local WeepingAngel = NPC.extend("WeepingAngel")

local function setFrozen(npc: any, frozen: boolean)
	npc.Model:SetAttribute(ObservedFreezeConfig.FrozenAttribute, frozen)
end

local function released(state: StateMachine.StateFunction): StateMachine.StateFunction
	return function(changeState: StateMachine.ChangeState, npc: any, ...: any)
		setFrozen(npc, false)
		return state(changeState, npc, ...)
	end
end

local function idle(_changeState: StateMachine.ChangeState, npc: any)
	npc.Target = nil
	npc.Animator:Resume()
	npc:SetSpeed(0)
	npc:StopMoving()
	task.wait(math.random() * (npc.Config.IdleTimeMax - npc.Config.IdleTimeMin) + npc.Config.IdleTimeMin)
	return npc.Config.IdleNextState, npc
end

local function frozen(_changeState: StateMachine.ChangeState, npc: any)
	setFrozen(npc, true)
	npc.Animator:Pause()
	npc:SetSpeed(0)
	npc:StopMoving()
	coroutine.yield()
end

local function chase(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	if npc:IsObserved() then
		return "Frozen", npc
	end

	npc.Target = target
	npc.Animator:Resume()
	npc:SetSpeed(npc.Config.ChaseSpeed)

	local result = npc:Pursue(function()
		return npc:GetTargetPosition(target)
	end, nil, nil, function()
		return npc:HasLineOfSightToPlayer(target)
	end)

	if result == "Reached" then
		return "Attack", npc, target
	end
	return "Idle", npc
end

local function attack(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	if npc:IsObserved() then
		return "Frozen", npc
	end

	local position = npc:GetTargetPosition(target)
	if not position then
		return "Idle", npc
	end

	if not npc:IsTouchingPlayer(target) then
		return "Chase", npc, target
	end

	npc:Attack(target)
	task.wait(npc.Config.AttackCooldown)
	return "Idle", npc
end

function WeepingAngel.new(model: Model, config)
	model:AddTag(ObservedFreezeConfig.Tag)
	model:SetAttribute(ObservedFreezeConfig.FrozenAttribute, false)
	return NPC.new(model, config, WeepingAngel)
end

function WeepingAngel:BuildStateMachine(): StateMachine.StateMachine
	local npc = self

	return StateMachine.new({
		Idle = released(idle),
		Patrol = released(NPC.SharedStates.Patrol),
		Frozen = frozen,
		Chase = released(chase),
		Attack = released(attack),
		Despawn = released(NPC.SharedStates.Despawn),
		Stunned = released(NPC.SharedStates.Stunned),
	}, {
		Observed = { "Idle", "Patrol", "Chase", "Attack" },
		Released = { "Frozen" },
		Perception = { "Idle", "Patrol" },
		Impact = { "Idle", "Patrol", "Chase", "Attack" },
	}, {
		Perception = function()
			while true do
				task.wait(PERCEPTION_INTERVAL)

				if npc:IsObserved() then
					if npc.StateMachine.State ~= "Frozen" then
						npc.StateMachine:SetState("Frozen", "Observed", npc)
					end
					continue
				end

				local target = npc:GetNearestTarget()
				if npc.StateMachine.State == "Frozen" then
					if target then
						npc.StateMachine:SetState("Chase", "Released", npc, target)
					else
						npc.StateMachine:SetState("Patrol", "Released", npc)
					end
				elseif target then
					npc.StateMachine:SetState("Chase", "Perception", npc, target)
				end
			end
		end,
	}, "Patrol", self)
end

return WeepingAngel
