--- Temporary hand controls for the enemy system, in place of the old startup drop that put one of
--- every enemy on the tagged spawn whether or not anybody wanted them there.
---
--- Chat commands, all of which answer in the server output rather than in chat:
---   /spawn <enemy>  -- one of that enemy, twenty studs in front of you, facing you
---   /spawn all      -- one of each
---   /despawn        -- clear every live enemy
---   /enemies        -- what is alive, and what can be spawned
---
--- Delete this file and the `EnemyCommands` flag once the enemy work is finished.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local EnemyService = require(ServerStorage.Services.EnemyService)

local SPAWN_DISTANCE = 20 -- studs in front of the caller: far enough to watch it approach

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
-- watch. Nil while they have no character to stand in front of.
local function spawnCFrame(player: Player): CFrame?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end

	local origin = root.Position
	local spot = origin + root.CFrame.LookVector * SPAWN_DISTANCE
	return CFrame.lookAt(Vector3.new(spot.X, origin.Y, spot.Z), origin)
end

local Commands = {}

function Commands.spawn(player: Player, argument: string?)
	local where = spawnCFrame(player)
	if not where then
		warn(`[enemies] {player.Name} has no character to spawn in front of`)
		return
	end

	if argument == "all" then
		for _, enemyId in enemyIds() do
			EnemyService:Spawn(enemyId, where)
		end
		warn(`[enemies] spawned one of each in front of {player.Name}`)
		return
	end

	local enemyId = argument and findEnemyId(argument)
	if not enemyId then
		warn(`[enemies] no enemy called "{argument or ""}" -- try: {table.concat(enemyIds(), ", ")}, all`)
		return
	end

	EnemyService:Spawn(enemyId, where)
	warn(`[enemies] spawned {enemyId} in front of {player.Name}`)
end

function Commands.despawn()
	local count = #EnemyService:GetActive()
	EnemyService:DespawnAll()
	warn(`[enemies] despawned {count}`)
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
