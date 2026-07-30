local ServerStorage = game:GetService("ServerStorage")

local Healer = require(ServerStorage.Classes.Healer)

--- @class Medkit
--- The heavy heal: most of a health bar in one use.
local Medkit = setmetatable({}, Healer)
Medkit.__index = Medkit

local HEAL_AMOUNT = 45

function Medkit.new(medkit: Tool)
	return setmetatable(Healer.new(medkit, HEAL_AMOUNT, "Medkit"), Medkit)
end

return Medkit
