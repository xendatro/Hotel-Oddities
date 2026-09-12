local ServerStorage = game:GetService("ServerStorage")

local ServerTool = require(ServerStorage.Classes.ServerTool)
local ComputerChipService = require(ServerStorage.Services.ComputerChipService)

local ComputerChip = ServerTool.extend("ComputerChip")

function ComputerChip.new(tool: Tool)
	return ServerTool.new(tool, ComputerChip)
end

function ComputerChip:OnActivated()
	local player = self:GetPlayer()
	if player then
		ComputerChipService:Activate(player, self.Tool, self.Config.ColorKey)
	end
end

return ComputerChip
