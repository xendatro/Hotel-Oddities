local ServerStorage = game:GetService("ServerStorage")

local PlayerOddityTool = require(ServerStorage.Classes.PlayerOddityTool)

local BigHead = PlayerOddityTool.extend("Big Head")

function BigHead.new(tool: Tool)
	return PlayerOddityTool.new(tool, BigHead)
end

return BigHead
