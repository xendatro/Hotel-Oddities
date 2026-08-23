local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local StatsHUDConfig = require(ReplicatedStorage.Configs.StatsHUDConfig)
local EnemyService = require(ServerStorage.Services.EnemyService)

local EnemyDebugService = {}

local function ensure(parent: Instance, name: string, className: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then return existing end

	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created
end

local communication = ensure(ReplicatedStorage, "Communication", "Folder")
local enemies = ensure(communication, "Enemies", "Folder")
local Snapshot = ensure(enemies, "DebugSnapshot", "RemoteEvent") :: RemoteEvent

local function stateOf(enemy: any): string
	local machine = enemy.StateMachine
	local state = machine and machine.State
	return if type(state) == "string" then state else "--"
end

--- Walks the enemies the server actually owns rather than the models tagged in
--- the workspace: one entry per enemy, so a Sisters pair counts once, and
--- nothing is missing because the asking client has not streamed it in.
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

	for _, player in players do
		Snapshot:FireClient(player, entries)
	end
end)

return EnemyDebugService
