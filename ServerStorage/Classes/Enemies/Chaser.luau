local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local NPC = require(ServerStorage.Classes.NPC)
local RoomService = require(ServerStorage.Services.RoomService)

local PERCEPTION_INTERVAL = 0.25
local CHASE_TARGET_ATTRIBUTE = "ChaseTargetUserId"

local Chaser = NPC.extend("Chaser")
Chaser.AttackLostState = "Search"

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

local function chase(
	_changeState: StateMachine.ChangeState,
	npc: any,
	target: Player,
	allowRoomReaction: boolean?
)
	npc:BeginChase(target)
	npc.Model:SetAttribute(CHASE_TARGET_ATTRIBUTE, target.UserId)

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
	if safeRoom and allowRoomReaction ~= false then
		return "RoomReaction", npc, safeRoom, target
	end
	return "Search", npc, lastKnown
end

local attack = NPC.SharedStates.Attack

local function search(_changeState: StateMachine.ChangeState, npc: any, _lastKnown: Vector3)
	clearChaseTarget(npc)
	npc.Target = nil
	npc.Animator:Resume()
	npc:SetSpeed(npc.Config.WalkSpeed)
	return "Patrol", npc
end

local function roomReaction(
	changeState: StateMachine.ChangeState,
	npc: any,
	room: Model,
	target: Player?
)
	clearChaseTarget(npc)
	local shouldCancel = if target
		then function()
			return not RoomService:IsInRoom(target)
		end
		else nil
	local nextState, nextNpc = NPC.SharedStates.RoomReaction(
		changeState,
		npc,
		room,
		npc.Config.ChaseSpeed,
		shouldCancel
	)
	if target and not RoomService:IsInRoom(target) then
		return "Chase", npc, target
	end
	return nextState, nextNpc
end

Chaser.Chase = chase

local function applyVariant(model: Model, config)
	local hairs = model:FindFirstChild("Hairs")
	local variants = config.Variants
	if not variants or #variants == 0 then
		if hairs then hairs:Destroy() end
		return
	end

	local variant = variants[math.random(#variants)]

	local bodyColors = model:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		bodyColors.HeadColor3 = variant.SkinColor
		bodyColors.TorsoColor3 = variant.SkinColor
		bodyColors.LeftArmColor3 = variant.SkinColor
		bodyColors.RightArmColor3 = variant.SkinColor
		bodyColors.LeftLegColor3 = variant.SkinColor
		bodyColors.RightLegColor3 = variant.SkinColor
	end

	if hairs then
		local hair = hairs:FindFirstChild(variant.Hair)
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if hair and hair:IsA("Accessory") and humanoid then
			for _, child in model:GetChildren() do
				if child:IsA("Accessory") then
					child:Destroy()
				end
			end
			hair.Parent = nil
			humanoid:AddAccessory(hair)
		end
		hairs:Destroy()
	end
end

function Chaser.new(model: Model, config)
	applyVariant(model, config)
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
		Perception = npc:MakePerceptionEvaluator(PERCEPTION_INTERVAL, function()
			return npc:GetNearestVisibleTarget()
		end),
	}, "Idle", self)
end

return Chaser
