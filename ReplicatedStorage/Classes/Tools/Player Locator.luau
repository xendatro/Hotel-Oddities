local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientTool = require(ReplicatedStorage.Classes.ClientTool)
local PlayerLocatorService = require(ReplicatedStorage.Services.PlayerLocatorService)

--- @class PlayerLocator
--- The locator is passive while it is equipped: its client service owns the GUI and markers, while
--- this tool class only supplies the equip lifetime that turns that service on and off.
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
