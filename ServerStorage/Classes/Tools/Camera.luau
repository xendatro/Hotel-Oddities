local ServerStorage = game:GetService("ServerStorage")

local ServerTool = require(ServerStorage.Classes.ServerTool)
local PhotoCameraService = require(ServerStorage.Services.PhotoCameraService)

local Camera = ServerTool.extend("Camera")

function Camera.new(tool: Tool)
	local self = ServerTool.new(tool, Camera)

	self:On("Place", function(player: Player, pivot: any)
		self:_place(player, pivot)
	end)

	return self
end

function Camera:_place(player: Player, pivot: any)
	if self.Placed then return end
	if typeof(pivot) ~= "CFrame" then return end
	if player ~= self:GetPlayer() then return end
	if not self:IsAlive() then return end

	local model = PhotoCameraService:Place(player, pivot)
	if not model then return end

	self.Placed = true
	self:PlaySound(self.Config.Sound, self.Tool:FindFirstChild("Handle"))
	self:Consume(1)
end

return Camera
