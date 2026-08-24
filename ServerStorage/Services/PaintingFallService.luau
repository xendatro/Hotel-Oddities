local ServerStorage = game:GetService("ServerStorage")

local FixtureCommand = require(ServerStorage.Services.FixtureCommandService)
local FixturePool = require(ServerStorage.Classes.FixturePool)
local OddityService = require(ServerStorage.Services.OddityService)

local Class = OddityService:Get("Prop", "PaintingFall")
if not Class then return {} end

local PaintingFallService = FixturePool.new(Class, "painting")
FixtureCommand.Bind(PaintingFallService, "painting", { "painting", "paintings" })

return PaintingFallService
