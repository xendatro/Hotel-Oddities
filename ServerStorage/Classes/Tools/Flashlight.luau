local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local FlashlightConfig = require(ReplicatedStorage.Configs.FlashlightConfig)
local ServerTool = require(ServerStorage.Classes.ServerTool)

local Flashlight = ServerTool.extend("Flashlight")

function Flashlight.new(tool: Tool)
	local self = ServerTool.new(tool, Flashlight)
	self:SetEnabled(false)
	return self
end

function Flashlight:SetEnabled(enabled: boolean)
	self.Enabled = enabled
	self.Tool:SetAttribute(FlashlightConfig.Attribute, enabled)

	local handle = self.Tool:FindFirstChild("Handle")
	local light = handle and handle:FindFirstChildWhichIsA("SpotLight")
	if light then
		light.Enabled = false
	end
end

function Flashlight:OnActivated()
	self:SetEnabled(not self.Enabled)

	local handle = self.Tool:FindFirstChild("Handle")
	local emitter = handle and handle:FindFirstChildWhichIsA("AudioEmitter")
	if emitter then
		(emitter.Player :: AudioPlayer):Play()
	end
end

function Flashlight:OnUnequipped()
	self:SetEnabled(false)
end

function Flashlight:OnDestroy()
	self:SetEnabled(false)
end

return Flashlight
