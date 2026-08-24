local ServerStorage = game:GetService("ServerStorage")

local HallwayOddity = require(ServerStorage.Classes.HallwayOddity)

local ChaosWarning = HallwayOddity.extend("ChaosWarning", HallwayOddity)

ChaosWarning.Ambient = false
ChaosWarning.IncludeRoomFloors = true

function ChaosWarning.new(config: { [string]: any }?)
	return HallwayOddity.new(config, ChaosWarning)
end

function ChaosWarning:OnStart()
	self:FireMapDoors(
		"Start",
		self.BoxCFrame,
		self.BoxSize,
		math.clamp(self:Setting("OpeningSpeed", 1.2), 0.05, 4),
		"Chaos",
		math.clamp(self:Setting("ClosingSpeed", 1.2), 0.05, 4),
		math.max(self:Setting("DoorIntervalMin", 0.3), 0.05),
		math.max(self:Setting("DoorIntervalMax", 1.1), 0.06),
		"ChaosWarning"
	)
	return true
end

function ChaosWarning:OnStop()
	self:FireMapDoors("Stop")
end

return ChaosWarning
