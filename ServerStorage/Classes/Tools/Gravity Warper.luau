local ServerStorage = game:GetService("ServerStorage")

local GravityWarpService = require(ServerStorage.Services.GravityWarpService)
local ServerTool = require(ServerStorage.Classes.ServerTool)

local GravityWarper = ServerTool.extend("GravityWarper")

function GravityWarper.new(tool: Tool)
	return ServerTool.new(tool, GravityWarper)
end

function GravityWarper:OnActivated()
	local player = self:GetPlayer()
	if not player or not GravityWarpService:CanWarp(player) then return end

	local duration = self.Config.Duration
	if not self:Consume() then return end

	GravityWarpService:Warp(player, duration)
end

return GravityWarper
