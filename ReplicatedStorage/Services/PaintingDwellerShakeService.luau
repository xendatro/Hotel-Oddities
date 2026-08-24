local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local ShakeService = require(ReplicatedStorage.Services.ShakeService)

local PaintingDwellerShakeService = {}

if not RunService:IsClient() then
	return PaintingDwellerShakeService
end

task.spawn(function()
	local remote = CommunicationService.Get("Oddities", "PaintingDwellerPop") :: RemoteEvent
	remote.OnClientEvent:Connect(function()
		ShakeService:Create({ ID = "PaintingDwellerPop", ShakeType = "Once", Preset = "Slam" })
	end)
end)

return PaintingDwellerShakeService
