local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local DangerConfig = require(ReplicatedStorage.Configs.DangerConfig)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local MathService = require(ReplicatedStorage.Services.MathService)
local ChaosService = require(ServerStorage.Services.ChaosService)
local DangerMapService = require(ServerStorage.Services.DangerMapService)
local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local EnemyService = require(ServerStorage.Services.EnemyService)
local GhostAreaService = require(ServerStorage.Services.GhostAreaService)
local HallwayGraphService = require(ReplicatedStorage.Services.HallwayGraphService)
local SistersService = require(ServerStorage.Services.SistersService)
local StalkerService = require(ServerStorage.Services.StalkerService)

local ENEMY_TAG = "Enemy"
local SPAWN_ROOT_HEIGHT = 3
local SIGHT_EYE_HEIGHT = 4
local CHAOS_PENDING_TIMEOUT = 20

type ResidentSpec = {
	Count: number,
	Lifetime: number?,
	Respawn: number?,
	Placement: string?,
}

type Managed = {
	Enemy: any,
	EnemyId: string,
	Config: EnemyConfigs.EnemyConfig,
	SelfManaged: boolean?,
	ExpiresAt: number?,
}

local EnemyDirectorService = {}

function EnemyDirectorService:CanAfford(_enemyId: string): boolean
	return true
end

function EnemyDirectorService:Adopt(_enemy: any, _enemyId: string, _selfManaged: boolean?) end

function EnemyDirectorService:Reset() end

function EnemyDirectorService:GetPopulation()
	return { Residents = {}, Enemies = {} }
end

function EnemyDirectorService:GetStalkerTarget(): Player?
	return nil
end

if not (FLAGS.Enemies and FLAGS.Director) then
	return EnemyDirectorService
end

local Config = DangerConfig.Director

local Population: { Managed } = {}
local NextResidentSpawn: { [string]: number } = {}
local NextGhostSpawn = 0
local NextChaosSpawn = 0
local StalkerQueue: { Player } = {}
local StalkerIndex = 0
local StalkerTarget = nil :: Player?
local StalkerRetries = 0
local StalkerWasAlive = false
local NextStalkerAt = 0
local ChaosPendingUntil = 0

local TickAccumulator = 0
local DespawnAccumulator = 0

local Residents: { [string]: ResidentSpec } = Config.Residents or {}
for enemyId, spec in Residents do
	if not EnemyConfigs[enemyId] then
		warn(`[director] residents name an unknown enemy "{enemyId}"; it will never spawn`)
	elseif type(spec) ~= "table" or type(spec.Count) ~= "number" then
		warn(`[director] resident "{enemyId}" has no numeric Count; it will never spawn`)
	end
end

local horizontal = MathService.Horizontal
local getAliveRoot = CharacterService.GetAliveRoot

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
	local now = os.clock()

	for index = #Population, 1, -1 do
		local entry = Population[index]
		if not isEnemyAlive(entry) then
			local spec = Residents[entry.EnemyId]
			if spec then
				NextResidentSpawn[entry.EnemyId] = now
					+ (spec.Respawn or Config.ResidentRespawnDelay or 0)
			end
			table.remove(Population, index)
		end
	end
end

local function countAlive(enemyId: string): number
	local count = 0
	for _, entry in Population do
		if entry.EnemyId == enemyId then
			count += 1
		end
	end
	return count
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

local function playerPositions(living: { Player }): { Vector3 }
	local positions = {}
	for _, player in living do
		local root = getAliveRoot(player)
		if root then
			table.insert(positions, root.Position)
		end
	end
	return positions
end

local function enemyPositions(): { Vector3 }
	local positions = {}
	for _, model in CollectionService:GetTagged(ENEMY_TAG) do
		if model:IsA("Model") and model.Parent then
			table.insert(positions, model:GetPivot().Position)
		end
	end
	return positions
end

