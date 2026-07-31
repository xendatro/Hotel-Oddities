--- Turns tagged ceiling vents into reusable CeilingDweller ambushes.
---
--- A vent is any instance in workspace tagged `CeilingVent` with a descendant BasePart named
--- `Door`. Players underneath it get spaced chances to spring it, so walking through may or may not
--- wake it while lingering eventually will. Once sprung, its door swings around the authored part
--- pivot and one CeilingDweller drops from the opening; its class delegates to the Chaser state
--- machine from there. The vent remains spent while the enemy is active. Once every player has left
--- and nobody can see the vent, that particular enemy is despawned, the door closes, and the
--- approach trigger is armed again.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local TagService = require(ReplicatedStorage.Services.TagService)
local EnemyService = require(ServerStorage.Services.EnemyService)

local CEILING_VENT_TAG = "CeilingVent"
local MAZE_FLOOR_TAG = "MazeFloor"
local DOOR_NAME = "Door"
local ENEMY_ID = "CeilingDweller"

local POLL_INTERVAL = 0.15
local DEFAULT_TRIGGER_RADIUS = 14
local DEFAULT_TRIGGER_HEIGHT = 20
local DEFAULT_TRIGGER_CHANCE = 0.35
local DEFAULT_RETRY_INTERVAL = 0.75

local OPEN_ANGLE = math.rad(-45)
local DOOR_MOVE_TIME = 0.45
local DROP_RAY_START_OFFSET = 2.5
local DROP_RAY_DISTANCE = 100
local MINIMUM_FLOOR_NORMAL = 0.5

-- This mirrors the broad horizontal pre-check used by EnemyObservationService. The server does not
-- receive camera orientation, so character facing is intentionally conservative: if somebody is
-- facing the vent and has clear sight of it, it stays open even if their camera might be pitched
-- elsewhere.
local VIEW_ARC = 110
local MAX_VIEW_DISTANCE = 300
local ENGAGEMENT_STATES = {
	Chase = true,
	Attack = true,
}

type VentState = {
	Vent: Instance,
	Door: BasePart,
	DoorPivot: CFrame,
	SpawnPosition: Vector3,
	FallbackFacing: Vector3,
	TriggerRadius: number,
	TriggerHeight: number,
	TriggerChance: number,
	RetryInterval: number,
	NextRollAt: { [Player]: number },
	Triggered: boolean,
	ReadyToReset: boolean,
	Resetting: boolean,
	Enemy: any?,
	Alive: boolean,
}

local CeilingVentService = {}
local Accumulator = 0

if not FLAGS.Enemies then
	return CeilingVentService
end

local function getAliveRoot(player: Player): BasePart?
	local character = player.Character
	if not character then return nil end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then return nil end
	return root :: BasePart
end

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

local function isUnderVent(state: VentState, root: BasePart): boolean
	local offset = root.Position - state.SpawnPosition
	local horizontalDistance = Vector2.new(offset.X, offset.Z).Magnitude
	local heightAbovePlayer = -offset.Y
	return horizontalDistance <= state.TriggerRadius
		and heightAbovePlayer >= 0
		and heightAbovePlayer <= state.TriggerHeight
end

local function getSpawnCFrame(state: VentState, triggeringPlayer: Player): CFrame
	local facing = state.FallbackFacing
	local root = getAliveRoot(triggeringPlayer)
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
	local floors = {}
	for _, instance in CollectionService:GetTagged(MAZE_FLOOR_TAG) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
			table.insert(floors, instance)
		end
	end
	if #floors == 0 then return nil, nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = floors
	params.RespectCanCollide = true

	-- Begin below the vent/roof slab and only admit authored maze floors. The vent, roof, characters,
	-- props and live enemies therefore cannot become an accidental landing surface.
	local origin = state.SpawnPosition - Vector3.yAxis * DROP_RAY_START_OFFSET
	local result = workspace:Raycast(origin, -Vector3.yAxis * DROP_RAY_DISTANCE, params)
	if not result or result.Normal.Y < MINIMUM_FLOOR_NORMAL then return nil, nil end
	return result.Position, result.Normal
end

local function moveDoor(state: VentState, target: CFrame): boolean
	if not state.Alive or not state.Door.Parent then return false end

	local value = Instance.new("CFrameValue")
	value.Value = state.Door:GetPivot()

	local changed = value:GetPropertyChangedSignal("Value"):Connect(function()
		if state.Alive and state.Door.Parent then
			state.Door:PivotTo(value.Value)
		end
	end)

	local tween = TweenService:Create(
		value,
		TweenInfo.new(DOOR_MOVE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = target }
	)
	tween:Play()
	tween.Completed:Wait()

	changed:Disconnect()
	value:Destroy()
	if not state.Alive or not state.Door.Parent then return false end

	state.Door:PivotTo(target)
	return true
end

local function isVentVisibleToPlayer(state: VentState, player: Player): boolean
	local root = getAliveRoot(player)
	if not root then return false end

	local character = root.Parent :: Model
	local head = character:FindFirstChild("Head") :: BasePart?
	local eye = if head then head.Position else root.Position + Vector3.new(0, 1.5, 0)
	local offset = state.Door.Position - eye
	if offset.Magnitude > MAX_VIEW_DISTANCE then return false end

	local horizontalOffset = Vector3.new(offset.X, 0, offset.Z)
	local horizontalLook = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
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

	if offset.Magnitude < 1e-3 then return true end
	local result = workspace:Raycast(eye, offset, params)
	return result == nil or result.Instance == state.Vent or result.Instance:IsDescendantOf(state.Vent)
