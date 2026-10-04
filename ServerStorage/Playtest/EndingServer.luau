-- Server half of the ending cutscene playtest: runs what /ending runs, without the
-- chat command's group-role gate. Call through ServerBridge with "@player".
local ServerStorage = game:GetService("ServerStorage")

local EndingService = require(ServerStorage.Services.EndingService)

local EndingServer = {}

function EndingServer.Preview(player: Player): boolean
	return EndingService:Preview(player)
end

function EndingServer.Finish(player: Player): boolean
	return EndingService:Finish(player)
end

function EndingServer.IsEnding(player: Player): boolean
	return EndingService:IsEnding(player)
end

return EndingServer
