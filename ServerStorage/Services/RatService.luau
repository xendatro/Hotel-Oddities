local ServerStorage = game:GetService("ServerStorage")

local CrossingPool = require(ServerStorage.Classes.CrossingPool)
local FixtureCommand = require(ServerStorage.Services.FixtureCommandService)
local OddityService = require(ServerStorage.Services.OddityService)

local Class = OddityService:Get("Prop", "RatScurry")
if not Class then return {} end

local RatService = CrossingPool.new(Class, "rat")
FixtureCommand.Bind(RatService, "rat", { "rat", "ratscurry" })

return RatService