end

local function isEnemyEngaged(state: VentState): boolean
	local enemy = state.Enemy
	if not enemy or not enemy.Active then return false end
	if enemy.Target ~= nil then return true end

	local machine = enemy.StateMachine
	return machine ~= nil and ENGAGEMENT_STATES[machine.State] == true
end

local function canReset(state: VentState): boolean
	-- Looking away from the vent is never enough to erase an enemy that is still hunting somebody.
	-- Chaser clears Target as it enters Search, which is the first disengaged state eligible here.
	if isEnemyEngaged(state) then return false end

	for _, player in Players:GetPlayers() do
		local root = getAliveRoot(player)
		if root then
			if isUnderVent(state, root) then
				return false
			end
			if isVentVisibleToPlayer(state, player) then
				return false
			end
		end
	end
	return true
end

local function reset(state: VentState)
	if state.Resetting or not state.ReadyToReset then return end
	state.Resetting = true

	task.spawn(function()
		-- The vent stays Triggered throughout teardown. It cannot roll another approach until its
		-- own enemy is inactive and the panel has reached the authored closed pivot.
		if state.Enemy then
			state.Enemy:Despawn()
			state.Enemy = nil
		end
		local closed = moveDoor(state, state.DoorPivot)
		if not state.Alive or not closed then return end

		state.NextRollAt = {}
		state.ReadyToReset = false
		state.Resetting = false
		state.Triggered = false
	end)
end

local function trigger(state: VentState, player: Player)
	if state.Triggered or not state.Alive then return end
	state.Triggered = true

	task.spawn(function()
		local opened = moveDoor(state, state.DoorPivot * CFrame.Angles(OPEN_ANGLE, 0, 0))
		if not opened or not state.Alive or not state.Vent:IsDescendantOf(workspace) then return end

		local spawnCFrame = getSpawnCFrame(state, player)
		local floorPosition, floorNormal = getDropSurface(state)
		if not floorPosition then
			warn(
				`CeilingVentService: no "{MAZE_FLOOR_TAG}" floor found below `
					.. `{state.Vent:GetFullName()}; skipping spawn`
			)
			state.ReadyToReset = true
			return
		end

		state.Enemy = EnemyService:Spawn(ENEMY_ID, spawnCFrame, player, floorPosition, floorNormal)
		state.ReadyToReset = true
	end)
end

TagService:Listen(CEILING_VENT_TAG, function(vent: Instance)
	local door = vent:FindFirstChild(DOOR_NAME, true)
	if not door or not door:IsA("BasePart") then
		warn(`CeilingVentService: {vent:GetFullName()} has no descendant BasePart named "{DOOR_NAME}"`)
		return nil
	end

	return {
		Vent = vent,
		Door = door,
		DoorPivot = door:GetPivot(),
		SpawnPosition = door.Position,
		FallbackFacing = flattenFacing(door.CFrame.LookVector),
		TriggerRadius = getNumberAttribute(vent, "TriggerRadius", DEFAULT_TRIGGER_RADIUS, 1, 100),
		TriggerHeight = getNumberAttribute(vent, "TriggerHeight", DEFAULT_TRIGGER_HEIGHT, 1, 100),
		TriggerChance = getNumberAttribute(vent, "TriggerChance", DEFAULT_TRIGGER_CHANCE, 0, 1),
		RetryInterval = getNumberAttribute(vent, "TriggerRetryInterval", DEFAULT_RETRY_INTERVAL, 0.1, 60),
		NextRollAt = {},
		Triggered = false,
		ReadyToReset = false,
		Resetting = false,
		Enemy = nil,
		Alive = true,
	} :: VentState
end, function(_vent: Instance, state: VentState?)
	if state then
		state.Alive = false
		if state.Enemy then
			state.Enemy:Despawn()
			state.Enemy = nil
		end
	end
end, workspace)

Players.PlayerRemoving:Connect(function(player: Player)
	for _, state in TagService:GetAllApplied(CEILING_VENT_TAG) do
		state.NextRollAt[player] = nil
	end
end)

RunService.Heartbeat:Connect(function(deltaTime: number)
	Accumulator += deltaTime
	if Accumulator < POLL_INTERVAL then return end
	Accumulator %= POLL_INTERVAL

	for _, state in TagService:GetAllApplied(CEILING_VENT_TAG) do
		if not state.Alive then continue end
		if state.Triggered then
			if state.ReadyToReset and not state.Resetting and canReset(state) then
				reset(state)
			end
			continue
		end

		local now = os.clock()
		for _, player in Players:GetPlayers() do
			local root = getAliveRoot(player)
			local isNearby = root ~= nil and isUnderVent(state, root)
			if not isNearby then
				state.NextRollAt[player] = nil
				continue
			end

			local nextRollAt = state.NextRollAt[player]
			if nextRollAt and now < nextRollAt then continue end
			state.NextRollAt[player] = now + state.RetryInterval

			if math.random() < state.TriggerChance then
				trigger(state, player)
				break
			end
		end
	end
end)

return CeilingVentService
