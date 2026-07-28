--- @class WeepingAngel
--- A hunter that always knows where nearby players are, but cannot move or finish an attack while
--- any living player can see it. Freezing pauses its current animation track on the exact pose.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local NPC = require(ServerStorage.Classes.NPC)

local PERCEPTION_INTERVAL = 0.1

local WeepingAngel = NPC.extend("WeepingAngel")

local function idle(_changeState: StateMachine.ChangeState, npc: any)
	npc.Target = nil
	npc.Animator:Resume()
	npc:SetSpeed(0)
	npc:StopMoving()
	coroutine.yield()
end

local function frozen(_changeState: StateMachine.ChangeState, npc: any)
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
	end, 0, function()
		return npc:IsTouchingPlayer(target)
	end, function()
		return npc:HasLineOfSightToPlayer(target)
	end)

	if result == "Reached" then
		return "Attack", npc, target
	end
	return "Idle", npc
end

local function attack(_changeState: StateMachine.ChangeState, npc: any, target: Player)
	npc:StopMoving()
	if npc:IsObserved() then
		return "Frozen", npc
	end

	local position = npc:GetTargetPosition(target)
	if not position then
		return "Idle", npc
	end

	npc:FaceTowards(position)
	if not npc:IsTouchingPlayer(target) then
		return "Chase", npc, target
	end

	npc:Attack(target)
	task.wait(npc.Config.AttackCooldown)
	return "Idle", npc
end

function WeepingAngel.new(model: Model, config)
	return NPC.new(model, config, WeepingAngel)
end

function WeepingAngel:BuildStateMachine(): StateMachine.StateMachine
	local npc = self

	return StateMachine.new({
		Idle = idle,
		Frozen = frozen,
		Chase = chase,
		Attack = attack,
		Despawn = NPC.SharedStates.Despawn,
		Stunned = NPC.SharedStates.Stunned,
	}, {
		Observed = { "Idle", "Chase", "Attack" },
		Released = { "Frozen" },
		-- A trap or a paper ball lands whatever it is doing, except while it is frozen under
		-- observation -- being watched already holds it still, and outranks being hit.
		Impact = { "Idle", "Chase", "Attack" },
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

				if npc.StateMachine.State == "Frozen" then
					local target = npc:GetNearestTarget()
					if target then
						npc.StateMachine:SetState("Chase", "Released", npc, target)
					else
						npc.StateMachine:SetState("Idle", "Released", npc)
					end
				elseif npc.StateMachine.State == "Idle" then
					local target = npc:GetNearestTarget()
					if target then
						npc.StateMachine:SetState("Chase", "root", npc, target)
					end
				end
			end
		end,
	}, "Idle", self)
end

return WeepingAngel
