local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local StatsHUDConfig = require(ReplicatedStorage.Configs.StatsHUDConfig)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local EnemyDirectorService = require(ServerStorage.Services.EnemyDirectorService)
local EnemyService = require(ServerStorage.Services.EnemyService)

local EnemyDebugService = {}

local Snapshot = CommunicationService.Ensure("Enemies", "DebugSnapshot") :: RemoteEvent

local function stateOf(enemy: any): string
	local machine = enemy.StateMachine
	local state = machine and machine.State
	return if type(state) == "string" then state else "--"
end

function EnemyDebugService:GetSnapshot(): { any }
	local entries = {}

	for _, enemy in EnemyService:GetActive() do
		local model = enemy.Model :: Model?
		if not (model and model.Parent) then continue end

		table.insert(entries, {
			Id = enemy.EnemyId or model.Name,
			State = stateOf(enemy),
			Position = model:GetPivot().Position,
		})
	end

	return entries
end

local Accumulator = 0

RunService.Heartbeat:Connect(function(deltaTime: number)
	Accumulator += deltaTime
	if Accumulator < StatsHUDConfig.Enemies.Interval then return end
	Accumulator = 0

	local players = Players:GetPlayers()
	if #players == 0 then return end

	local entries = EnemyDebugService:GetSnapshot()
	local stalkerTarget = EnemyDirectorService:GetStalkerTarget()
	local stalkerName = if stalkerTarget then stalkerTarget.Name else nil

	for _, player in players do
		Snapshot:FireClient(player, entries, stalkerName)
	end
end)

return EnemyDebugService
