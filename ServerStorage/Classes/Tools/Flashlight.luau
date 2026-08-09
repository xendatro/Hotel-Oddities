local ServerStorage = game:GetService("ServerStorage")

local ServerTool = require(ServerStorage.Classes.ServerTool)

--- @class Flashlight
--- A reusable light. Its model already carries the click sound and spotlight, so toggling them on
--- the server keeps the beam and click visible to everyone without inventing duplicate assets.
local Flashlight = ServerTool.extend("Flashlight")

function Flashlight.new(tool: Tool)
	local self = ServerTool.new(tool, Flashlight)
	self:SetEnabled(false)
	return self
end

function Flashlight:SetEnabled(enabled: boolean)
	self.Enabled = enabled

	local handle = self.Tool:FindFirstChild("Handle")
	local light = handle and handle:FindFirstChildWhichIsA("SpotLight")
	if light then
		light.Enabled = enabled
	end
end

function Flashlight:OnActivated()
	self:SetEnabled(not self.Enabled)

	local handle = self.Tool:FindFirstChild("Handle")
	local sound = handle and handle:FindFirstChildWhichIsA("Sound")
	if sound then
		sound:Play()
	end
end

function Flashlight:OnUnequipped()
	self:SetEnabled(false)
end

function Flashlight:OnDestroy()
	self:SetEnabled(false)
end

return Flashlight
