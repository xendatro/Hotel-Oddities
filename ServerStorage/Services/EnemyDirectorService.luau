--- Decides what the hotel has in it, and where.
---
--- The model is a **standing population** rather than pressure applied to a player. The danger map
--- describes where enemies live; the director keeps the world stocked according to it and players
--- walk into that, rather than having danger spawned around them. In a public server that is the only
--- honest option -- strangers are not a party, so nobody's position or progress may decide what
--- anybody else meets -- and it is the better fiction anyway: some wings of this building have more
--- residents than others.
---
--- Three things run at once and they are deliberately independent:
---
---  * **A spawn timer per player**, paced by the danger where that player is standing. Their own
---    downtime, nobody else's. A player in a quiet corridor gets long gaps while somebody across the
---    hotel is in the worst of it and gets short ones.
---  * **A global budget**, linear in player count. The only thing every player shares, and it exists
---    to stop a full server melting rather than to balance anybody against anybody.
---  * **A despawn sweep**, which culls anything that has been far from everybody and unobserved for
---    long enough. This is what keeps the population where the players are without the director ever
---    having to think about it.
---
--- Two budgets that never compete. **Pursuit** is everything that comes after you. **Presence** is
--- everything that does not -- Creep, Watcher and Eye. Eye is lethal and still lives in Presence,
--- because the line that matters when rationing is whether a thing hunts you: a Chaser and an Eye at
--- once is one problem plus a hazard you can decline, where two Chasers is genuinely twice as hard.
--- Splitting them is what lets downtime mean "nothing is hunting" instead of "the hotel is empty".
---
--- Enemies spawned by the chat commands are not counted, not culled, and not the director's business.

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
local SistersService = require(ServerStorage.Services.SistersService)
local WatcherService = require(ServerStorage.Services.WatcherService)

local ENEMY_TAG = "Enemy"
local SPAWN_ROOT_HEIGHT = 3 -- studs above the floor a rig's root sits, matching the command spawns
local SIGHT_EYE_HEIGHT = 4 -- studs up a candidate the sight test aims for: roughly a standing head
local RESERVATION_TIMEOUT = 20 -- seconds a deferred spawn may hold budget before it is written off

type Managed = {
	Enemy: any,
	EnemyId: string,
	Config: EnemyConfigs.EnemyConfig,
	FarSince: number?, -- when it was first found out of everybody's reach, or nil while it is not
	SelfManaged: boolean?, -- counted against the budget, but somebody else owns when it leaves
}

type Reservation = {
	EnemyId: string,
	Config: EnemyConfigs.EnemyConfig,
	ExpiresAt: number,
	Filled: boolean,
}

local EnemyDirectorService = {}

--- Whether the budget could carry one more `enemyId` right now. Anything that spawns an enemy on its
--- own initiative -- the ceiling vents -- asks this first, or the budget means nothing.
function EnemyDirectorService:CanAfford(_enemyId: string): boolean
	return true
end

--- Takes an enemy something else created onto the director's books, so it counts against the budget.
--- `selfManaged` marks one whose lifetime belongs to its creator: it is counted, but never culled by
--- the distance sweep.
function EnemyDirectorService:Adopt(_enemy: any, _enemyId: string, _selfManaged: boolean?) end

--- Clears everything the director owns, leaving hand-spawned and self-managed enemies alone.
function EnemyDirectorService:Reset() end

-- With the director off, the stubs above stand: nothing is counted, nothing is capped, and the
-- systems that spawn on their own initiative carry on exactly as they did before it existed.
if not (FLAGS.Enemies and FLAGS.Director) then
	return EnemyDirectorService
end

local Config = DangerConfig.Director

local Population: { Managed } = {}
-- Chaos announces itself several seconds before it exists, so the budget it will spend has to be held
-- from the moment the decision is made. Without this the director would happily commit to three of
-- them inside one spawn delay and only notice when they all turned up.
local Reservations: { Reservation } = {}
local NextPursuitSpawn: { [Player]: number } = {}
local NextPresenceSpawn: { [Player]: number } = {}

local TickAccumulator = 0
local DespawnAccumulator = 0

--- Every enemy the director is allowed to roll, grouped by budget. Built once: an enemy without a
--- `SpawnWeight` has opted out, which is how the Ghost (its own placement) and the CeilingDweller (an
--- authored vent) stay out of this without needing to be named here.
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
	table.sort(ids) -- so a roll is reproducible for a given seed of `math.random`
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

--- Drops anything that has left the world of its own accord -- despawned itself, reached the end of
--- a route, expired on its own lifetime -- so the budget it was holding comes back.
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

--- One enemy id from `budget`'s roster, drawn by `SpawnWeight` from those that would actually fit:
--- inside the remaining budget and under their own cap. Nil when nothing fits, which is the ordinary
--- state of a full hotel rather than a problem.
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

