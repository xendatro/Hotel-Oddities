local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientTool = require(ReplicatedStorage.Classes.ClientTool)
local PlayerLocatorService = require(ReplicatedStorage.Services.PlayerLocatorService)

local PlayerLocator = ClientTool.extend("PlayerLocator")

function PlayerLocator.new(tool: Tool)
	return ClientTool.new(tool, PlayerLocator)
end

function PlayerLocator:OnEquipped()
	PlayerLocatorService:SetEnabled(true)
end

function PlayerLocator:OnUnequipped()
	PlayerLocatorService:SetEnabled(false)
end

function PlayerLocator:OnDestroy()
	PlayerLocatorService:SetEnabled(false)
end

return PlayerLocator
