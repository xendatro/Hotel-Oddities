local ServerStorage = game:GetService("ServerStorage")

local HallwayOddity = require(ServerStorage.Classes.HallwayOddity)

local DoorsOpen = HallwayOddity.extend("DoorsOpen", HallwayOddity)

DoorsOpen.RequiresPlayer = true

function DoorsOpen.new(config: { [string]: any }?)
	return HallwayOddity.new(config, DoorsOpen)
end

function DoorsOpen:OnStart()
	self:FireMapDoors(
		"Start",
		self.BoxCFrame,
		self.BoxSize,
		math.clamp(self:Setting("OpeningSpeed", 0.75), 0.05, 4)
	)
	return true
end

function DoorsOpen:OnStop()
	self:FireMapDoors("Stop")
end

return DoorsOpen
