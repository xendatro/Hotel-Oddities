local ServerStorage = game:GetService("ServerStorage")

local PlayerOddityTool = require(ServerStorage.Classes.PlayerOddityTool)

local SmallCharacter = PlayerOddityTool.extend("Small Character")

function SmallCharacter.new(tool: Tool)
	return PlayerOddityTool.new(tool, SmallCharacter)
end

return SmallCharacter
