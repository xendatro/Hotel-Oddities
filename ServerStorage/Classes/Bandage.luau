local ServerStorage = game:GetService("ServerStorage")

local Healer = require(ServerStorage.Classes.Healer)

--- @class Bandage
--- The cheap patch-up: a small heal, meant to be carried in numbers.
local Bandage = setmetatable({}, Healer)
Bandage.__index = Bandage

local HEAL_AMOUNT = 10

function Bandage.new(bandage: Tool)
	return setmetatable(Healer.new(bandage, HEAL_AMOUNT, "Bandage"), Bandage)
end

return Bandage
