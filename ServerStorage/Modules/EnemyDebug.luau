local ServerStorage = game:GetService("ServerStorage")

local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local EnemyService = require(ServerStorage.Services.EnemyService)
local StalkerService = require(ServerStorage.Services.StalkerService)
local Peek = require(ServerStorage.Classes.Enemies.Behaviors.Peek)
local PeekSpotService = require(ServerStorage.Services.PeekSpotService)

local EnemyDebug = {}

function EnemyDebug.SpawnPeekingStalker(player: Player, enemyId: string?): any?
	return StalkerService:SpawnPeeking(player, enemyId)
end

function EnemyDebug.FindPeekSpot(player: Player, enemyId: string?): any?
	return StalkerService:FindSpot(player, enemyId)
end

function EnemyDebug.DebugPeekCorner(player: Player, position: Vector3): any?
	return PeekSpotService:DebugCorner(player, Peek.GetFindOptions(EnemyConfigs.Stalker), position)
end

function EnemyDebug.SpawnAt(player: Player, enemyId: string): any?
	local config = EnemyConfigs[enemyId]
	if not config then return nil end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end

	local distance = config.CommandSpawnDistance or 20
	local direction = if config.CommandSpawnBehind then -root.CFrame.LookVector else root.CFrame.LookVector
	local position = root.Position + direction * distance
	local where = CFrame.lookAt(Vector3.new(position.X, root.Position.Y, position.Z), root.Position)
	return EnemyService:Spawn(enemyId, where)
end

return EnemyDebug