--- Studs from every player this enemy may appear at. Derived rather than flat, because a flat number
--- means nothing to a roster whose detection ranges run from 60 to 250: put a Chaser down at exactly
--- its own detection range and it is hunting before it has finished appearing. Something should have
--- to find you, not start found.
--- The cap matters as much as the derivation. WeepingAngel detects at 250 studs through a 360 degree
--- cone -- it is *built* to always know where you are -- so taking its range at face value would ask
--- for a spawn between 312 and 320 studs out, a band so narrow that nothing would ever qualify and it
--- would simply never appear. There is no distance at which that enemy spawns unaware, so it gets the
--- sight rule, a generous distance, and its own rarity to carry the rest.
--- `DespawnRange` is in here for the Creep, which vanishes the moment anybody gets within 96 studs of
--- it. Placed at the flat 70-stud floor it would delete itself on the frame after it appeared.
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

--- Everything a sight test must not treat as a wall.
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

--- Whether anybody could see something standing at `position`.
---
--- Raw line of sight, with no regard for which way anybody is facing -- which is stricter than a
--- view-cone test and is the point. "Not in shot" is not good enough; what makes a spawn fair is that
--- it is not in the same *hallway*, so that first contact happens when somebody rounds a corner and
--- finds it already there rather than watching it wink into being.
---
--- The eyes come from `EnemyObservationService`, which reports real camera positions and falls back
--- to the top of the character for a client that reports nothing plausible. In first person the
--- camera sits inside the head, so a spot hidden from a head position is not necessarily hidden from
--- the eye that matters.
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

--- Puts one point-placed enemy somewhere suitable near `anchor`. Nil when every draw was rejected.
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

	-- Turned away from the player who anchored the draw. Line of sight already guarantees it appears
	-- unseen, but an enemy facing back down the corridor somebody is about to walk out of catches them
	-- with its own view cone the instant they round the corner -- and the whole of the runway a Chaser
	-- offers assumes you were not spotted at the exact moment of first contact. Pointed away, the
	-- player often gets to see it first, which is the difference between a fright and a death.
	local origin = point.Position + Vector3.yAxis * SPAWN_ROOT_HEIGHT
	local away = horizontal(point.Position - anchorRoot.Position)
	local facing = if away.Magnitude > 1e-3 then away.Unit else anchorRoot.CFrame.LookVector

	return EnemyService:Spawn(enemyId, CFrame.lookAt(origin, origin + facing))
end

local function register(enemy: any, enemyId: string, config: EnemyConfigs.EnemyConfig, selfManaged: boolean?)
	if not enemy then return end

	-- Blind to whoever is nearby for its first few seconds. Distance and sight rules keep a spawn out
	-- of trouble geometrically, but geometry conspires -- a corridor bends back, somebody moves while
	-- the draw is happening -- and this makes "it never starts a chase the instant it appears" true
	-- rather than merely likely.
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

--- Commits to one spawn of `enemyId` for `anchor`. Returns whether anything came of it.
local function spawnFor(enemyId: string, anchor: Player): boolean
	local config = EnemyConfigs[enemyId]

	if enemyId == "Chaos" then
		-- It exists only after its warning has run, so the budget is held from now and handed over
		-- when the model actually appears. A Chaos that gets cancelled lets its reservation lapse.
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
			reservation.Filled = true -- nothing is coming; give the budget straight back
		end
		return scheduled
	end

	if enemyId == "Sisters" then
		local sisters = SistersService:Spawn()
		register(sisters, enemyId, config)
		return sisters ~= nil
	end

	if enemyId == "Watcher" then
		-- Ambient placement, so no `anyDirection`: a corner behind somebody is wasted on a thing that
		-- wants to be glimpsed, and one at arm's length is worse.
		local watcher = WatcherService:SpawnNear(anchor)
		register(watcher, enemyId, config)
		return watcher ~= nil
	end

	local enemy = placeOnFloor(enemyId, config, anchor)
	register(enemy, enemyId, config)
	return enemy ~= nil
end

local function intervalFor(danger: number, quiet: number, busy: number, floor: number): number
	return math.max(floor, quiet + (busy - quiet) * math.clamp(danger, 0, 1))
end

--- One player's turn. Their timer, paced by the danger where they are standing, against the shared
--- budget. A tick that rolls nothing, or draws nowhere out of sight to put it, spends the interval
--- anyway -- the quiet stretches that produces are the system working, not failing.
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

--- Culls anything that has been out of everybody's reach and out of everybody's sight for long
--- enough. The distance is far larger than anything spawns at, deliberately: if the two were close a
--- lone player would generate a treadmill, with the hotel materialising ahead of them and dissolving
--- behind them, which reads as being followed rather than as a building with things in it. The gap
--- between the two numbers is the band where an enemy simply persists and is nobody's problem.
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

		-- Never while it is still hunting somebody, and never in view: something vanishing at the end
		-- of a corridor somebody is looking down is worse than it being there at all.
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

--- How much of each budget is in the world right now. The debug UI reads this; nothing else needs it.
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

--- Clears everything the director owns. Hand-spawned enemies and self-managed ones (a Dweller still
--- hanging out of its vent) are left where they are. The debug UI calls this after a slider changes
--- where things ought to be, since judging a new field through the old field's population is no test.
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
