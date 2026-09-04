local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientTool = require(ReplicatedStorage.Classes.ClientTool)
local CaptureConfig = require(ReplicatedStorage.Configs.CaptureConfig)
local CaptureGalleryService = require(ReplicatedStorage.Services.CaptureGalleryService)
local NotificationService = require(ReplicatedStorage.Services.NotificationService)
local PhotoDevelopService = require(ReplicatedStorage.Services.PhotoDevelopService)

local Camcorder = ClientTool.extend("Camcorder")
local HUD = CaptureConfig.Video.Hud
local STOP_ACTION = "StopCamcorderRecording"

local recordingGui: ScreenGui? = nil
local recordingDot: Frame? = nil
local recordingStop: TextButton? = nil
local recordingDotTransparency = 0
local stopHandler: (() -> ())? = nil
local blinkVersion = 0

local function getRecordingGui(): ScreenGui
	if recordingGui and recordingGui.Parent then return recordingGui end

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(HUD.GuiName, 20) :: ScreenGui?
	assert(gui, `Camcorder: {HUD.GuiName} did not replicate`)
	recordingGui = gui
	local panel = gui:WaitForChild("Panel", 10) :: Frame
	recordingDot = panel:WaitForChild("Dot", 10) :: Frame
	recordingDotTransparency = recordingDot.BackgroundTransparency
	local stop = panel:WaitForChild("Stop", 10) :: TextButton
	recordingStop = stop

	stop.Activated:Connect(function()
		local handler = stopHandler
		if not handler then return end
		stopHandler = nil
		stop.Interactable = false
		stop.Text = HUD.StoppingText
		handler()
	end)

	return gui
end

local function showRecording(onStop: () -> ())
	local gui = getRecordingGui()
	stopHandler = onStop
	gui.Enabled = true

	if recordingStop then
		recordingStop.Interactable = true
		recordingStop.Text = HUD.StopText
	end

	blinkVersion += 1
	local version = blinkVersion
	task.spawn(function()
		while version == blinkVersion and gui.Enabled and recordingDot and recordingDot.Parent do
			recordingDot.BackgroundTransparency = if recordingDot.BackgroundTransparency > 0.5
				then recordingDotTransparency
				else 1
			task.wait(CaptureConfig.Overlay.BlinkTime)
		end
	end)
end

local function hideRecording()
	stopHandler = nil
	blinkVersion += 1
	if recordingGui then recordingGui.Enabled = false end
	if recordingDot then recordingDot.BackgroundTransparency = recordingDotTransparency end
end

ContextActionService:BindAction(STOP_ACTION, function(_, state: Enum.UserInputState)
	if state ~= Enum.UserInputState.Begin or not stopHandler then
		return Enum.ContextActionResult.Pass
	end

	local handler = stopHandler
	stopHandler = nil
	if recordingStop then
		recordingStop.Interactable = false
		recordingStop.Text = HUD.StoppingText
	end
	handler()
	return Enum.ContextActionResult.Sink
end, false, HUD.StopKey, Enum.KeyCode.ButtonB)

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
	if CaptureGalleryService:IsRecording() then
		self:_stow()
		return
	end

	local settings = CaptureConfig.Video

	self:_stow()
	task.wait(settings.HideToolFor)

	self.OwnsRecording = true

	local function stop()
		if not self.OwnsRecording then return end
		self.StopAt = nil
		CaptureGalleryService:StopVideo()
	end

	local started = CaptureGalleryService:StartVideo(function(media, message)
		self.StopAt = nil
		self.OwnsRecording = false
		if self.Tool.Parent then self.Tool.Enabled = true end
		hideRecording()

		if not media then
			NotificationService:Show(message or CaptureConfig.Text.Unsupported)
			return
		end

		PhotoDevelopService:Show(media, true)
	end)

	if not started then
		self.OwnsRecording = false
		hideRecording()
		return
	end

	NotificationService:Show(CaptureConfig.Text.Recording)
	self.Tool.Enabled = false
	showRecording(stop)

	local duration = math.min(settings.Duration, settings.MaxDuration)
	self.StopAt = os.clock() + duration

	task.delay(duration, function()
		if not self.StopAt or os.clock() < self.StopAt - 0.05 then return end
		stop()
	end)
end

function Camcorder:OnEquipped()
	if not CaptureGalleryService:IsRecording() then return end
	task.defer(function()
		if CaptureGalleryService:IsRecording() then
			self:_stow()
		end
	end)
end

function Camcorder:OnActivated()
	if CaptureGalleryService:IsRecording() then
		self:_stow()
		return
	end

	self:Fire("Record")
end

function Camcorder:OnDestroy()
	self.StopAt = nil
	if self.OwnsRecording and CaptureGalleryService:IsRecording() then
		CaptureGalleryService:StopVideo()
	end
	ClientTool.OnDestroy(self)
end

return Camcorder
