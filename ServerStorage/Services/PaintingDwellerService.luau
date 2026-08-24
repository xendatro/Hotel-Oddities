local ServerStorage = game:GetService("ServerStorage")

local FixtureCommand = require(ServerStorage.Modules.FixtureCommand)
local FixturePool = require(ServerStorage.Modules.FixturePool)
local OddityService = require(ServerStorage.Services.OddityService)

local Class = OddityService:Get("Prop", "PaintingDweller")
if not Class then return {} end

local PaintingDwellerService = FixturePool.new(Class, "dweller")
FixtureCommand.Bind(PaintingDwellerService, "dweller", { "dweller", "paintingdweller" })

return PaintingDwellerService
