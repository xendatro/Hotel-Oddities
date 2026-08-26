local ServerStorage = game:GetService("ServerStorage")

local PlayerOddityTool = require(ServerStorage.Classes.PlayerOddityTool)

local BigCharacter = PlayerOddityTool.extend("Big Character")

function BigCharacter.new(tool: Tool)
	return PlayerOddityTool.new(tool, BigCharacter)
end

return BigCharacter
