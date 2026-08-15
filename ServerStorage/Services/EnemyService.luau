local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)

local EnemyService = {}
local ActiveEnemies = {}

-- A Stalker is an ambush. Check the exact spawn transform again after placement has been chosen so a
-- player turning during that small gap cannot watch it appear. The director performs the same check
-- while it samples points; this final guard also covers command and service-created spawns.
local STALKER_SIGHT_HEIGHTS = { 1.5, 4.5, 7 }

local function isStalkerSpawnVisible(position: Vector3): boolean
	local filter = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(filter, player.Character)
		end
	end
	for _, model in CollectionService:GetTagged("Enemy") do
		table.insert(filter, model)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	params.RespectCanCollide = true

	for _, eye in EnemyObservationService:GetEyes() do
		for _, height in STALKER_SIGHT_HEIGHTS do
			local direction = position + Vector3.yAxis * height - eye
			if direction.Magnitude < 1e-3 or workspace:Raycast(eye, direction, params) == nil then
				return true
			end
		end
	end
	return false
end

--- Every enemy rig in the world sits in this group, and the group does not collide with itself.
--- Enemies do not collide with players or with one another, but remain solid to the hotel geometry.
--- Nothing about damage runs through physics: contact is an `OverlapParams` query against the
--- player's own parts, so passing through an enemy does not remove the attack check.
EnemyService.CollisionGroup = "Enemies"
local PLAYER_COLLISION_GROUP = "Players"

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

	PhysicsService:CollisionGroupSetCollidable(self.CollisionGroup, self.CollisionGroup, false)
	PhysicsService:CollisionGroupSetCollidable(self.CollisionGroup, PLAYER_COLLISION_GROUP, false)
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
	if enemyId == "Stalker" and isStalkerSpawnVisible(spawnCFrame.Position) then
		return nil
	end

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
