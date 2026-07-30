local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)

local EnemyService = {}
local ActiveEnemies = {}

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

local function setServerOwnership(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:CanSetNetworkOwnership() then
			descendant:SetNetworkOwner(nil)
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
	setServerOwnership(model)

	local enemy = enemyClass.new(model, config, ...)
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
