local ServerStorage = game:GetService("ServerStorage")

local Healer = require(ServerStorage.Classes.Healer)

--- @class Medkit
--- The heavy heal: most of a health bar in one use. Amount comes from
--- `ToolConfigs.Medkit.HealAmount`.
local Medkit = Healer.extend("Medkit")

function Medkit.new(tool: Tool)
	return Healer.new(tool, Medkit)
end

return Medkit
