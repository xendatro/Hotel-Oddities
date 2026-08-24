local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsClient() then
	return {}
end

local Interaction = require(ReplicatedStorage.Classes.Interaction)

return Interaction.new()
