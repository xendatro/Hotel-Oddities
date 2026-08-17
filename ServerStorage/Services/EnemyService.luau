local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)

local EnemyService = {}
local ActiveEnemies = {}

--- Every enemy rig in the world sits in this group, and the group does not collide with itself.
--- Enemies do not collide with players or with one another, but remain solid to the hotel geometry.
--- The server uses an `OverlapParams` query for pursuit state; the client's touch listener owns the
--- actual contact death so health is not decided by server-side physics.
EnemyService.CollisionGroup = "Enemies"
local PLAYER_COLLISION_GROUP = "Players"
local FURNITURE_TAG = "Furniture"
local FURNITURE_COLLISION_GROUP = "Furniture"

--- Registers the group if it is not already there. Idempotent, and safe to call from anywhere that
--- puts a rig in the world without going through `Spawn` -- the second sister is cloned after her
--- pair has already spawned.
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

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(preparePlayerCharacter)
	if player.Character then
		preparePlayerCharacter(player.Character)
	end
end)
for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(preparePlayerCharacter)
	if player.Character then
		preparePlayerCharacter(player.Character)
	end
end

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

--- Puts a freshly parented rig into the state every enemy starts in: simulated by the server, and in
--- the enemy collision group so it cannot get wedged against another one.
local function prepare(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = EnemyService.CollisionGroup
			if descendant:CanSetNetworkOwnership() then
				descendant:SetNetworkOwner(nil)
			end
		end
	end
end

--- Puts one `enemyId` in the world at `spawnCFrame`. Anything after those is handed to that class's
--- constructor, for an enemy whose spawner knows something it cannot work out for itself -- a Watcher
--- is placed on a corner that had to be found before there was a model to place.
function EnemyService:Spawn(enemyId: string, spawnCFrame: CFrame, ...: any)
	if not FLAGS.Enemies then return nil end

	local config = EnemyConfigs[enemyId]
	local enemyClass = require(ServerStorage.Classes.Enemies:WaitForChild(enemyId))
	local model = ReplicatedStorage:WaitForChild("Enemies"):WaitForChild(config.Model):Clone() :: Model

	-- Every enemy carries the id it was spawned under, which is what a death is reported as. A class
	-- cannot work this out for itself: `CeilingDweller` is a `Chaser` with another model on it, and
	-- the pair of Sisters is one enemy with two rigs.
	model:PivotTo(spawnCFrame)
	model:SetAttribute("EnemyId", enemyId)
	-- Carried on the model because the thing that acts on it is the client's touch handler, which has
	-- no reach into server tuning. Set it before parenting so a client never sees the Enemy tag without
	-- the flag that tells its touch handler to ignore contact. Absent rather than false on killers.
	model:SetAttribute("Harmless", config.Harmless or nil)
	model.Parent = getActiveFolder()
	EnemyService:EnsureCollisionGroup()
	prepare(model)

	local enemy = enemyClass.new(model, config, ...)
	enemy.EnemyId = enemyId
	table.insert(ActiveEnemies, enemy)
	model.Destroying:Connect(function()
		local index = table.find(ActiveEnemies, enemy)
		if index then
			table.remove(ActiveEnemies, index)
		end
	end)

	enemy:Start()
	return enemy
end

function EnemyService:GetActive()
	return table.clone(ActiveEnemies)
end

function EnemyService:DespawnAll()
	for _, enemy in table.clone(ActiveEnemies) do
		enemy:Despawn()
	end
end

return EnemyService
