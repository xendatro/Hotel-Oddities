local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local SpawnZoneService = require(ReplicatedStorage.Services.SpawnZoneService)
local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local EnemyService = require(ServerStorage.Services.EnemyService)
local Peek = require(ServerStorage.Classes.Enemies.Behaviors.Peek)
local PeekSpotService = require(ServerStorage.Services.PeekSpotService)

local HAND_SPAWN_MIN_DISTANCE = 60

local StalkerService = {}

local DEFAULT_ENEMY_ID = "Stalker"

function StalkerService:FindSpot(player: Player, enemyId: string?): PeekSpotService.PeekSpot?
	local config = EnemyConfigs[enemyId or DEFAULT_ENEMY_ID]
	return PeekSpotService:Find(player, Peek.GetFindOptions(config))
end

function StalkerService:SpawnPeeking(player: Player, enemyId: string?, anyDirection: boolean?)
	local id = enemyId or DEFAULT_ENEMY_ID
	local config = EnemyConfigs[id]
	local spot = self:FindSpot(player, id)

	if not spot and anyDirection then
		local options = Peek.GetFindOptions(config)
		options.RearArc = 360
		spot = PeekSpotService:Find(player, options)

		if not spot then
			options.MinDistance = math.min(HAND_SPAWN_MIN_DISTANCE, options.MinDistance)
			spot = PeekSpotService:Find(player, options)
		end
	end

	if not spot then return nil end
	if SpawnZoneService:Contains(spot.Stand) then return nil end

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or (spot.Stand - root.Position).Magnitude < config.MinPeekDistance then
		return nil
	end

	local facing = if root
		then Vector3.new(root.Position.X, spot.Stand.Y, root.Position.Z)
		else spot.Stand + spot.Facing
	if (facing - spot.Stand).Magnitude < 1e-3 then
		facing = spot.Stand + spot.Facing
	end
	return EnemyService:Spawn(id, CFrame.lookAt(spot.Stand, facing), spot, player)
end

return StalkerService