local function nearestDistance(position: Vector3, points: { Vector3 }): number
	local nearest = math.huge
	for _, point in points do
		nearest = math.min(nearest, (position - point).Magnitude)
	end
	return nearest
end

local function scorePoint(
	position: Vector3,
	danger: number,
	bias: number,
	minimum: number,
	players: { Vector3 },
	enemies: { Vector3 }
): number
	local weights = Config.Placement

	local toPlayer = nearestDistance(position, players)
	local proximity = 1
		- math.clamp((toPlayer - minimum) / math.max(weights.PlayerFalloff, 1), 0, 1)

	local toEnemy = nearestDistance(position, enemies)
	local spacing = math.clamp(toEnemy / math.max(weights.EnemySpacing, 1), 0, 1)

	return weights.DangerWeight * math.clamp(danger, 0, 1) ^ math.max(bias, 0.01)
		+ weights.PlayerProximityWeight * proximity
		+ weights.EnemySpacingWeight * spacing
end

local function spawnAt(enemyId: string, position: Vector3, facing: Vector3): any?
	local origin = position + Vector3.yAxis * SPAWN_ROOT_HEIGHT
	local look = if facing.Magnitude > 1e-3 then facing.Unit else Vector3.zAxis
	return EnemyService:Spawn(enemyId, CFrame.lookAt(origin, origin + look))
end

