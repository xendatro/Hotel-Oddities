local ServerStorage = game:GetService("ServerStorage")

local FixtureCommand = require(ServerStorage.Services.FixtureCommandService)
local FixturePool = require(ServerStorage.Classes.FixturePool)
local OddityService = require(ServerStorage.Services.OddityService)

local Class = OddityService:Get("Prop", "LanternFall")
if not Class then return {} end

local LanternFallService = FixturePool.new(Class, "lantern")
FixtureCommand.Bind(LanternFallService, "lantern", { "lantern", "lanterns" })

return LanternFallService
