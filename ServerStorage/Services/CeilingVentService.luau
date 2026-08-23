local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local AudioService = require(ReplicatedStorage.Services.AudioService)
local CrouchConfig = require(ReplicatedStorage.Configs.CrouchConfig)
local DangerConfig = require(ReplicatedStorage.Configs.DangerConfig)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local TagService = require(ReplicatedStorage.Services.TagService)
local Vanished = require(ReplicatedStorage.Modules.Vanished)
local DangerMapService = require(ServerStorage.Services.DangerMapService)
local EnemyDirectorService = require(ServerStorage.Services.EnemyDirectorService)
local EnemyService = require(ServerStorage.Services.EnemyService)

local CEILING_VENT_TAG = "CeilingVent"
local MAZE_FLOOR_TAG = "MazeFloor"
local DOOR_NAME = "Door"
local ENEMY_ID = "CeilingDweller"
local CROUCH_ATTRIBUTE = CrouchConfig.Stealth.Attribute

local POLL_INTERVAL = 0.15

--- A vent arms at spawn + Lifetime * (1 - danger), so a vent in a fully dangerous
--- spot is live the moment it appears and one in a safe spot arms exactly as its
--- lifetime runs out, meaning it never fires. Crossing before the arm time does
--- nothing; the first crossing after it always fires. There is no roll to farm.
local LIFETIME = DangerConfig.ProgrammaticVents.Lifetime

--- Radius of the trip ring, in studs. The player crosses this circle heading
--- inward and the dweller drops, so this doubles as how far ahead it lands.
local DEFAULT_APPROACH_DISTANCE = 40
--- How far below the vent the player may be and still trip it.
local DEFAULT_TRIGGER_HEIGHT = 20
--- Studs/second the player must be moving before a crossing counts.
local DEFAULT_APPROACH_MIN_SPEED = 6
--- Dot of travel direction against direction to the vent; 0.6 is a ~53 degree cone.
local DEFAULT_APPROACH_DOT = 0.6

--- Ignore the shared Pursuit budget, so an armed vent always fires on contact.
--- One dweller at a time is still enforced locally.
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
--- Height above the landing spot to aim the second sight ray at.
local DROP_SIGHT_HEIGHT = 4

--- A dweller is culled the moment it is neither chasing nor watched. The vent it
--- came from is on its own clock; neither waits for the other.
local ENGAGEMENT_STATES = {
	Chase = true,
	Attack = true,
}
--- Seconds of immunity after spawning, covering the drop tween before the state
--- machine reports Chase. Without it the sweep can cull a dweller mid-fall.
local DWELLER_SPAWN_GRACE = 4

local function getEnemyEvent(name: string): RemoteEvent
	local communication = ReplicatedStorage:FindFirstChild("Communication")
	if not communication then
		communication = Instance.new("Folder")
		communication.Name = "Communication"
		communication.Parent = ReplicatedStorage
	end
	local enemies = communication:FindFirstChild("Enemies")
	if not enemies then
		enemies = Instance.new("Folder")
		enemies.Name = "Enemies"
		enemies.Parent = communication
	end
	local event = enemies:FindFirstChild(name)
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = enemies
	end
	return event :: RemoteEvent
end

local CameraEvent = getEnemyEvent("CeilingDwellerCamera")
local DoorEvent = getEnemyEvent("CeilingVentDoor")

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
}

local CeilingVentService = {}
local Accumulator = 0
local LiveDwellers: { any } = {}

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

local function isHeadingToward(state: VentState, root: BasePart, toVent: Vector3): boolean
	local velocity = root.AssemblyLinearVelocity
	local heading = Vector3.new(velocity.X, 0, velocity.Z)
	if heading.Magnitude < state.ApproachMinSpeed then return false end
	if toVent.Magnitude < 1e-3 then return true end
	return heading.Unit:Dot(toVent.Unit) >= state.ApproachDot
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
	if state.DropSolved then return state.DropPosition, state.DropNormal end

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

	local origin = state.SpawnPosition - Vector3.yAxis * DROP_RAY_START_OFFSET
	local result = workspace:Raycast(origin, -Vector3.yAxis * DROP_RAY_DISTANCE, params)
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

local function isVentVisibleToPlayer(state: VentState, player: Player): boolean
	local root = getAliveRoot(player)
	if not root then return false end

	local character = root.Parent :: Model
	local head = character:FindFirstChild("Head") :: BasePart?
	local eye = if head then head.Position else root.Position + Vector3.new(0, 1.5, 0)
	local look = root.CFrame.LookVector

	if canSeePoint(state, character, eye, look, state.Door.Position) then return true end

	local dropPosition = getDropSurface(state)
	return dropPosition ~= nil
		and canSeePoint(state, character, eye, look, dropPosition + Vector3.yAxis * DROP_SIGHT_HEIGHT)
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
	if not forced and not canSpawn() then return end
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
	local root = getAliveRoot(player)
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
	} :: VentState
end, function(_vent: Instance, state: VentState?)
	if state then
		state.Alive = false
	end
end, workspace)

Players.PlayerRemoving:Connect(function(player: Player)
	for _, state in TagService:GetAllApplied(CEILING_VENT_TAG) do
		state.Armed[player] = nil
	end
end)

RunService.Heartbeat:Connect(function(deltaTime: number)
	Accumulator += deltaTime
	if Accumulator < POLL_INTERVAL then return end
	Accumulator %= POLL_INTERVAL

	local now = os.clock()
	sweepDwellers(now)

	for _, state in TagService:GetAllApplied(CEILING_VENT_TAG) do
		if not state.Alive or state.Triggered then continue end

		for _, player in Players:GetPlayers() do
			local root = getAliveRoot(player)
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
			if player.Character:GetAttribute(CROUCH_ATTRIBUTE) then continue end
			if offset.Y < 0 or offset.Y > state.TriggerHeight then continue end
			if not state.Armed[player] then continue end
			if not isHeadingToward(state, root, toVent) then continue end
			if not isVentVisibleToPlayer(state, player) then continue end

			state.Armed[player] = nil
			trigger(state, player)
			break
		end
	end
end)

return CeilingVentService
