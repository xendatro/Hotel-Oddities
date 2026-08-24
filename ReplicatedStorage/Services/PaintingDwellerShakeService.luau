local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ShakeService = require(ReplicatedStorage.Services.ShakeService)

local PaintingDwellerShakeService = {}

if not RunService:IsClient() then
	return PaintingDwellerShakeService
end

task.spawn(function()
	local communication = ReplicatedStorage:WaitForChild("Communication")
	local oddities = communication:WaitForChild("Oddities")
	local remote = oddities:WaitForChild("PaintingDwellerPop") :: RemoteEvent
	remote.OnClientEvent:Connect(function()
		ShakeService:Create({ ID = "PaintingDwellerPop", ShakeType = "Once", Preset = "Slam" })
	end)
end)

return PaintingDwellerShakeService