local function placeOnFloor(enemyId: string, config: EnemyConfigs.EnemyConfig, anchor: Player, living: { Player }): any?
	local players = playerPositions(living)
	if #players == 0 then return nil end

	local points = DangerMapService:GetPoints()
	if #points == 0 then return nil end

	local minimum = minimumSpawnDistance(config)
	local bias = config.DangerBias or 1
	local enemies = enemyPositions()
	local filter = buildSightFilter()

	local best, bestScore = nil, -math.huge
	for _ = 1, Config.PlacementAttempts do
		local candidate = points[math.random(#points)]
		local toPlayer = nearestDistance(candidate.Position, players)
		if toPlayer < minimum or toPlayer > Config.MaxSpawnDistance then continue end

		local score =
			scorePoint(candidate.Position, candidate.Danger, bias, minimum, players, enemies)
		if score <= bestScore then continue end
		if isVisibleToAnybody(candidate.Position, filter) then continue end

		best, bestScore = candidate, score
	end

	if not best then return nil end

	local anchorRoot = getAliveRoot(anchor)
	local reference = if anchorRoot then anchorRoot.Position else players[1]
	return spawnAt(enemyId, best.Position, horizontal(best.Position - reference))
end

local function hallwayCandidates(from: Vector3): ({ any }, { [any]: any })
	local start = HallwayGraphService:FindNearestNode(from)
	if not start then return {}, {} end

	local distances = { [start] = 0 }
	local previous = {}
	local queue = { start }
	local index = 1

	local found = {}
	local seen = {}

	while index <= #queue do
		local node = queue[index]
		index += 1

		local travelled = distances[node]
		if travelled > Config.HallwayMaxWalk then continue end

		if travelled >= Config.HallwayMinWalk and not seen[node] then
			seen[node] = true
			table.insert(found, node)
		end

		for neighbor in node.Neighbors do
			local step = travelled + (neighbor.Position - node.Position).Magnitude
			if step < (distances[neighbor] or math.huge) then
				distances[neighbor] = step
				previous[neighbor] = node
				table.insert(queue, neighbor)
			end
		end
	end

	return found, previous
end

local function placeInHallway(enemyId: string, config: EnemyConfigs.EnemyConfig, anchor: Player, living: { Player }): any?
	local anchorRoot = getAliveRoot(anchor)
	if not anchorRoot then return nil end

	local candidates, previous = hallwayCandidates(anchorRoot.Position)
	if #candidates == 0 then return nil end

	local players = playerPositions(living)
	local enemies = enemyPositions()
	local filter = buildSightFilter()

	local minimum = minimumSpawnDistance(config)
	local bias = config.DangerBias or 1

	local best, bestScore = nil, -math.huge
	for _, node in candidates do
		if nearestDistance(node.Position, players) < minimum then continue end

		local danger = DangerMapService:GetDanger(node.Position)
		local score = scorePoint(node.Position, danger, bias, minimum, players, enemies)
		if score <= bestScore then continue end
		if isVisibleToAnybody(node.Position, filter) then continue end

		best, bestScore = node, score
	end

	if not best then return nil end

	local back = previous[best]
	local facing = if back
		then horizontal(back.Position - best.Position)
		else horizontal(anchorRoot.Position - best.Position)

	return spawnAt(enemyId, best.Position, facing)
end

local function register(
	enemy: any,
	enemyId: string,
	config: EnemyConfigs.EnemyConfig,
	selfManaged: boolean?,
	spec: ResidentSpec?
)
	if not enemy then return end

	if config.SpawnGrace then
		enemy.AcquireAfter = os.clock() + config.SpawnGrace
	end

	table.insert(Population, {
		Enemy = enemy,
		EnemyId = enemyId,
		Config = config,
		SelfManaged = selfManaged,
		ExpiresAt = if spec and spec.Lifetime then os.clock() + spec.Lifetime else nil,
	})
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

local function tickChaos(now: number, living: { Player })
	if now < NextChaosSpawn or now < ChaosPendingUntil then return end
	if #living == 0 then return end

	local config = EnemyConfigs.Chaos
	if countAlive("Chaos") >= (config.MaxAlive or 1) then return end

	NextChaosSpawn = now + Config.ChaosInterval
	ChaosPendingUntil = now + (config.SpawnDelay or 0) + CHAOS_PENDING_TIMEOUT

	local scheduled = ChaosService:Spawn(function(chaos: any)
		ChaosPendingUntil = 0
		register(chaos, "Chaos", config)
	end)

	if not scheduled then
		ChaosPendingUntil = 0
		NextChaosSpawn = now + Config.TickInterval
	end
end

local function stalkerInterval(living: { Player }): number
	return Config.StalkerRotationInterval / math.max(#living, 1)
end

local function nextStalkerTarget(): Player?
	for _ = 1, #StalkerQueue do
		StalkerIndex = StalkerIndex % #StalkerQueue + 1
		local player = StalkerQueue[StalkerIndex]
		if getAliveRoot(player) then return player end
	end
	return nil
end

local function tickStalker(now: number, living: { Player })
	if countAlive("Stalker") > 0 then
		StalkerWasAlive = true
		return
	end
	if StalkerWasAlive then
		StalkerWasAlive = false
		StalkerTarget = nil
		StalkerRetries = 0
		NextStalkerAt = now + stalkerInterval(living)
		return
	end
	if now < NextStalkerAt then return end

	local target = StalkerTarget
	if not (target and getAliveRoot(target)) then
		target = nextStalkerTarget()
		StalkerRetries = 0
	end
	if not target then
		NextStalkerAt = now + Config.TickInterval
		return
	end
	StalkerTarget = target

	local enemy = StalkerService:SpawnPeeking(target, "Stalker")
	if enemy then
		register(enemy, "Stalker", EnemyConfigs.Stalker, nil, {
			Count = 1,
			Lifetime = Config.StalkerLifetime,
		})
		StalkerWasAlive = true
	else
		StalkerRetries += 1
		if StalkerRetries >= Config.StalkerSpawnAttempts then
			StalkerTarget = nil
			StalkerRetries = 0
			NextStalkerAt = now + stalkerInterval(living)
		else
			NextStalkerAt = now + Config.StalkerRetryDelay
		end
	end
end

local function spawnResident(enemyId: string, spec: ResidentSpec, anchor: Player, living: { Player }): any?
	local config = EnemyConfigs[enemyId]

	if enemyId == "Sisters" then
		return SistersService:Spawn()
	end

	if spec.Placement == "Peek" or config.SpawnPeeking then
		return StalkerService:SpawnPeeking(anchor, enemyId)
	end

	if spec.Placement == "Hallway" then
		return placeInHallway(enemyId, config, anchor, living)
	end

	return placeOnFloor(enemyId, config, anchor, living)
end

local function topUpResidents(now: number, living: { Player })
	if #living == 0 then return end

	for enemyId, spec in Residents do
		local config = EnemyConfigs[enemyId]
		if not config or type(spec) ~= "table" or type(spec.Count) ~= "number" then continue end
		if countAlive(enemyId) >= spec.Count then continue end
		if now < (NextResidentSpawn[enemyId] or 0) then continue end

		local anchor = living[math.random(#living)]
		local enemy = spawnResident(enemyId, spec, anchor, living)
		if enemy then
			register(enemy, enemyId, config, nil, spec)
			NextResidentSpawn[enemyId] = nil
		else
			NextResidentSpawn[enemyId] = now + Config.TickInterval
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
	local filter = buildSightFilter()

	for _, entry in Population do
		if entry.SelfManaged or not entry.ExpiresAt then continue end
		if now < entry.ExpiresAt or not isEnemyAlive(entry) then continue end

		local enemy = entry.Enemy
		if isEngaged(enemy) then continue end

		local position = (enemy.Model :: Model):GetPivot().Position
		if isVisibleToAnybody(position, filter) then continue end

		enemy:Despawn()
	end
end

function EnemyDirectorService:CanAfford(enemyId: string): boolean
	local config = EnemyConfigs[enemyId]
	if not config then return true end

	prunePopulation()
	return countAlive(enemyId) < (config.MaxAlive or math.huge)
end

function EnemyDirectorService:Adopt(enemy: any, enemyId: string, selfManaged: boolean?)
	register(enemy, enemyId, EnemyConfigs[enemyId], selfManaged)
end

function EnemyDirectorService:GetStalkerTarget(): Player?
	return StalkerTarget
end

function EnemyDirectorService:GetPopulation(): { Residents: { [string]: string }, Enemies: { string } }
	prunePopulation()

	local names = {}
	for _, entry in Population do
		table.insert(names, entry.EnemyId)
	end
	table.sort(names)

	local counts = {}
	for enemyId, spec in Residents do
		counts[enemyId] = `{countAlive(enemyId)}/{spec.Count}`
	end

	return { Residents = counts, Enemies = names }
end

function EnemyDirectorService:Reset()
	for _, entry in Population do
		if isEnemyAlive(entry) and not entry.SelfManaged then
			entry.Enemy:Despawn()
		end
	end
	table.clear(Population)
	table.clear(NextResidentSpawn)
	NextGhostSpawn = 0
	NextChaosSpawn = 0
	StalkerTarget = nil
	StalkerRetries = 0
	StalkerWasAlive = false
	NextStalkerAt = 0
	ChaosPendingUntil = 0
end

RunService.Heartbeat:Connect(function(deltaTime: number)
	TickAccumulator += deltaTime
	DespawnAccumulator += deltaTime

	local now = os.clock()

	if TickAccumulator >= Config.TickInterval then
		TickAccumulator = 0
		local living = getLivingPlayers()
		prunePopulation()
		topUpResidents(now, living)
		tickChaos(now, living)
		tickStalker(now, living)
		if #living > 0 then spawnGhost(now) end
	end

	if DespawnAccumulator >= Config.DespawnCheckInterval then
		DespawnAccumulator = 0
		sweepDespawns(now)
	end
end)

for _, player in Players:GetPlayers() do
	table.insert(StalkerQueue, player)
end

Players.PlayerAdded:Connect(function(player: Player)
	table.insert(StalkerQueue, player)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	local index = table.find(StalkerQueue, player)
	if index then
		table.remove(StalkerQueue, index)
		if index <= StalkerIndex then
			StalkerIndex -= 1
		end
	end
	if StalkerTarget == player then
		StalkerTarget = nil
		StalkerRetries = 0
	end
end)

return EnemyDirectorService
