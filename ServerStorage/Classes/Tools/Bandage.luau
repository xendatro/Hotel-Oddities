local ServerStorage = game:GetService("ServerStorage")

local Healer = require(ServerStorage.Classes.Healer)

--- @class Bandage
--- The cheap patch-up: a small heal, meant to be carried in numbers. Amount comes from
--- `ToolConfigs.Bandage.HealAmount`.
local Bandage = Healer.extend("Bandage")

function Bandage.new(tool: Tool)
	return Healer.new(tool, Bandage)
end

return Bandage
