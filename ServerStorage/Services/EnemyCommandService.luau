local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local ChaosService = require(ServerStorage.Services.ChaosService)
local CeilingVentService = require(ServerStorage.Services.CeilingVentService)
local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local EnemyService = require(ServerStorage.Services.EnemyService)
local SistersService = require(ServerStorage.Services.SistersService)
local WatcherService = require(ServerStorage.Services.WatcherService)

local DEFAULT_SPAWN_DISTANCE = 20

local EnemyCommandService = {}

if not (FLAGS.Enemies and FLAGS.EnemyCommands) then
	return EnemyCommandService
end

local function enemyIds(): { string }
	local ids = {}
	for enemyId in EnemyConfigs do
		table.insert(ids, enemyId)
	end
	table.sort(ids)
	return ids
end

local function findEnemyId(name: string): string?
	for _, enemyId in enemyIds() do
		if enemyId:lower() == name:lower() then
			return enemyId
		end
	end
	return nil
end

local function spawnCFrame(player: Player, distance: number): CFrame?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end

	local origin = root.Position
	local spot = origin + root.CFrame.LookVector * distance
	return CFrame.lookAt(Vector3.new(spot.X, origin.Y, spot.Z), origin)
end

local function spawnOne(player: Player, enemyId: string): boolean
	if enemyId == "Chaos" then
		if ChaosService:SpawnInHallway(player) then return true end
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
		if WatcherService:SpawnNear(player) then return true end
		warn(`[enemies] no valid Watcher location found near {player.Name}; nothing spawned`)
		return false
	end

	if enemyId == "CeilingDweller" then
		if CeilingVentService:SpawnFromNearest(player) then return true end
		warn(`[enemies] no usable ceiling vent found for {player.Name}`)
		return false
	end

	local config = EnemyConfigs[enemyId]
	local distance = config.CommandSpawnDistance or DEFAULT_SPAWN_DISTANCE
	local where = spawnCFrame(player, if config.CommandSpawnBehind then -distance else distance)
	if not where then
		warn(`[enemies] {player.Name} has no character to spawn in front of`)
		return false
	end

	EnemyService:Spawn(enemyId, where)
	return true
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
		warn(`[enemies] no enemy called "{argument or ""}" -- try one of: {table.concat(enemyIds(), ", ")}`)
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

local VentCycle: { [Player]: number } = {}

function Commands.vent(player: Player)
	local character = player.Character
	if not character then
		warn(`[enemies] {player.Name} has no character to teleport`)
		return
	end

	local vents = CeilingVentService:GetVents()
	if #vents == 0 then
		warn("[enemies] no usable ceiling vents registered")
		return
	end

	local index = (VentCycle[player] or 0) % #vents + 1
	VentCycle[player] = index
	local vent = vents[index]
	character:PivotTo(CFrame.new(vent.Floor + Vector3.yAxis * 4))
	local status = if vent.Triggered then "already sprung" else "armed"
	warn(`[enemies] {player.Name} -> vent {index}/{#vents} ({status}): {vent.Vent:GetFullName()}`)
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
Players.PlayerRemoving:Connect(function(player: Player)
	VentCycle[player] = nil
end)
for _, player in Players:GetPlayers() do
	watch(player)
end

return EnemyCommandService
