local ServerStorage = game:GetService("ServerStorage")

local SpeedDrink = require(ServerStorage.Classes.SpeedDrink)

local EnergyDrink = SpeedDrink.extend("EnergyDrink")

function EnergyDrink.new(tool: Tool)
	return SpeedDrink.new(tool, EnergyDrink)
end

return EnergyDrink
