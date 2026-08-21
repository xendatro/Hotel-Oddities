local ServerStorage = game:GetService("ServerStorage")

local Healer = require(ServerStorage.Classes.Healer)

local Bandage = Healer.extend("Bandage")

function Bandage.new(tool: Tool)
	return Healer.new(tool, Bandage)
end

return Bandage
