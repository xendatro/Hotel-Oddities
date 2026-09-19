local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CrouchConfig = require(ReplicatedStorage.Configs.CrouchConfig)
local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local HallwaysService = require(ReplicatedStorage.Services.HallwaysService)
local NPC = require(ServerStorage.Classes.NPC)
local RoomService = require(ServerStorage.Services.RoomService)
local SpawnZoneService = require(ReplicatedStorage.Services.SpawnZoneService)

local PERCEPTION_INTERVAL = 0.25
local REST_CHECK_INTERVAL = 0.15
local CHASE_TARGET_ATTRIBUTE = "ChaseTargetUserId"
local CROUCH_ATTRIBUTE = CrouchConfig.Stealth.Attribute

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

local function wantsRest(npc: any): string?
	local chance = npc.Config.RestChance
	if not chance or chance <= 0 then return nil end
	if math.random() >= chance then return nil end
	return "Rest"
end

local function patrol(changeState: StateMachine.ChangeState, npc: any)
	clearChaseTarget(npc)
	npc.Animator:StopOverride()
	return NPC.SharedStates.Patrol(changeState, npc, wantsRest)
end

local function restSpot(npc: any): (Vector3?, HallwaysService.Hallway?, Vector3?)
	local origin = npc.RootPart.Position
	local hallway = HallwaysService.At(origin)
	if not hallway or hallway.IsRoomFloor then return nil, nil, nil end

	local offset = hallway.HalfWidth - (npc.Config.RestWallInset or 2)
	if offset <= 0 then return nil, nil, nil end

	local centre = HallwaysService.PointAt(hallway, HallwaysService.Along(hallway, origin))
	local side = if math.random() < 0.5 then 1 else -1
	local spot = centre + hallway.Across * (side * offset)
	if SpawnZoneService:Contains(spot) then return nil, nil, nil end
	return spot, hallway, centre
end

local function passerBy(npc: any, hallway: HallwaysService.Hallway, centre: Vector3, radius: number): Player?
	local origin = npc.RootPart.Position
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character or character:GetAttribute(CROUCH_ATTRIBUTE) == true then continue end
		local root = CharacterService.GetAliveRoot(player)
		if not root then continue end
		if (root.Position - origin).Magnitude > radius then continue end
		if math.abs((root.Position - centre):Dot(hallway.Across)) > hallway.HalfWidth then continue end
		return player
	end
	return nil
end

local function rest(_changeState: StateMachine.ChangeState, npc: any)
	clearChaseTarget(npc)
	npc.Target = nil

	local spot, hallway, centre = restSpot(npc)
	if not spot or not hallway or not centre then return "Patrol", npc end

	npc:SetSpeed(npc.Config.WalkSpeed)
	if not npc:WalkTo(spot) then return "Patrol", npc end

	npc:FaceTowards(centre)
	npc:StopMoving()
	npc:SetSpeed(0)
	npc.Animator:Pause()

	local animations = npc.Config.Animations
	local sleepId = animations and animations.Sleep
	if sleepId then npc.Animator:PlayOverride(sleepId) end

	local minimum = npc.Config.RestTimeMin or 20
	local deadline = os.clock() + minimum + math.random() * ((npc.Config.RestTimeMax or minimum) - minimum)
	local radius = npc.Config.RestWakeRadius or 16
	local woken: Player? = nil

	while os.clock() < deadline do
		task.wait(REST_CHECK_INTERVAL)
		woken = passerBy(npc, hallway, centre, radius)
		if woken then break end
	end

	if sleepId then npc.Animator:StopOverride() end

	if woken then
		local wakeId = animations and animations.Wake
		if wakeId then
			npc.Animator:PlayOverride(wakeId)
			task.wait(npc.Config.RestWakeTime or 1)
			npc.Animator:StopOverride()
		end
	end

	npc:SetSpeed(npc.Config.WalkSpeed)
	npc.Animator:Resume()

	if woken then return "Chase", npc, woken end
	return "Patrol", npc
end

local function stunned(changeState: StateMachine.ChangeState, npc: any, duration: number)
	clearChaseTarget(npc)
	npc.Animator:StopOverride()
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
	if safeRoom and allowRoomReaction ~= false and npc.Config.AllowRoomReaction ~= false then
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
		Retreat = NPC.SharedStates.Retreat,
		Search = search,
		RoomReaction = roomReaction,
		Stunned = stunned,
		Rest = rest,
	}, {
		Perception = { "Idle", "Wander", "Patrol", "Search" },
		Impact = { "Idle", "Wander", "Patrol", "Search", "Chase", "Attack", "RoomReaction", "Retreat", "Rest" },
	}, {
		Perception = npc:MakePerceptionEvaluator(PERCEPTION_INTERVAL, function()
			return npc:GetNearestVisibleTarget()
		end),
	}, "Idle", self)
end

return Chaser
