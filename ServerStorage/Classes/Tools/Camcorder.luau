local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CaptureConfig = require(ReplicatedStorage.Configs.CaptureConfig)
local MarketplaceService = require(ReplicatedStorage.Services.MarketplaceService)
local PerkService = require(ServerStorage.Services.PerkService)
local ServerTool = require(ServerStorage.Classes.ServerTool)

local Camcorder = ServerTool.extend("Camcorder")

function Camcorder.new(tool: Tool)
	local self = ServerTool.new(tool, Camcorder)

	self:On("Record", function(player: Player)
		self:_record(player)
	end)

	return self
end

function Camcorder:_record(player: Player)
	if player ~= self:GetPlayer() then return end
	if not self:IsAlive() then return end

	if CaptureConfig.RequireGamepass then
		local passName = self.Config.Gamepass
		local passId = passName and MarketplaceService.Gamepasses[passName]
		if not passId or passId == 0 or not PerkService:Owns(player, passName) then
			self:Fire("Denied", CaptureConfig.Text.NoPass)
			return
		end
	end

	self:PlaySound(self.Config.Sound, self.Tool:FindFirstChild("Handle"))
	self:Fire("Allowed")
end

return Camcorder
