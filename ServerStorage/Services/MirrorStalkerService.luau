local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local MirrorRoomService = require(ReplicatedStorage.Services.MirrorRoomService)
local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local EnemyDirectorService = require(ServerStorage.Services.EnemyDirectorService)
local EnemyService = require(ServerStorage.Services.EnemyService)

local ENEMY_ID = "MirrorStalker"
local STALKER_ID = "Stalker"

local MirrorStalkerService = {}

if not FLAGS.Enemies then
	return MirrorStalkerService
end

local Config = EnemyConfigs[ENEMY_ID]

local active: any? = nil
local nextAllowedAt = 0
local accumulator = 0
local Inside: { [Player]: boolean } = {}

local function isStalked(player: Player): boolean
	if EnemyDirectorService:GetStalkerTarget() == player then return true end

	for _, enemy in EnemyService:GetActive() do
		if enemy.EnemyId ~= STALKER_ID then continue end
		if enemy.Target == player or enemy.Audience == player then return true end
	end

	return false
end

local function occupants(bounds: MirrorRoomService.Bounds): { Player }
	local players = {}
	for _, player in Players:GetPlayers() do
		local root = CharacterService.GetAliveRoot(player)
		if root and MirrorRoomService.IsInside(bounds, root.Position) then
			table.insert(players, player)
		end
	end
	return players
end

function MirrorStalkerService:GetActive(): any?
	return active
end

function MirrorStalkerService:Clear(): boolean
	if not active then return false end
	active:Despawn()
	return true
end

function MirrorStalkerService:Trigger(player: Player): (boolean, string?)
	if active then return false, "one is already following someone" end

	local root = CharacterService.GetAliveRoot(player)
	if not root then return false, "no living character" end

	local room, bounds = MirrorRoomService.GetRoomAt(root.Position)
	if not (room and bounds) then return false, "not standing in the mirror room" end

	local alone = occupants(bounds)
	if #alone > 1 then return false, "another player is in the mirror room" end

	local enemy = EnemyService:Spawn(ENEMY_ID, root.CFrame, player)
	if not enemy then return false, "spawn refused" end
	if enemy.Despawned then return false, "the spawn point was rejected" end

	active = enemy
	enemy.OnDespawn = function()
		active = nil
		nextAllowedAt = os.clock() + Config.Cooldown
	end

	return true, nil
end

local function consider(player: Player)
	if active or os.clock() < nextAllowedAt then return end
	if isStalked(player) then return end
	if math.random() > Config.Chance then
		nextAllowedAt = os.clock() + Config.RollCooldown
		return
	end

	task.delay(math.random() * (Config.SpawnDelayMax - Config.SpawnDelayMin) + Config.SpawnDelayMin, function()
		if not Inside[player] then return end
		MirrorStalkerService:Trigger(player)
	end)
end

local function poll(deltaTime: number)
	accumulator += deltaTime
	if accumulator < Config.PollInterval then return end
	accumulator = 0

	local seen: { [Player]: boolean } = {}
	for _, room in MirrorRoomService.GetRooms() do
		local bounds = MirrorRoomService.GetBounds(room)
		if not bounds then continue end

		local players = occupants(bounds)
		for _, player in players do
			seen[player] = true
			if not Inside[player] then
				Inside[player] = true
				if #players == 1 then
					consider(player)
				end
			end
		end
	end

	for player in Inside do
		if not seen[player] then
			Inside[player] = nil
		end
	end
end

RunService.Heartbeat:Connect(poll)
CharacterService.CleanupOnLeave(Inside)

return MirrorStalkerService
