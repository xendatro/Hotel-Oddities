local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local CollectionService = game:GetService("CollectionService")

local DangerConfig = require(ReplicatedStorage.Configs.DangerConfig)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local ChaosService = require(ServerStorage.Services.ChaosService)
local DangerMapService = require(ServerStorage.Services.DangerMapService)
local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local EnemyService = require(ServerStorage.Services.EnemyService)
local GhostAreaService = require(ServerStorage.Services.GhostAreaService)
local SistersService = require(ServerStorage.Services.SistersService)
local StalkerService = require(ServerStorage.Services.StalkerService)

local ENEMY_TAG = "Enemy"
local SPAWN_ROOT_HEIGHT = 3
local SIGHT_EYE_HEIGHT = 4
local RESERVATION_TIMEOUT = 20

type Managed = {
	Enemy: any,
	EnemyId: string,
	Config: EnemyConfigs.EnemyConfig,
	FarSince: number?,
	SelfManaged: boolean?,
}

type Reservation = {
	EnemyId: string,
	Config: EnemyConfigs.EnemyConfig,
	ExpiresAt: number,
	Filled: boolean,
}

local EnemyDirectorService = {}

function EnemyDirectorService:CanAfford(_enemyId: string): boolean
	return true
end

function EnemyDirectorService:Adopt(_enemy: any, _enemyId: string, _selfManaged: boolean?) end

function EnemyDirectorService:Reset() end

if not (FLAGS.Enemies and FLAGS.Director) then
	return EnemyDirectorService
end

local Config = DangerConfig.Director

local Population: { Managed } = {}
local Reservations: { Reservation } = {}
local NextPursuitSpawn: { [Player]: number } = {}
local NextPresenceSpawn: { [Player]: number } = {}
local NextGhostSpawn = 0

local TickAccumulator = 0
local DespawnAccumulator = 0

local Roster: { [string]: { string } } = { Pursuit = {}, Presence = {} }
for enemyId, config in EnemyConfigs do
	if config.SpawnWeight and config.SpawnWeight > 0 and config.Budget then
		local budget = Roster[config.Budget]
		if budget then
			table.insert(budget, enemyId)
		else
			warn(`[director] {enemyId} names an unknown budget "{config.Budget}"; it will never spawn`)
		end
	end
end
for _, ids in Roster do
	table.sort(ids)
end

local function horizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function getAliveRoot(player: Player): BasePart?
	local character = player.Character
	if not character then return nil end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then return nil end
	return root :: BasePart
end

local function getLivingPlayers(): { Player }
	local living = {}
	for _, player in Players:GetPlayers() do
		if getAliveRoot(player) then
			table.insert(living, player)
		end
	end
	return living
end

local function isEnemyAlive(entry: Managed): boolean
	local enemy = entry.Enemy
	if not enemy then return false end
	if enemy.Active == false then return false end

	local model = enemy.Model :: Model?
	return model ~= nil and model.Parent ~= nil
end

local function prunePopulation()
	for index = #Population, 1, -1 do
		if not isEnemyAlive(Population[index]) then
			table.remove(Population, index)
		end
	end

	local now = os.clock()
	for index = #Reservations, 1, -1 do
		local reservation = Reservations[index]
		if reservation.Filled or now >= reservation.ExpiresAt then
			table.remove(Reservations, index)
		end
	end
end

local function budgetCeiling(budget: string): number
	local playerCount = #getLivingPlayers()
	if playerCount == 0 then return 0 end

	if budget == "Pursuit" then
		return math.min(Config.PursuitPerPlayer * playerCount, Config.PursuitCap)
	end
	return math.min(Config.PresencePerPlayer * playerCount, Config.PresenceCap)
end

local function budgetSpent(budget: string): number
	local total = 0
	for _, entry in Population do
		if entry.Config.Budget == budget then
			total += entry.Config.Cost or 0
		end
	end
	for _, reservation in Reservations do
		if reservation.Config.Budget == budget then
			total += reservation.Config.Cost or 0
		end
	end
	return total
end

local function countAlive(enemyId: string): number
	local count = 0
	for _, entry in Population do
		if entry.EnemyId == enemyId then
			count += 1
		end
	end
	for _, reservation in Reservations do
		if reservation.EnemyId == enemyId then
			count += 1
		end
	end
	return count
end

