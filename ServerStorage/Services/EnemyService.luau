local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local PerfLog = require(ReplicatedStorage.Services.PerfLoggerService)
local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local EnemySizeService = require(ServerStorage.Services.EnemySizeService)

local EnemyClasses = ServerStorage.Classes.Enemies
local EnemyModels = ReplicatedStorage:WaitForChild("Enemies")

local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local despawnEffect = CommunicationService.Ensure("Enemies", "DespawnPoof")

local EnemyService = {}
local ActiveEnemies = {}
local spawnBlocks = 0

EnemyService.CollisionGroup = "Enemies"
local PLAYER_COLLISION_GROUP = "Players"
local FURNITURE_TAG = "Furniture"
local FURNITURE_COLLISION_GROUP = "Furniture"

function EnemyService:EnsureCollisionGroup()
	if not PhysicsService:IsCollisionGroupRegistered(self.CollisionGroup) then
		PhysicsService:RegisterCollisionGroup(self.CollisionGroup)
	end
	if not PhysicsService:IsCollisionGroupRegistered(PLAYER_COLLISION_GROUP) then
		PhysicsService:RegisterCollisionGroup(PLAYER_COLLISION_GROUP)
	end
	if not PhysicsService:IsCollisionGroupRegistered(FURNITURE_COLLISION_GROUP) then
		PhysicsService:RegisterCollisionGroup(FURNITURE_COLLISION_GROUP)
	end
	PhysicsService:CollisionGroupSetCollidable(self.CollisionGroup, self.CollisionGroup, false)
	PhysicsService:CollisionGroupSetCollidable(self.CollisionGroup, PLAYER_COLLISION_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(self.CollisionGroup, FURNITURE_COLLISION_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(PLAYER_COLLISION_GROUP, PLAYER_COLLISION_GROUP, false)
end

local function preparePlayerCharacter(character: Model)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = PLAYER_COLLISION_GROUP
		end
	end
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = PLAYER_COLLISION_GROUP
		end
	end)
end

EnemyService:EnsureCollisionGroup()

local furnitureConnections: { [Instance]: RBXScriptConnection } = {}

local function prepareFurniture(model: Instance)
	if not model:IsA("Model") then return end

	local function prepareDescendant(descendant: Instance)
		if descendant:IsA("ProximityPrompt") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.CollisionGroup = FURNITURE_COLLISION_GROUP
		end
	end

	for _, descendant in model:GetDescendants() do
		prepareDescendant(descendant)
	end

	furnitureConnections[model] = model.DescendantAdded:Connect(prepareDescendant)
end

local function removeFurniture(model: Instance)
	local connection = furnitureConnections[model]
	if connection then
		connection:Disconnect()
		furnitureConnections[model] = nil
	end
end

for _, furniture in CollectionService:GetTagged(FURNITURE_TAG) do
	prepareFurniture(furniture)
end
CollectionService:GetInstanceAddedSignal(FURNITURE_TAG):Connect(prepareFurniture)
CollectionService:GetInstanceRemovedSignal(FURNITURE_TAG):Connect(removeFurniture)

CharacterService.ForEachPlayer(function(player)
	player.CharacterAdded:Connect(preparePlayerCharacter)
	if player.Character then
		preparePlayerCharacter(player.Character)
	end
end)

local activeFolder: Folder?

local function getActiveFolder(): Folder
	if activeFolder then return activeFolder end

	activeFolder = workspace:FindFirstChild("Enemies") :: Folder?
	if not activeFolder then
		activeFolder = Instance.new("Folder")
		activeFolder.Name = "Enemies"
		activeFolder.Parent = workspace
	end
	return activeFolder
end

local function prepare(model: Model)
	local function prepareDescendant(descendant: Instance)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = EnemyService.CollisionGroup
		end
	end

	for _, descendant in model:GetDescendants() do
		prepareDescendant(descendant)
		if descendant:IsA("BasePart") and descendant:CanSetNetworkOwnership() then
			pcall(descendant.SetNetworkOwner, descendant, nil)
		end
	end
	model.DescendantAdded:Connect(prepareDescendant)
end

local function spawnEnemy(self,allowed,enemyId: string, spawnCFrame: CFrame, ...: any)
	if not FLAGS.Enemies or not allowed() then return nil end

	local config = EnemyConfigs[enemyId]
	local enemyClass = require(EnemyClasses:FindFirstChild(enemyId))
	if not allowed() then return nil end
	local model = EnemyModels:FindFirstChild(config.Model):Clone() :: Model

	model:PivotTo(spawnCFrame)
	EnemySizeService.Apply(model)
	model:SetAttribute("EnemyId", enemyId)
	model:SetAttribute("Harmless", config.Harmless or nil)
	model.Parent = getActiveFolder()
	prepare(model)

	local enemy = enemyClass.new(model, config, ...)
	if not allowed() then enemy:Despawn(); model:Destroy(); return nil end
	enemy.EnemyId = enemyId
	local shouldEmitPoof = config.DespawnEffect ~= false
	local effectSent = false
	local function emitPoof()
		if not shouldEmitPoof then return end
		if effectSent then return end
		effectSent = true
		for _, body in enemy.Models or { model } do
			if not body:IsA("Model") or not body.Parent then continue end
			local ok, frame, size = pcall(body.GetBoundingBox, body)
			if ok then despawnEffect:FireAllClients(frame.Position, size, body) end
		end
	end
	local despawn = enemy.Despawn
	enemy.Despawn = function(self, ...)
		if self.Active and not self.SilentDespawn then emitPoof() end
		return despawn(self, ...)
	end
	table.insert(ActiveEnemies, enemy)
	model.Destroying:Connect(function()
		if not enemy.SilentDespawn then emitPoof() end
		local index = table.find(ActiveEnemies, enemy)
		if index then
			table.remove(ActiveEnemies, index)
		end
		PerfLog.Log("Enemy", `{enemyId} despawn`)
	end)

	enemy:Start()
	PerfLog.Log("Enemy", `{enemyId} spawn`)
	return enemy
end

function EnemyService:Spawn(enemyId: string, spawnCFrame: CFrame, ...: any)
	return spawnEnemy(self,function() return spawnBlocks==0 end,enemyId,spawnCFrame,...)
end

function EnemyService:AcquireSpawnBlock()
	spawnBlocks += 1
	local released = false
	return function()
		if not released then released = true; spawnBlocks -= 1 end
	end,function(enemyId,spawnCFrame,...)
		return spawnEnemy(self,function() return not released and spawnBlocks==1 end,enemyId,spawnCFrame,...)
	end
end

function EnemyService:GetActive()
	return table.clone(ActiveEnemies)
end

function EnemyService:ForEachActive(callback: (enemy: any) -> ())
	for _, enemy in ActiveEnemies do
		callback(enemy)
	end
end

function EnemyService:DespawnAll(silent: boolean?)
	for _, enemy in table.clone(ActiveEnemies) do
		if silent then enemy.SilentDespawn = true end
		enemy:Despawn()
	end
end

return EnemyService
