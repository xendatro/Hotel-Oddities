local ServerStorage = game:GetService("ServerStorage")

local HallwayOddity = require(ServerStorage.Classes.HallwayOddity)
local OddityRemotes = require(ServerStorage.Modules.OddityRemotes)

local MapDoors = OddityRemotes.Event("MapDoors")

local DoorsOpen = HallwayOddity.extend("DoorsOpen", HallwayOddity)

DoorsOpen.RequiresPlayer = true

function DoorsOpen.new(config: { [string]: any }?)
	return HallwayOddity.new(config, DoorsOpen)
end

function DoorsOpen:OnStart()
	MapDoors:FireAllClients(
		"Start",
		self.Token,
		self.BoxCFrame,
		self.BoxSize,
		math.clamp(self:Setting("OpeningSpeed", 0.75), 0.05, 4)
	)
	return true
end

function DoorsOpen:OnStop()
	MapDoors:FireAllClients("Stop", self.Token)
end

return DoorsOpen
