local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local DiscoveryConfig = require(ServerStorage.Configs.DiscoveryConfig)
local DataSaveService = require(ServerStorage.Services.DataSaveService)
local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local EnemyService = require(ServerStorage.Services.EnemyService)

local Update = CommunicationService.Get("Index", "Update") :: RemoteEvent
local Reveal = CommunicationService.Get("Index", "Reveal") :: RemoteEvent

local EnemyDiscoveryService = {}

local Progress: { [Player]: { [string]: number } } = {}
local Dwell: { [Player]: { [string]: number } } = {}
local Replicated: { [Player]: { [string]: number } } = {}
local PendingReveal: { [Player]: { Id: string, Before: number, After: number } } = {}

local accumulator = 0

function EnemyDiscoveryService:Get(player: Player, enemyId: string): number
	local set = Progress[player]
	return (set and set[enemyId]) or 0
end

function EnemyDiscoveryService:GetAll(player: Player): { [string]: number }
	return table.clone(Progress[player] or {})
end

local function replicate(player: Player)
	local set = Progress[player]
	if not set then return end

	Replicated[player] = table.clone(set)
	Update:FireClient(player, set)
end

local function persist(player: Player)
	local profile = DataSaveService:Get(player)
	if not profile then return end
	profile.Data.DiscoveredEnemies = table.clone(Progress[player] or {})
end

function EnemyDiscoveryService:Grant(player: Player, enemyId: string?, amount: number): (number, number)
	if not enemyId or amount <= 0 then return 0, 0 end

	local set = Progress[player]
	if not set then return 0, 0 end

	local before = set[enemyId] or 0
	if before >= 1 then return before, before end

	local after = math.clamp(before + amount, 0, 1)
	set[enemyId] = after
	persist(player)
	return before, after
end

function EnemyDiscoveryService:Set(player: Player, enemyId: string, progress: number)
	local set = Progress[player]
	if not set then return end

	local value = math.clamp(progress, 0, 1)
	set[enemyId] = value > 0 and value or nil
	persist(player)
	replicate(player)
end

function EnemyDiscoveryService:Clear(player: Player)
	if not Progress[player] then return end

	Progress[player] = {}
	Dwell[player] = {}
	persist(player)
	replicate(player)
end

function EnemyDiscoveryService:GrantEvent(player: Player, enemyId: string?)
	if not enemyId then return end

	local rule = DiscoveryConfig.Resolve(enemyId)
	if not rule.Event then return end

	local before, after = EnemyDiscoveryService:Grant(player, enemyId, rule.Event)
	if after > before then
		replicate(player)
	end
end

function EnemyDiscoveryService:GrantDeath(player: Player, enemyId: string?)
	if not enemyId then return end

	local rule = DiscoveryConfig.Resolve(enemyId)
	local before, after = EnemyDiscoveryService:Grant(player, enemyId, rule.Death)
	if after <= before then return end

	replicate(player)
	PendingReveal[player] = { Id = enemyId, Before = before, After = after }
end

local function hasView(eye: Vector3, look: Vector3, character: Model, model: Model, rule): boolean
	local bounds = model:GetBoundingBox()
	local offset = bounds.Position - eye
	local distance = offset.Magnitude
	if distance > rule.Range then return false end
	if distance < 1e-3 then return true end

	local angle = math.deg(math.acos(math.clamp(offset.Unit:Dot(look), -1, 1)))
	if angle > rule.Angle then return false end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, model }
	params.RespectCanCollide = true

	return workspace:Raycast(eye, offset, params) == nil
end

local function activeModels(): { { Id: string, Model: Model } }
	local entries = {}
	for _, enemy in EnemyService:GetActive() do
		local id = enemy.EnemyId
		if not id then continue end

		for _, model in (enemy.Models or { enemy.Model }) do
			if typeof(model) == "Instance" and model:IsA("Model") and model:IsDescendantOf(workspace) then
				table.insert(entries, { Id = id, Model = model })
			end
		end
	end
	return entries
end

local function sweepPlayer(player: Player, models: { { Id: string, Model: Model } }, delta: number): boolean
	local character = player.Character
	local root = CharacterService.GetAliveRootFromCharacter(character)
	if not (character and root) then return false end

	local eye, look = EnemyObservationService:GetView(player)
	if not (eye and look) then return false end

	local dwell = Dwell[player]
	if not dwell then return false end

	local seen: { [string]: boolean } = {}
	local gained = false

	for _, entry in models do
		local rule = DiscoveryConfig.Resolve(entry.Id)
		local current = EnemyDiscoveryService:Get(player, entry.Id)
		if current >= 1 then continue end

		if rule.Sight and hasView(eye, look, character, entry.Model, rule.Sight) then
			seen[entry.Id] = true
			local held = (dwell[entry.Id] or 0) + delta
			dwell[entry.Id] = held

			if held >= rule.Sight.MinDwell then
				EnemyDiscoveryService:Grant(player, entry.Id, rule.Sight.GainPerSecond * delta)
				gained = true
			end
		end

		if rule.Proximity then
			local distance = (entry.Model:GetPivot().Position - root.Position).Magnitude
			if distance <= rule.Proximity.Range then
				EnemyDiscoveryService:Grant(player, entry.Id, rule.Proximity.GainPerSecond * delta)
				gained = true
			end
		end
	end

	for id in dwell do
		if not seen[id] then
			dwell[id] = nil
		end
	end

	if not gained then return false end

	local last = Replicated[player] or {}
	for id, value in Progress[player] or {} do
		if value >= 1 and (last[id] or 0) < 1 then return true end
		if value - (last[id] or 0) >= DiscoveryConfig.ReplicateStep then return true end
	end
	return false
end

local function sweep(delta: number)
	local models = activeModels()
	if #models == 0 then return end

	for _, player in Players:GetPlayers() do
		if sweepPlayer(player, models, delta) then
			replicate(player)
		end
	end
end

if FLAGS.Enemies then
	RunService.Heartbeat:Connect(function(delta: number)
		accumulator += delta
		if accumulator < DiscoveryConfig.SweepInterval then return end

		local elapsed = accumulator
		accumulator = 0
		sweep(elapsed)
	end)
end

local function watchCharacter(player: Player)
	local pending = PendingReveal[player]
	if not pending then return end
	PendingReveal[player] = nil

	if not player:IsDescendantOf(Players) then return end
	Reveal:FireClient(player, pending.Id, pending.Before, pending.After)
end

local function watchPlayer(player: Player)
	Progress[player] = {}
	Dwell[player] = {}

	task.spawn(function()
		local profile = DataSaveService:Wait(player)
		if not profile or not player:IsDescendantOf(Players) then return end

		local saved = profile.Data.DiscoveredEnemies
		local loaded = {}
		if type(saved) == "table" then
			for id, value in saved do
				if type(id) == "string" and type(value) == "number" then
					loaded[id] = math.clamp(value, 0, 1)
				end
			end
		end

		Progress[player] = loaded
		replicate(player)
	end)

	player.CharacterAdded:Connect(function()
		watchCharacter(player)
	end)
end

Update.OnServerEvent:Connect(function(player: Player)
	replicate(player)
end)

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)

Players.PlayerRemoving:Connect(function(player: Player)
	persist(player)
	Progress[player] = nil
	Dwell[player] = nil
	Replicated[player] = nil
	PendingReveal[player] = nil
end)

return EnemyDiscoveryService
