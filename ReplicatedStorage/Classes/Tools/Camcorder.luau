local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientTool = require(ReplicatedStorage.Classes.ClientTool)
local CaptureConfig = require(ReplicatedStorage.Configs.CaptureConfig)
local CaptureGalleryService = require(ReplicatedStorage.Services.CaptureGalleryService)
local NotificationService = require(ReplicatedStorage.Services.NotificationService)
local PhotoDevelopService = require(ReplicatedStorage.Services.PhotoDevelopService)

local Camcorder = ClientTool.extend("Camcorder")

function Camcorder.new(tool: Tool)
	local self = ClientTool.new(tool, Camcorder)

	self:On("Allowed", function()
		self:_roll()
	end)

	self:On("Denied", function(reason: string?)
		NotificationService:Show(reason or CaptureConfig.Text.NoPass)
	end)

	return self
end

function Camcorder:_stow()
	local humanoid = self.Humanoid
	if humanoid then
		humanoid:UnequipTools()
	end
end

function Camcorder:_roll()
	if CaptureGalleryService:IsRecording() then return end

	local settings = CaptureConfig.Video

	self:_stow()
	task.wait(settings.HideToolFor)

	local started = CaptureGalleryService:StartVideo(function(media, message)
		self.StopAt = nil

		if not media then
			NotificationService:Show(message or CaptureConfig.Text.Unsupported)
			return
		end

		PhotoDevelopService:Show(media, true)
	end)

	if not started then return end

	NotificationService:Show(CaptureConfig.Text.Recording)

	local duration = math.min(settings.Duration, settings.MaxDuration)
	self.StopAt = os.clock() + duration

	task.delay(duration, function()
		if not self.StopAt or os.clock() < self.StopAt - 0.05 then return end
		self.StopAt = nil
		CaptureGalleryService:StopVideo()
	end)
end

function Camcorder:OnEquipped()
	if not CaptureGalleryService:IsRecording() then return end

	self.StopAt = nil
	CaptureGalleryService:StopVideo()
end

function Camcorder:OnActivated()
	if CaptureGalleryService:IsRecording() then
		self.StopAt = nil
		CaptureGalleryService:StopVideo()
		return
	end

	self:Fire("Record")
end

function Camcorder:OnDestroy()
	self.StopAt = nil
	if CaptureGalleryService:IsRecording() then
		CaptureGalleryService:StopVideo()
	end
end

return Camcorder
