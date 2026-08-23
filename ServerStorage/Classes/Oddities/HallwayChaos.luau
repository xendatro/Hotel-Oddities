local ServerStorage = game:GetService("ServerStorage")

local HallwayOddity = require(ServerStorage.Classes.HallwayOddity)
local LightService = require(ServerStorage.Services.LightService)
local OddityRemotes = require(ServerStorage.Modules.OddityRemotes)

local MapDoors = OddityRemotes.Event("MapDoors")

local HallwayChaos = HallwayOddity.extend("HallwayChaos", HallwayOddity)

HallwayChaos.RequiresPlayer = false

function HallwayChaos.new(config: { [string]: any }?)
	local self = HallwayOddity.new(config, HallwayChaos)
	self.LightClaim = nil :: any
	return self
end

function HallwayChaos:OnStart()
	self.LightClaim = LightService:FlickerChaosAlongHallway(
		(self.Span :: any).Center,
		self.Duration,
		math.max(self:Setting("LightIntervalMin", 0.06), 0.02),
		math.max(self:Setting("LightIntervalMax", 0.24), 0.03)
	)

	MapDoors:FireAllClients(
		"Start",
		self.Token,
		self.BoxCFrame,
		self.BoxSize,
		math.clamp(self:Setting("OpeningSpeed", 1.2), 0.05, 4),
		"Chaos",
		math.clamp(self:Setting("ClosingSpeed", 1.2), 0.05, 4),
		math.max(self:Setting("DoorIntervalMin", 0.3), 0.05),
		math.max(self:Setting("DoorIntervalMax", 1.1), 0.06)
	)
	return true
end

function HallwayChaos:OnStop()
	if self.LightClaim then
		LightService:ReleaseFlicker(self.LightClaim)
		self.LightClaim = nil
	end
	MapDoors:FireAllClients("Stop", self.Token)
end

return HallwayChaos
