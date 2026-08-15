--- Temporary hand controls for the enemy system, in place of the old startup drop that put one of
--- every enemy on the tagged spawn whether or not anybody wanted them there.
---
--- Chat commands, all of which answer in the server output rather than in chat:
---   /spawn <enemy>  -- one of that enemy, using any placement rules specific to it
---   /spawn all      -- one of each
---   /despawn        -- clear every live enemy
---   /enemies        -- what is alive, and what can be spawned
---
--- Delete this file and the `EnemyCommands` flag once the enemy work is finished.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local ChaosService = require(ServerStorage.Services.ChaosService)
local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local EnemyService = require(ServerStorage.Services.EnemyService)
local SistersService = require(ServerStorage.Services.SistersService)
local WatcherService = require(ServerStorage.Services.WatcherService)

local DEFAULT_SPAWN_DISTANCE = 20 -- studs in front of the caller: far enough to watch it approach

local EnemyCommandService = {}

if not (FLAGS.Enemies and FLAGS.EnemyCommands) then
	return EnemyCommandService
end

-- Every enemy id, spelled as `EnemyConfigs` spells it.
local function enemyIds(): { string }
	local ids = {}
	for enemyId in EnemyConfigs do
		table.insert(ids, enemyId)
	end
	table.sort(ids)
	return ids
end

-- The properly-cased id matching `name`, so the command does not care how it was typed.
local function findEnemyId(name: string): string?
	for _, enemyId in enemyIds() do
		if enemyId:lower() == name:lower() then
			return enemyId
		end
	end
	return nil
end

-- In front of the caller and turned to face them, which is where you want something you are about to
-- watch -- or behind them, for a negative distance, which is where you have to put something whose
-- whole behaviour is undone by being looked at. Nil while they have no character to stand near.
local function spawnCFrame(player: Player, distance: number): CFrame?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end

	local origin = root.Position
	local spot = origin + root.CFrame.LookVector * distance
	return CFrame.lookAt(Vector3.new(spot.X, origin.Y, spot.Z), origin)
end

-- Spawns one of `enemyId` for this caller, reporting whether it managed it. Chaos plans a remote
-- hallway route and warning first, and the Sisters a remote corridor to walk out of. A Watcher goes
-- through its own corner-placement service.
local function spawnOne(player: Player, enemyId: string): boolean
	if enemyId == "Chaos" then
		if ChaosService:Spawn() then return true end
		warn(`[enemies] no MazeFloor route starts at least {EnemyConfigs.Chaos.SpawnPlayerDistance} studs from every player`)
		return false
	end

	if enemyId == "Sisters" then
		if SistersService:SpawnInHallway(player) then return true end
		warn(`[enemies] {player.Name} must be standing in a usable MazeFloor hallway to spawn the Sisters`)
		return false
	end

	if enemyId == "Watcher" then
		-- Any direction, not just ahead: a hand-spawn is meant to be walked over to and looked at.
		if WatcherService:SpawnNear(player, true) then return true end
		warn(`[enemies] no corner near {player.Name} to put a Watcher behind -- try a corridor`)
		return false
	end

	local config = EnemyConfigs[enemyId]
	local distance = config.CommandSpawnDistance or DEFAULT_SPAWN_DISTANCE
	local where = spawnCFrame(player, if config.CommandSpawnBehind then -distance else distance)
	if not where then
		warn(`[enemies] {player.Name} has no character to spawn in front of`)
		return false
	end

	return EnemyService:Spawn(enemyId, where) ~= nil
end

local Commands = {}

function Commands.spawn(player: Player, argument: string?)
	if argument == "all" then
		local ids = enemyIds()
		local spawned = 0
		for _, enemyId in ids do
			if spawnOne(player, enemyId) then
				spawned += 1
			end
		end
		warn(`[enemies] spawned {spawned} of {#ids} around {player.Name}`)
		return
	end

	local enemyId = argument and findEnemyId(argument)
	if not enemyId then
		warn(`[enemies] no enemy called "{argument or ""}" -- try: {table.concat(enemyIds(), ", ")}, all`)
		return
	end

	if spawnOne(player, enemyId) then
		warn(`[enemies] spawned {enemyId} for {player.Name}`)
	end
end

function Commands.despawn()
	local count = #EnemyService:GetActive()
	local pendingChaos = ChaosService:CancelPending()
	EnemyService:DespawnAll()
	warn(`[enemies] despawned {count}; cancelled {pendingChaos} pending Chaos warnings`)
end

function Commands.enemies()
	local active = {}
	for _, enemy in EnemyService:GetActive() do
		table.insert(active, `{enemy.ClassName}({enemy.StateMachine.State})`)
	end
	warn(`[enemies] {#active} alive: {table.concat(active, ", ")}`)
	warn(`[enemies] spawnable: {table.concat(enemyIds(), ", ")}, all`)
end

local function onChatted(player: Player, message: string)
	local name, argument = message:match("^/(%a+)%s*(.*)$")
	local command = name and Commands[name:lower()]
	if command then
		command(player, if argument ~= "" then argument else nil)
	end
end

local function watch(player: Player)
	player.Chatted:Connect(function(message: string)
		onChatted(player, message)
	end)
end

Players.PlayerAdded:Connect(watch)
for _, player in Players:GetPlayers() do
	watch(player) -- already in before this service loaded
end

return EnemyCommandService