local function rollEnemy(budget: string): string?
	local remaining = budgetCeiling(budget) - budgetSpent(budget)
	if remaining <= 0 then return nil end

	local eligible = {}
	local total = 0
	for _, enemyId in Roster[budget] do
		local config = EnemyConfigs[enemyId]
		local cost = config.Cost or 0
		local cap = config.MaxAlive or math.huge
		if cost <= remaining and countAlive(enemyId) < cap then
			total += config.SpawnWeight :: number
			table.insert(eligible, { EnemyId = enemyId, Ceiling = total })
		end
	end
	if total <= 0 then return nil end

	local roll = math.random() * total
	for _, candidate in eligible do
		if roll <= candidate.Ceiling then
			return candidate.EnemyId
		end
	end
	return eligible[#eligible].EnemyId
end

local function minimumSpawnDistance(config: EnemyConfigs.EnemyConfig): number
	local detection = config.DetectionRange or 0
	local vanish = config.DespawnRange or 0
	local derived = math.max(
		Config.MinSpawnDistance,
		detection * Config.DetectionMargin,
		vanish * Config.DetectionMargin
	)
	return math.min(derived, Config.MaxSpawnDistance * 0.6)
end

local function buildSightFilter(): { Instance }
	local filter = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(filter, player.Character)
		end
	end
	for _, model in CollectionService:GetTagged(ENEMY_TAG) do
		table.insert(filter, model)
	end
	return filter
end

local function isVisibleToAnybody(position: Vector3, filter: { Instance }): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	params.RespectCanCollide = true

	local head = position + Vector3.yAxis * SIGHT_EYE_HEIGHT
	for _, eye in EnemyObservationService:GetEyes() do
		local offset = head - eye
		if offset.Magnitude < 1e-3 then return true end
		if workspace:Raycast(eye, offset, params) == nil then return true end
	end
	return false
end

local function placeOnFloor(enemyId: string, config: EnemyConfigs.EnemyConfig, anchor: Player): any?
	local anchorRoot = getAliveRoot(anchor)
	if not anchorRoot then return nil end

	local minimum = minimumSpawnDistance(config)
	local living = getLivingPlayers()
	local filter = buildSightFilter()

	local point = DangerMapService:PickPoint(config.DangerBias or 1, function(candidate)
		local toAnchor = (candidate.Position - anchorRoot.Position).Magnitude
		if toAnchor < minimum or toAnchor > Config.MaxSpawnDistance then return false end

		for _, player in living do
			local root = getAliveRoot(player)
			if root and (candidate.Position - root.Position).Magnitude < minimum then
				return false
			end
		end

		return not isVisibleToAnybody(candidate.Position, filter)
	end, Config.PlacementAttempts)

	if not point then return nil end

	local origin = point.Position + Vector3.yAxis * SPAWN_ROOT_HEIGHT
	local away = horizontal(point.Position - anchorRoot.Position)
	local facing = if away.Magnitude > 1e-3 then away.Unit else anchorRoot.CFrame.LookVector

	return EnemyService:Spawn(enemyId, CFrame.lookAt(origin, origin + facing))
end

local function register(enemy: any, enemyId: string, config: EnemyConfigs.EnemyConfig, selfManaged: boolean?)
	if not enemy then return end

	if config.SpawnGrace then
		enemy.AcquireAfter = os.clock() + config.SpawnGrace
	end

	table.insert(Population, {
		Enemy = enemy,
		EnemyId = enemyId,
		Config = config,
		FarSince = nil,
		SelfManaged = selfManaged,
	})
end

function EnemyDirectorService:CanAfford(enemyId: string): boolean
	local config = EnemyConfigs[enemyId]
	if not config or not config.Budget then return true end

	prunePopulation()
	if countAlive(enemyId) >= (config.MaxAlive or math.huge) then return false end
	return (config.Cost or 0) <= budgetCeiling(config.Budget) - budgetSpent(config.Budget)
end

function EnemyDirectorService:Adopt(enemy: any, enemyId: string, selfManaged: boolean?)
	register(enemy, enemyId, EnemyConfigs[enemyId], selfManaged)
end

local function spawnFor(enemyId: string, anchor: Player): boolean
	local config = EnemyConfigs[enemyId]

	if enemyId == "Chaos" then
		local reservation: Reservation = {
			EnemyId = enemyId,
			Config = config,
			ExpiresAt = os.clock() + (config.SpawnDelay or 0) + RESERVATION_TIMEOUT,
			Filled = false,
		}
		table.insert(Reservations, reservation)

		local scheduled = ChaosService:Spawn(function(chaos: any)
			reservation.Filled = true
			register(chaos, enemyId, config)
		end)
		if not scheduled then
			reservation.Filled = true
		end
		return scheduled
	end

	if enemyId == "Sisters" then
		local sisters = SistersService:Spawn()
		register(sisters, enemyId, config)
		return sisters ~= nil
	end

	if config.SpawnPeeking then
		local peeker = StalkerService:SpawnPeeking(anchor, enemyId)
		register(peeker, enemyId, config)
		return peeker ~= nil
	end

	local enemy = placeOnFloor(enemyId, config, anchor)
	register(enemy, enemyId, config)
	return enemy ~= nil
end

local function spawnGhost(now: number)
	local config = EnemyConfigs.Ghost
	if now < NextGhostSpawn or countAlive("Ghost") >= (config.MaxAlive or 1) then return end
	NextGhostSpawn = now + (config.SpawnInterval or 20)
	local point = GhostAreaService:GetRandomPoint()
	if not point then return end
	local enemy = EnemyService:Spawn("Ghost", CFrame.lookAt(point, point + Vector3.zAxis))
	register(enemy, "Ghost", config, true)
end

local function intervalFor(danger: number, quiet: number, busy: number, floor: number): number
	return math.max(floor, quiet + (busy - quiet) * math.clamp(danger, 0, 1))
end

local function tickPlayer(player: Player, now: number)
	local root = getAliveRoot(player)
	if not root then return end

	local danger = DangerMapService:GetDanger(root.Position)

	if now >= (NextPursuitSpawn[player] or 0) then
		NextPursuitSpawn[player] = now + intervalFor(
			danger,
			Config.PursuitQuietInterval,
			Config.PursuitBusyInterval,
			Config.PursuitFloorInterval
		)
		local enemyId = rollEnemy("Pursuit")
		if enemyId then
			spawnFor(enemyId, player)
		end
	end

	if now >= (NextPresenceSpawn[player] or 0) then
		NextPresenceSpawn[player] = now + intervalFor(
			danger,
			Config.PresenceQuietInterval,
			Config.PresenceBusyInterval,
			Config.PresenceFloorInterval
		)
		local enemyId = rollEnemy("Presence")
		if enemyId then
			spawnFor(enemyId, player)
		end
	end
end

local ENGAGED_STATES = {
	Chase = true,
	Attack = true,
	Stalk = true,
	Reveal = true,
	Investigate = true,
	Flee = true,
}

local function isEngaged(enemy: any): boolean
	if enemy.Target ~= nil then return true end

	local machine = enemy.StateMachine
	return machine ~= nil and ENGAGED_STATES[machine.State] == true
end

local function sweepDespawns(now: number)
	local despawnDistance = DangerMapService:GetExtent() * DangerConfig.DespawnDistanceFraction
	local living = getLivingPlayers()
	local filter = buildSightFilter()

	for _, entry in Population do
		if not isEnemyAlive(entry) or entry.SelfManaged then continue end

		local enemy = entry.Enemy
		local model = enemy.Model :: Model
		local position = model:GetPivot().Position

		local nearest = math.huge
		for _, player in living do
			local root = getAliveRoot(player)
			if root then
				nearest = math.min(nearest, (position - root.Position).Magnitude)
			end
		end

		local cullable = nearest > despawnDistance
			and not isEngaged(enemy)
			and not isVisibleToAnybody(position, filter)

		if not cullable then
			entry.FarSince = nil
			continue
		end

		entry.FarSince = entry.FarSince or now
		if now - entry.FarSince >= DangerConfig.DespawnGrace then
			enemy:Despawn()
		end
	end
end

function EnemyDirectorService:GetPopulation(): { Budget: { [string]: number }, Enemies: { string } }
	prunePopulation()

	local names = {}
	for _, entry in Population do
		table.insert(names, entry.EnemyId)
	end
	table.sort(names)

	return {
		Budget = {
			Pursuit = budgetSpent("Pursuit"),
			PursuitCeiling = budgetCeiling("Pursuit"),
			Presence = budgetSpent("Presence"),
			PresenceCeiling = budgetCeiling("Presence"),
		},
		Enemies = names,
	}
end

function EnemyDirectorService:Reset()
	for _, entry in Population do
		if isEnemyAlive(entry) and not entry.SelfManaged then
			entry.Enemy:Despawn()
		end
	end
	table.clear(Population)
	table.clear(Reservations)
	table.clear(NextPursuitSpawn)
	table.clear(NextPresenceSpawn)
	NextGhostSpawn = 0
end

RunService.Heartbeat:Connect(function(deltaTime: number)
	TickAccumulator += deltaTime
	DespawnAccumulator += deltaTime

	local now = os.clock()

	if TickAccumulator >= Config.TickInterval then
		TickAccumulator = 0
		prunePopulation()
		for _, player in Players:GetPlayers() do
			tickPlayer(player, now)
		end
		if #getLivingPlayers() > 0 then spawnGhost(now) end
	end

	if DespawnAccumulator >= Config.DespawnCheckInterval then
		DespawnAccumulator = 0
		sweepDespawns(now)
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	NextPursuitSpawn[player] = nil
	NextPresenceSpawn[player] = nil
end)

return EnemyDirectorService
