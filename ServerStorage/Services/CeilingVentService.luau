local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local AudioService = require(ReplicatedStorage.Services.AudioService)
local CrouchConfig = require(ReplicatedStorage.Configs.CrouchConfig)
local DangerConfig = require(ReplicatedStorage.Configs.DangerConfig)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local HallwayGraphService = require(ReplicatedStorage.Services.HallwayGraphService)
local NpcAnimator = require(ReplicatedStorage.Classes.NpcAnimator)
local TagService = require(ReplicatedStorage.Services.TagService)
local Vanished = require(ReplicatedStorage.Services.VanishedService)
local DangerMapService = require(ServerStorage.Services.DangerMapService)
local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local EnemyDirectorService = require(ServerStorage.Services.EnemyDirectorService)
local EnemyService = require(ServerStorage.Services.EnemyService)
local SurfaceWalker = require(ServerStorage.Classes.SurfaceWalker)

local CEILING_VENT_TAG = "CeilingVent"
local MAZE_FLOOR_TAG = "MazeFloor"
local DOOR_NAME = "Door"
local ENEMY_ID = "CeilingDweller"
local CROUCH_ATTRIBUTE = CrouchConfig.Stealth.Attribute

local POLL_INTERVAL = 0.15

local LIFETIME = DangerConfig.ProgrammaticVents.Lifetime

local DEFAULT_APPROACH_DISTANCE = 40
local DEFAULT_TRIGGER_HEIGHT = 20
local DEFAULT_APPROACH_MIN_SPEED = 6
local DEFAULT_APPROACH_DOT = 0.6

local IGNORE_BUDGET = true

local OPEN_ANGLE = math.rad(-100)
local DOOR_MOVE_TIME = 0.45
local DOOR_OPEN_TIME = 0.65
local OPEN_CUE_POINT = 0.6
local DROP_RAY_START_OFFSET = 2.5
local DROP_RAY_DISTANCE = 100
local MINIMUM_FLOOR_NORMAL = 0.5

local VIEW_ARC = 110
local MAX_VIEW_DISTANCE = 300
local DROP_SIGHT_HEIGHT = 4

local ENGAGEMENT_STATES = {
	Chase = true,
	Attack = true,
}
local DWELLER_SPAWN_GRACE = 4

local WALK_IN_LEAD = 10
local WALK_IN_SPEED = 9
local WALK_IN_MIN_DISTANCE = 24
local WALK_IN_MAX_DISTANCE = 140
local WALK_IN_MIN_PLAYER_DISTANCE = 22
local WALK_IN_START_ATTEMPTS = 8
local WALK_IN_CEILING_RAY = 60
local WALK_IN_DOOR_STOP = 3
local CLIMB_RISE = 5
local ENTRY_TIME = 1.1
local ENTRY_PITCH = math.rad(85)
local SPAWN_READY_DELAY = 3

local CameraEvent = CommunicationService.Ensure("Enemies", "CeilingDwellerCamera") :: RemoteEvent
local DoorEvent = CommunicationService.Ensure("Enemies", "CeilingVentDoor") :: RemoteEvent

type VentState = {
	Vent: Instance,
	Door: BasePart,
	DoorPivot: CFrame,
	SpawnPosition: Vector3,
	FallbackFacing: Vector3,
	TriggerHeight: number,
	ApproachDistance: number,
	ApproachMinSpeed: number,
	ApproachDot: number,
	ArmAt: number,
	Armed: { [Player]: boolean },
	DropPosition: Vector3?,
	DropNormal: Vector3?,
	DropSolved: boolean,
	Triggered: boolean,
	Spent: boolean,
	Enemy: any?,
	Alive: boolean,
	WalkIn: "Pending" | "Walking" | "Done",
	WalkInRig: Model?,
	WalkInWalker: any?,
}

local CeilingVentService = {}
local Accumulator = 0
local LiveDwellers: { any } = {}

if not FLAGS.Enemies then
	return CeilingVentService
end

local EnemyModels = ReplicatedStorage:WaitForChild("Enemies")
local WalkInFolder = Instance.new("Folder")
WalkInFolder.Name = "CeilingWalkIns"
WalkInFolder.Parent = workspace

