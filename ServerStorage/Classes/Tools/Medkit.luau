local ServerStorage = game:GetService("ServerStorage")

local Healer = require(ServerStorage.Classes.Healer)

local Medkit = Healer.extend("Medkit")

function Medkit.new(tool: Tool)
	return Healer.new(tool, Medkit)
end

return Medkit
