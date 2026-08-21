local ServerStorage = game:GetService("ServerStorage")

local ServerTool = require(ServerStorage.Classes.ServerTool)
local PerkService = require(ServerStorage.Services.PerkService)

local Pathfinder = ServerTool.extend("Pathfinder")

function Pathfinder.new(tool: Tool)
	local self = ServerTool.new(tool, Pathfinder)

	if tool:GetAttribute("uses") == nil then
		tool:SetAttribute("uses", self.Config.Uses)
	end

	self:On("Placed", function(player: Player)
		self:_spend(player)
	end)

	return self
end

function Pathfinder:_spend(player: Player)
	if PerkService:Owns(player, "Pathfinder") then return end

	local remaining = (self.Tool:GetAttribute("uses") or self.Config.Uses) - 1
	if remaining > 0 then
		self.Tool:SetAttribute("uses", remaining)
		return
	end

	self.Tool:SetAttribute("uses", self.Config.Uses)
	self:Consume(1)
end

return Pathfinder