local MazeFloors: { BasePart } = {}
local MazeFloorsDirty = true
local FloorParams = RaycastParams.new()
FloorParams.FilterType = Enum.RaycastFilterType.Include
FloorParams.RespectCanCollide = true

local function getMazeFloors(): { BasePart }
	if MazeFloorsDirty then
		MazeFloorsDirty = false
		table.clear(MazeFloors)
		for _, instance in CollectionService:GetTagged(MAZE_FLOOR_TAG) do
			if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
				table.insert(MazeFloors, instance)
			end
		end
		FloorParams.FilterDescendantsInstances = MazeFloors
	end
	return MazeFloors
end

local function markFloorsDirty()
	MazeFloorsDirty = true
end

CollectionService:GetInstanceAddedSignal(MAZE_FLOOR_TAG):Connect(markFloorsDirty)
CollectionService:GetInstanceRemovedSignal(MAZE_FLOOR_TAG):Connect(markFloorsDirty)

local function flattenFacing(facing: Vector3): Vector3
	local flat = Vector3.new(facing.X, 0, facing.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
end

local function getNumberAttribute(
	vent: Instance,
	name: string,
	default: number,
	minimum: number,
	maximum: number
): number
	local value = vent:GetAttribute(name)
	if value == nil then return default end
	if typeof(value) ~= "number" then
		warn(`CeilingVentService: {vent:GetFullName()}.{name} must be a number; using {default}`)
		return default
	end
	return math.clamp(value, minimum, maximum)
end

local function isHeadingToward(state: VentState, root: BasePart, toVent: Vector3): boolean
	local velocity = root.AssemblyLinearVelocity
	local heading = Vector3.new(velocity.X, 0, velocity.Z)
	if heading.Magnitude < state.ApproachMinSpeed then return false end
	if toVent.Magnitude < 1e-3 then return true end
	return heading.Unit:Dot(toVent.Unit) >= state.ApproachDot
end

local function getSpawnCFrame(state: VentState, triggeringPlayer: Player): CFrame
	local facing = state.FallbackFacing
	local root = CharacterService.GetAliveRoot(triggeringPlayer)
	if root then
		local towardPlayer = Vector3.new(
			root.Position.X - state.SpawnPosition.X,
			0,
			root.Position.Z - state.SpawnPosition.Z
		)
		if towardPlayer.Magnitude > 1e-3 then
			facing = towardPlayer.Unit
		end
	end
	return CFrame.lookAt(state.SpawnPosition, state.SpawnPosition + facing)
end

local function getDropSurface(state: VentState): (Vector3?, Vector3?)
	if state.DropSolved then return state.DropPosition, state.DropNormal end

	local floors = getMazeFloors()
	if #floors == 0 then return nil, nil end

	local origin = state.SpawnPosition - Vector3.yAxis * DROP_RAY_START_OFFSET
	local result = workspace:Raycast(origin, -Vector3.yAxis * DROP_RAY_DISTANCE, FloorParams)
	if not result or result.Normal.Y < MINIMUM_FLOOR_NORMAL then return nil, nil end

	state.DropPosition = result.Position
	state.DropNormal = result.Normal
	state.DropSolved = true
	return result.Position, result.Normal
end

local function moveDoor(state: VentState, target: CFrame, duration: number?, easing: string?): boolean
	if not state.Alive or not state.Door.Parent then return false end

	local moveTime = duration or DOOR_MOVE_TIME
	DoorEvent:FireAllClients(state.Door, target, moveTime, easing or "Quad")
	task.wait(moveTime)

	if not state.Alive or not state.Door.Parent then return false end
	state.Door:PivotTo(target)
	return true
end

local function canSeePoint(state: VentState, character: Model, eye: Vector3, look: Vector3, point: Vector3): boolean
	local offset = point - eye
	if offset.Magnitude > MAX_VIEW_DISTANCE then return false end
	if offset.Magnitude < 1e-3 then return true end

	local horizontalOffset = Vector3.new(offset.X, 0, offset.Z)
	local horizontalLook = Vector3.new(look.X, 0, look.Z)
	if horizontalOffset.Magnitude > 1e-3 and horizontalLook.Magnitude > 1e-3 then
		local minimumDot = math.cos(math.rad(VIEW_ARC / 2))
		if horizontalOffset.Unit:Dot(horizontalLook.Unit) < minimumDot then
			return false
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true

	local result = workspace:Raycast(eye, offset, params)
	return result == nil or result.Instance == state.Vent or result.Instance:IsDescendantOf(state.Vent)
end

local function isVentVisibleToPlayer(state: VentState, player: Player, root: BasePart): boolean
	local character = root.Parent :: Model
	local head = character:FindFirstChild("Head") :: BasePart?
	local eye = if head then head.Position else root.Position + Vector3.new(0, 1.5, 0)
	local look = root.CFrame.LookVector

	if canSeePoint(state, character, eye, look, state.Door.Position) then return true end

	local dropPosition = getDropSurface(state)
	return dropPosition ~= nil
		and canSeePoint(state, character, eye, look, dropPosition + Vector3.yAxis * DROP_SIGHT_HEIGHT)
end

local function cleanupWalkIn(state: VentState)
	local walker = state.WalkInWalker
	state.WalkInWalker = nil
	if walker then
		walker:Destroy()
	end

	local rig = state.WalkInRig
	state.WalkInRig = nil
	if rig then
		rig:Destroy()
	end
end

local function isPointHiddenFromPlayers(state: VentState, point: Vector3): boolean
	for _, player in Players:GetPlayers() do
		local root = CharacterService.GetAliveRoot(player)
		if root then
			local character = root.Parent :: Model
			local head = character:FindFirstChild("Head") :: BasePart?
			local eye = if head then head.Position else root.Position + Vector3.new(0, 1.5, 0)
			if canSeePoint(state, character, eye, root.CFrame.LookVector, point) then
				return false
			end
		end
	end
	return true
end

local function getCeilingContact(state: VentState, position: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true

	local excluded: { Instance } = { state.Vent, WalkInFolder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(excluded, player.Character)
		end
	end
	params.FilterDescendantsInstances = excluded

	local origin = position + Vector3.yAxis * 2
	local result = workspace:Raycast(origin, Vector3.yAxis * WALK_IN_CEILING_RAY, params)
	if result then
		return result.Position
	end
	return Vector3.new(position.X, state.SpawnPosition.Y, position.Z)
end

local function buildWalkInPath(state: VentState): { Vector3 }?
	local floorPosition = getDropSurface(state)
	if not floorPosition then return nil end

	local targetNode = HallwayGraphService:FindNearestNode(floorPosition)
	if not targetNode then return nil end

	local desired = WALK_IN_SPEED * WALK_IN_LEAD
	local candidates = {}
	for _, node in HallwayGraphService:Get() do
		if node == targetNode then continue end
		local distance = (node.Position - floorPosition).Magnitude
		if distance < WALK_IN_MIN_DISTANCE or distance > WALK_IN_MAX_DISTANCE then continue end
		if not HallwayGraphService:IsFarFromPlayers(node.Position, WALK_IN_MIN_PLAYER_DISTANCE) then continue end
		table.insert(candidates, { Node = node, Score = math.abs(distance - desired) })
	end
	table.sort(candidates, function(a, b)
		return a.Score < b.Score
	end)

	for index = 1, math.min(#candidates, WALK_IN_START_ATTEMPTS) do
		local startNode = candidates[index].Node
		if not isPointHiddenFromPlayers(state, getCeilingContact(state, startNode.Position)) then continue end

		local route = HallwayGraphService:FindPath(startNode, targetNode)
		if not route then continue end

		local points = {}
		for _, routeNode in route do
			table.insert(points, getCeilingContact(state, routeNode.Position))
		end

		local doorContact = getCeilingContact(state, floorPosition)
		local approach = doorContact - points[#points]
		local flatApproach = Vector3.new(approach.X, 0, approach.Z)
		if flatApproach.Magnitude > WALK_IN_DOOR_STOP then
			table.insert(points, doorContact - flatApproach.Unit * WALK_IN_DOOR_STOP)
		end

		if #points >= 2 then
			return points
		end
	end

	return nil
end

local function runWalkIn(state: VentState)
	state.WalkIn = "Walking"

	task.spawn(function()
		local finished = false
		local function finish(readyDelay: number?)
			if finished then return end
			finished = true
			cleanupWalkIn(state)
			if readyDelay and readyDelay > 0 then
				task.delay(readyDelay, function()
					if state.Alive then
						state.WalkIn = "Done"
					end
				end)
			else
				state.WalkIn = "Done"
			end
		end

		local template = EnemyModels:FindFirstChild(EnemyConfigs.CeilingDweller.Model)
		if not template then return finish() end

		local points = buildWalkInPath(state)
		if not points then return finish() end

		local rig = template:Clone() :: Model
		rig.Name = "CeilingDwellerWalkIn"
		rig:SetAttribute("EnemyId", nil)
		for _, tag in CollectionService:GetTags(rig) do
			CollectionService:RemoveTag(rig, tag)
		end
		for _, descendant in rig:GetDescendants() do
			for _, tag in CollectionService:GetTags(descendant) do
				CollectionService:RemoveTag(descendant, tag)
			end
		end
		rig:PivotTo(CFrame.new(points[1]))
		rig.Parent = WalkInFolder

		local animator = NpcAnimator.new(rig, EnemyConfigs.CeilingDweller.Animations)
		animator:Start()

		local walker = SurfaceWalker.new(rig, animator, -Vector3.yAxis)
		state.WalkInRig = rig
		state.WalkInWalker = walker

		local walked = walker:WalkAlong(points, WALK_IN_SPEED)
		if not walked or not state.Alive or not state.Vent:IsDescendantOf(workspace) then
			animator:Destroy()
			return finish()
		end

		AudioService:Play3DSound("VentOpen", state.Door, false, "SFX")
		local opened = moveDoor(state, state.DoorPivot * CFrame.Angles(OPEN_ANGLE, 0, 0), DOOR_OPEN_TIME, "Quad")
		if not opened or not state.WalkInRig then
			animator:Destroy()
			return finish()
		end

		local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
		local floorPosition = getDropSurface(state)
		if root and rig.Parent and floorPosition then
			animator:SetMovementSpeed(WALK_IN_SPEED)

			local start = root.CFrame
			local axis = start.RightVector
			local pitchSign = if axis:Cross(start.LookVector).Y >= 0 then 1 else -1
			local doorContact = getCeilingContact(state, floorPosition)
			local lip = Vector3.new(doorContact.X, start.Position.Y, doorContact.Z)
			local final = lip + Vector3.yAxis * CLIMB_RISE

			local elapsed = 0
			while elapsed < ENTRY_TIME do
				local deltaTime = RunService.Heartbeat:Wait()
				if not state.Alive or not root.Parent or not rig.Parent then break end
				elapsed = math.min(elapsed + deltaTime, ENTRY_TIME)

				local alpha = elapsed / ENTRY_TIME
				local eased = alpha * alpha * (3 - 2 * alpha)
				local inward = start.Position:Lerp(lip, eased)
				local upward = lip:Lerp(final, eased)
				local position = inward:Lerp(upward, eased)
				local rotation = CFrame.fromAxisAngle(axis, pitchSign * ENTRY_PITCH * eased) * start.Rotation
				root.CFrame = CFrame.new(position) * rotation
			end

			animator:SetMovementSpeed(0)
		end

		animator:Destroy()
		finish(SPAWN_READY_DELAY)
		moveDoor(state, state.DoorPivot, DOOR_MOVE_TIME, "Quad")
	end)
end

local function isEnemyEngaged(enemy: any): boolean
	if not enemy or not enemy.Active then return false end
	if enemy.Target ~= nil then return true end

	local machine = enemy.StateMachine
	return machine ~= nil and ENGAGEMENT_STATES[machine.State] == true
end

local function sweepDwellers(now: number)
	for index = #LiveDwellers, 1, -1 do
		local entry = LiveDwellers[index]
		local enemy = entry.Enemy
		if not enemy.Active or not enemy.Model or not enemy.Model.Parent then
			table.remove(LiveDwellers, index)
			continue
		end
		if now < entry.CullableAt then continue end
		if isEnemyEngaged(enemy) or enemy:IsObserved() then continue end

		enemy:Despawn()
		table.remove(LiveDwellers, index)
	end
end

local function hasLiveDweller(): boolean
	for _, entry in LiveDwellers do
		if entry.Enemy.Active then return true end
	end
	return false
end

local function canSpawn(): boolean
	if hasLiveDweller() then return false end
	if IGNORE_BUDGET then return true end
	return EnemyDirectorService:CanAfford(ENEMY_ID)
end

local function trigger(state: VentState, player: Player, forced: boolean?)
	if state.Triggered or not state.Alive then return end
	if not forced and state.WalkIn ~= "Done" then return end
	if not forced and not canSpawn() then return end
	if forced and state.WalkIn ~= "Done" then
		state.WalkIn = "Done"
		cleanupWalkIn(state)
	end
	state.Triggered = true

	task.spawn(function()
		AudioService:Play3DSound("VentOpen", state.Door, false, "SFX")
		if player.Parent == Players then
			task.delay(DOOR_OPEN_TIME * OPEN_CUE_POINT, function()
				if player.Parent == Players then
					CameraEvent:FireClient(player, "Open", DOOR_OPEN_TIME * (1 - OPEN_CUE_POINT))
				end
			end)
		end
		local opened = moveDoor(state, state.DoorPivot * CFrame.Angles(OPEN_ANGLE, 0, 0), DOOR_OPEN_TIME, "Bounce")
		if not opened or not state.Alive or not state.Vent:IsDescendantOf(workspace) then
			state.Spent = true
			return
		end

		local spawnCFrame = getSpawnCFrame(state, player)
		local floorPosition, floorNormal = getDropSurface(state)
		if not floorPosition then
			warn(
				`CeilingVentService: no "{MAZE_FLOOR_TAG}" floor found below `
					.. `{state.Vent:GetFullName()}; skipping spawn`
			)
			state.Spent = true
			return
		end

		local enemy = EnemyService:Spawn(ENEMY_ID, spawnCFrame, player, floorPosition, floorNormal)
		state.Enemy = enemy
		if enemy then
			table.insert(LiveDwellers, { Enemy = enemy, CullableAt = os.clock() + DWELLER_SPAWN_GRACE })
			EnemyDirectorService:Adopt(enemy, ENEMY_ID, true)
		end
		state.Spent = true
	end)
end

function CeilingVentService:GetVents(): { { Vent: Instance, Floor: Vector3, Triggered: boolean } }
	local vents = {}
	for _, state in TagService:GetAllApplied(CEILING_VENT_TAG) do
		if state.Alive then
			local floorPosition = getDropSurface(state)
			if floorPosition then
				table.insert(vents, { Vent = state.Vent, Floor = floorPosition, Triggered = state.Triggered })
			end
		end
	end
	table.sort(vents, function(a, b)
		return a.Vent:GetFullName() < b.Vent:GetFullName()
	end)
	return vents
end

function CeilingVentService:SpawnFromNearest(player: Player): boolean
	local root = CharacterService.GetAliveRoot(player)
	if not root then return false end

	local nearest: VentState? = nil
	local nearestDistance = math.huge
	for _, state in TagService:GetAllApplied(CEILING_VENT_TAG) do
		if state.Alive and not state.Triggered then
			local _, floorNormal = getDropSurface(state)
			if floorNormal then
				local distance = (state.SpawnPosition - root.Position).Magnitude
				if distance < nearestDistance then
					nearest = state
					nearestDistance = distance
				end
			end
		end
	end

	if not nearest then return false end
	trigger(nearest, player, true)
	return true
end

local function disablePhysicsQueries(vent: Instance)
	local function disable(instance: Instance)
		if instance:IsA("BasePart") then
			instance.CanCollide = false
			instance.CanQuery = false
			instance.CanTouch = false
		end
	end
	disable(vent)
	for _, descendant in vent:GetDescendants() do
		disable(descendant)
	end
end

TagService:Listen(CEILING_VENT_TAG, function(vent: Instance)
	local door = vent:FindFirstChild(DOOR_NAME, true)
	if not door or not door:IsA("BasePart") then
		warn(`CeilingVentService: {vent:GetFullName()} has no descendant BasePart named "{DOOR_NAME}"`)
		return nil
	end

	disablePhysicsQueries(vent)

	local spawnPosition = door.Position
	local danger = math.clamp(DangerMapService:GetDanger(spawnPosition), 0, 1)

	return {
		Vent = vent,
		Door = door,
		DoorPivot = door:GetPivot(),
		SpawnPosition = spawnPosition,
		FallbackFacing = flattenFacing(door.CFrame.LookVector),
		TriggerHeight = getNumberAttribute(vent, "TriggerHeight", DEFAULT_TRIGGER_HEIGHT, 1, 100),
		ApproachDistance = getNumberAttribute(vent, "ApproachDistance", DEFAULT_APPROACH_DISTANCE, 1, 200),
		ApproachMinSpeed = getNumberAttribute(vent, "ApproachMinSpeed", DEFAULT_APPROACH_MIN_SPEED, 0, 100),
		ApproachDot = getNumberAttribute(vent, "ApproachDot", DEFAULT_APPROACH_DOT, -1, 1),
		ArmAt = os.clock() + LIFETIME * (1 - danger),
		Armed = {},
		DropPosition = nil,
		DropNormal = nil,
		DropSolved = false,
		Triggered = false,
		Spent = false,
		Enemy = nil,
		Alive = true,
		WalkIn = "Pending",
		WalkInRig = nil,
		WalkInWalker = nil,
	} :: VentState
end, function(_vent: Instance, state: VentState?)
	if state then
		state.Alive = false
		cleanupWalkIn(state)
	end
end, workspace)

Players.PlayerRemoving:Connect(function(player: Player)
	for _, state in TagService:GetAllApplied(CEILING_VENT_TAG) do
		state.Armed[player] = nil
	end
end)

local TickPlayers: { Player } = {}
local TickRoots: { [Player]: BasePart? } = {}

RunService.Heartbeat:Connect(function(deltaTime: number)
	Accumulator += deltaTime
	if Accumulator < POLL_INTERVAL then return end
	Accumulator %= POLL_INTERVAL

	local now = os.clock()
	sweepDwellers(now)

	table.clear(TickPlayers)
	table.clear(TickRoots)
	for _, player in Players:GetPlayers() do
		table.insert(TickPlayers, player)
		TickRoots[player] = CharacterService.GetAliveRoot(player)
	end

	for _, state in TagService:GetAllApplied(CEILING_VENT_TAG) do
		if not state.Alive or state.Triggered then continue end

		if state.WalkIn == "Pending" and now >= state.ArmAt - WALK_IN_LEAD - SPAWN_READY_DELAY then
			runWalkIn(state)
		end

		for _, player in TickPlayers do
			local root = TickRoots[player]
			if not root or Vanished.Is(player.Character) then
				state.Armed[player] = nil
				continue
			end

			local offset = state.SpawnPosition - root.Position
			local toVent = Vector3.new(offset.X, 0, offset.Z)

			if toVent.Magnitude > state.ApproachDistance then
				state.Armed[player] = true
				continue
			end

			if now < state.ArmAt then continue end
			if state.WalkIn ~= "Done" then continue end
			if player.Character:GetAttribute(CROUCH_ATTRIBUTE) then continue end
			if offset.Y < 0 or offset.Y > state.TriggerHeight then continue end
			if not state.Armed[player] then continue end
			if not isHeadingToward(state, root, toVent) then continue end
			if not isVentVisibleToPlayer(state, player, root) then continue end

			state.Armed[player] = nil
			trigger(state, player)
			break
		end
	end
end)

return CeilingVentService
