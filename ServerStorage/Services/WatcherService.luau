local ServerStorage = game:GetService("ServerStorage")

local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local EnemyService = require(ServerStorage.Services.EnemyService)
local PeekSpotService = require(ServerStorage.Services.PeekSpotService)
local Watcher = require(ServerStorage.Classes.Enemies.Watcher)

local HAND_SPAWN_MIN_DISTANCE = 60

local WatcherService = {}

function WatcherService:FindSpot(player: Player): PeekSpotService.PeekSpot?
	return PeekSpotService:Find(player, Watcher.GetFindOptions(EnemyConfigs.Watcher))
end

function WatcherService:SpawnNear(player: Player, anyDirection: boolean?)
	local spot = self:FindSpot(player)

	if not spot and anyDirection then
		local options = Watcher.GetFindOptions(EnemyConfigs.Watcher)
		options.RearArc = 360
		spot = PeekSpotService:Find(player, options)

		if not spot then
			options.MinDistance = math.min(HAND_SPAWN_MIN_DISTANCE, options.MinDistance)
			spot = PeekSpotService:Find(player, options)
		end
	end

	if not spot then return nil end

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or (spot.Stand - root.Position).Magnitude < EnemyConfigs.Watcher.MinPeekDistance then
		return nil
	end

	local facing = if root
		then Vector3.new(root.Position.X, spot.Stand.Y, root.Position.Z)
		else spot.Stand + spot.Facing
	if (facing - spot.Stand).Magnitude < 1e-3 then
		facing = spot.Stand + spot.Facing
	end
	return EnemyService:Spawn("Watcher", CFrame.lookAt(spot.Stand, facing), spot, player)
end

return WatcherService
