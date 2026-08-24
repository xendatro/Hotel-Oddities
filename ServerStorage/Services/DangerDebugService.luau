local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local DangerMapService = require(ServerStorage.Services.DangerMapService)
local EnemyDirectorService = require(ServerStorage.Services.EnemyDirectorService)

local DangerDebugService = {}

if not (FLAGS.DangerDebug and RunService:IsStudio()) then
	return DangerDebugService
end

local TUNABLE = {
	Seed = true,
	FeatureScale = true,
	Octaves = true,
	Persistence = true,
	NoiseGain = true,
	Contrast = true,
	FloorHeight = true,
	FloorSeparation = true,
	SafeRadius = true,
	RampLength = true,
}

task.spawn(function()
	local setConfig = CommunicationService.Get("Danger", "SetConfig") :: RemoteEvent

	setConfig.OnServerEvent:Connect(function(player: Player, payload: any)
		if type(payload) ~= "table" then return end

		local overrides = {}
		local count = 0
		for key, value in payload do
			if TUNABLE[key] and type(value) == "number" and value == value then
				overrides[key] = value
				count += 1
			end
		end
		if count == 0 then return end

		DangerMapService:Rebake(overrides)
		EnemyDirectorService:Reset()

		warn(`[danger] rebaked from {player.Name}'s debug panel with {count} overrides`)
	end)
end)

return DangerDebugService
