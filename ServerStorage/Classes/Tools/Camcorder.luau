local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CaptureConfig = require(ReplicatedStorage.Configs.CaptureConfig)
local MarketplaceService = require(ReplicatedStorage.Services.MarketplaceService)
local InventoryService = require(ServerStorage.Services.InventoryService)
local PerkService = require(ServerStorage.Services.PerkService)
local ServerTool = require(ServerStorage.Classes.ServerTool)

local Camcorder = ServerTool.extend("Camcorder")

function Camcorder.new(tool: Tool)
	local self = ServerTool.new(tool, Camcorder)

	self:On("Record", function(player: Player)
		self:_record(player)
	end)
	self:On("Finished", function(player: Player)
		self:_finish(player)
	end)
	self:On("Kept", function(player: Player)
		self:_keep(player)
	end)
	self:On("Burned", function(player: Player)
		self:_burn(player)
	end)
	self:On("Cancelled", function(player: Player)
		self:_cancel(player)
	end)

	return self
end

function Camcorder:_record(player: Player)
	if player ~= self:GetPlayer() then return end
	if not self:IsAlive() then return end
	if self.Recording or self.PendingCapture then return end

	if CaptureConfig.RequireGamepass then
		local passName = self.Config.Gamepass
		local passId = passName and MarketplaceService.Gamepasses[passName]
		if not passId or passId == 0 or not PerkService:Owns(player, passName) then
			self:Fire("Denied", CaptureConfig.Text.NoPass)
			return
		end
	end

	self.Recording = true
	self:PlaySound(self.Config.Sound, self.Tool:FindFirstChild("Handle"))
	self:Fire("Allowed")
end

function Camcorder:_finish(player: Player)
	if player ~= self:GetPlayer() or not self.Recording then return end
	self.Recording = false
	self.PendingCapture = true
end

function Camcorder:_keep(player: Player)
	if player ~= self:GetPlayer() or not self.PendingCapture then return end
	self.PendingCapture = false

	local passName = self.Config.Gamepass
	if type(passName) ~= "string" then return end
	if not PerkService:WaitForPasses(player) or PerkService:Owns(player, passName) then return end

	InventoryService:RemoveAll(player, self.Name)
end

function Camcorder:_burn(player: Player)
	if player ~= self:GetPlayer() then return end
	self.PendingCapture = false
end

function Camcorder:_cancel(player: Player)
	if player ~= self:GetPlayer() then return end
	self.Recording = false
	self.PendingCapture = false
end

function Camcorder:OnDestroy()
	self.Recording = false
	self.PendingCapture = false
end

return Camcorder
