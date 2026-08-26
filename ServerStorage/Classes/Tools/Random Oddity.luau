local ServerStorage = game:GetService("ServerStorage")

local PlayerOddityTool = require(ServerStorage.Classes.PlayerOddityTool)

local RandomOddity = PlayerOddityTool.extend("Random Oddity")

function RandomOddity.new(tool: Tool)
	return PlayerOddityTool.new(tool, RandomOddity)
end

return RandomOddity
