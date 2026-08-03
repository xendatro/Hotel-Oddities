local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)

local EnemyService = {}
local ActiveEnemies = {}

--- Every enemy rig in the world sits in this group, and the group does not collide with itself.
--- Enemies are solid to players and to the hotel exactly as before; they are transparent only to one
--- another. Two Humanoids that meet in a corridor otherwise shoulder each other out of line and both
--- stall against a wall, which no amount of re-pathing can answer -- the path is fine, the rig simply
--- cannot walk it. Nothing about damage runs through physics: contact is an `OverlapParams` query
--- against the player's own parts, so passing through a fellow enemy costs an enemy no lethality.
EnemyService.CollisionGroup = "Enemies"

--- Registers the group if it is not already there. Idempotent, and safe to call from anywhere that
--- puts a rig in the world without going through `Spawn` -- the second sister is cloned after her
--- pair has already spawned.
function EnemyService:EnsureCollisionGroup()
	if PhysicsService:IsCollisionGroupRegistered(self.CollisionGroup) then return end

	PhysicsService:RegisterCollisionGroup(self.CollisionGroup)
	PhysicsService:CollisionGroupSetCollidable(self.CollisionGroup, self.CollisionGroup, false)
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

	model:PivotTo(spawnCFrame)
	model.Parent = getActiveFolder()
	EnemyService:EnsureCollisionGroup()
	prepare(model)

	local enemy = enemyClass.new(model, config, ...)
	-- Every enemy carries the id it was spawned under, which is what a death is reported as. A class
	-- cannot work this out for itself: `CeilingDweller` is a `Chaser` with another model on it, and
	-- the pair of Sisters is one enemy with two rigs.
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
