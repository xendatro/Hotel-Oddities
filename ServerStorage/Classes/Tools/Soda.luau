local ServerStorage = game:GetService("ServerStorage")

local SpeedDrink = require(ServerStorage.Classes.SpeedDrink)

local Soda = SpeedDrink.extend("Soda")

function Soda.new(tool: Tool)
	return SpeedDrink.new(tool, Soda)
end

return Soda
