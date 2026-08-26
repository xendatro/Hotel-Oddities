local ServerStorage = game:GetService("ServerStorage")

local PlayerOddityTool = require(ServerStorage.Classes.PlayerOddityTool)

local Transparency = PlayerOddityTool.extend("Transparency")

function Transparency.new(tool: Tool)
	return PlayerOddityTool.new(tool, Transparency)
end

return Transparency
