local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local AnalyticsConfig = require(ServerStorage.Configs.AnalyticsConfig)
local DiscoveryConfig = require(ServerStorage.Configs.DiscoveryConfig)
local AnalyticsService = require(ServerStorage.Services.AnalyticsService)
local EnemyDiscoveryService = require(ServerStorage.Services.EnemyDiscoveryService)
local EnemyService = require(ServerStorage.Services.EnemyService)

local CONFIG = AnalyticsConfig.Encounter
local OUTCOMES = CONFIG.Outcomes

local EnemyEncounterService = {}

type Encounter = {
	EnemyId: string,
	StartedAt: number,
	LastContact: number,
}

local Encounters: { [Player]: { [any]: Encounter } } = {}

local accumulator = 0

local function modelsOf(enemy: any): { Model }
	local models = {}
	for _, model in (enemy.Models or { enemy.Model }) do
		if typeof(model) == "Instance" and model:IsA("Model") and model:IsDescendantOf(workspace) then
			table.insert(models, model)
		end
	end
	return models
end

local function report(player: Player, enemyId: string, startedAt: number, outcome: string)
	AnalyticsService:LogEvent(player, "EnemyEncounter", os.clock() - startedAt, {
		Enemy = enemyId,
		Outcome = outcome,
	})
end

local function finish(player: Player, enemy: any, outcome: string?)
	local encounters = Encounters[player]
	local encounter = encounters and encounters[enemy]
	if not encounter then return end

	encounters[enemy] = nil
	if outcome then
		report(player, encounter.EnemyId, encounter.StartedAt, outcome)
	end
end

local function inContact(player: Player, root: BasePart, enemyId: string, models: { Model }): boolean
	local sight = DiscoveryConfig.Resolve(enemyId).Sight
	for _, model in models do
		local distance = (model:GetPivot().Position - root.Position).Magnitude
		if distance <= CONFIG.Range then return true end
		if sight and EnemyDiscoveryService:HasView(player, model, sight) then return true end
	end
	return false
end

local function sweepPlayer(player: Player, enemies: { any }, now: number)
	local encounters = Encounters[player]
	if not encounters then return end

	local root = CharacterService.GetAliveRootFromCharacter(player.Character)
	if not root then return end

	local live: { [any]: boolean } = {}
	for _, enemy in enemies do
		local enemyId = enemy.EnemyId
		if type(enemyId) ~= "string" then continue end
		live[enemy] = true

		local models = modelsOf(enemy)
		if #models == 0 then continue end
		if not inContact(player, root, enemyId, models) then continue end

		local encounter = encounters[enemy]
		if encounter then
			encounter.LastContact = now
		else
			encounters[enemy] = { EnemyId = enemyId, StartedAt = now, LastContact = now }
		end
	end

	for enemy, encounter in encounters do
		if not live[enemy] or now - encounter.LastContact >= CONFIG.Grace then
			finish(player, enemy, OUTCOMES.Escaped)
		end
	end
end

local function sweep()
	local enemies = EnemyService:GetActive()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		sweepPlayer(player, enemies, now)
	end
end

function EnemyEncounterService:IsEncountering(player: Player, enemyId: string?): boolean
	local encounters = Encounters[player]
	if not encounters then return false end
	for _, encounter in encounters do
		if enemyId == nil or encounter.EnemyId == enemyId then return true end
	end
	return false
end

function EnemyEncounterService:ResolveDeath(player: Player, killer: Model?, causeId: string?)
	local encounters = Encounters[player]
	if not encounters then return end

	local matched: any = nil
	if killer then
		for enemy in encounters do
			if table.find(modelsOf(enemy), killer) then
				matched = enemy
				break
			end
		end
	end
	if not matched and causeId then
		for enemy, encounter in encounters do
			if encounter.EnemyId == causeId then
				matched = enemy
				break
			end
		end
	end

	if matched then
		finish(player, matched, OUTCOMES.Died)
	elseif causeId then
		report(player, causeId, os.clock(), OUTCOMES.Died)
	end

	for enemy in encounters do
		finish(player, enemy, nil)
	end
end

local function watchPlayer(player: Player)
	Encounters[player] = {}
	player.CharacterAdded:Connect(function()
		Encounters[player] = {}
	end)
end

if FLAGS.Enemies and CONFIG.Enabled then
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		Encounters[player] = nil
	end)

	RunService.Heartbeat:Connect(function(delta: number)
		accumulator += delta
		if accumulator < CONFIG.SweepInterval then return end
		accumulator = 0
		sweep()
	end)
end

return EnemyEncounterService
