local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local PhotoDevelopService = {}

if not RunService:IsClient() then
	return PhotoDevelopService
end

local CaptureConfig = require(ReplicatedStorage.Configs.CaptureConfig)
local PhotoConfig = require(ReplicatedStorage.Configs.PhotoConfig)
local CaptureGalleryService = require(ReplicatedStorage.Services.CaptureGalleryService)
local CaptureOverlayService = require(ReplicatedStorage.Services.CaptureOverlayService)
local InterfaceService = require(ReplicatedStorage.Services.InterfaceService)
local NotificationService = require(ReplicatedStorage.Services.NotificationService)

type Paper = {
	Frame: Frame,
	Window: Frame,
	Image: ImageLabel,
	Tape: VideoFrame,
	Sheen: Frame,
	Sweep: UIGradient,
	Close: TextButton,
}

local settings = PhotoConfig.Develop
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local screen = playerGui:WaitForChild("PhotoDevelop", 20) :: ScreenGui?
if not screen then
	warn("PhotoDevelopService: PhotoDevelop did not replicate")
	return PhotoDevelopService
end

local preview = screen:WaitForChild("Preview", 10) :: Frame
local previewWindow = preview:WaitForChild("Window", 10) :: Frame
local previewPaper: Paper = {
	Frame = preview,
	Window = previewWindow,
	Image = previewWindow:WaitForChild("Capture", 10) :: ImageLabel,
	Tape = previewWindow:WaitForChild("Tape", 10) :: VideoFrame,
	Sheen = previewWindow:WaitForChild("Sheen", 10) :: Frame,
	Sweep = (previewWindow:WaitForChild("Sheen", 10)):WaitForChild("Sweep", 10) :: UIGradient,
	Close = preview:WaitForChild("Close", 10) :: TextButton,
}
local previewOpen = preview:WaitForChild("Open", 10) :: TextButton
local actions = preview:WaitForChild("Actions", 10) :: Frame
local save = actions:WaitForChild("Save", 10) :: TextButton
local discard = actions:WaitForChild("Discard", 10) :: TextButton
local fullscreenPose = screen:WaitForChild("FullscreenPose", 10) :: Frame
local slidePose = screen:WaitForChild("SlidePose", 10) :: Frame
local backdrop = screen:WaitForChild("Backdrop", 10) :: Frame
local dismiss = backdrop:WaitForChild("Dismiss", 10) :: TextButton
local expanded = backdrop:WaitForChild("Photo", 10) :: Frame
local expandedWindow = expanded:WaitForChild("Window", 10) :: Frame
local expandedPaper: Paper = {
	Frame = expanded,
	Window = expandedWindow,
	Image = expandedWindow:WaitForChild("Capture", 10) :: ImageLabel,
	Tape = expandedWindow:WaitForChild("Tape", 10) :: VideoFrame,
	Sheen = expandedWindow:WaitForChild("Sheen", 10) :: Frame,
	Sweep = (expandedWindow:WaitForChild("Sheen", 10)):WaitForChild("Sweep", 10) :: UIGradient,
	Close = expanded:WaitForChild("Close", 10) :: TextButton,
}

local restAnchor = preview.AnchorPoint
local restPosition = preview.Position
local restSize = preview.Size
local restRotation = preview.Rotation
local expandedPosition = expanded.Position
local expandedSize = expanded.Size
local expandedRotation = expanded.Rotation
local backdropTransparency = backdrop.BackgroundTransparency
local previewCloseTransparency = previewPaper.Close.BackgroundTransparency
local previewCloseTextTransparency = previewPaper.Close.TextTransparency
local expandedCloseTransparency = expandedPaper.Close.BackgroundTransparency
local expandedCloseTextTransparency = expandedPaper.Close.TextTransparency

local currentMedia: CaptureGalleryService.Media? = nil
local mouseWasUnlocked: boolean? = nil
local busy = false

preview.Visible = false
backdrop.Visible = false
actions.Visible = false
save.Text = CaptureConfig.Prompt.SaveText
discard.Text = CaptureConfig.Prompt.DiscardText

local function setDecisionOpen(open: boolean)
	if open then
		if mouseWasUnlocked == nil then
			mouseWasUnlocked = InterfaceService:IsMouseUnlocked()
		end
		InterfaceService:SetMouseUnlocked(true, true)
		return
	end

	if mouseWasUnlocked == nil then return end
	local restore = mouseWasUnlocked or InterfaceService:GetActive() ~= ""
	mouseWasUnlocked = nil
	InterfaceService:SetMouseUnlocked(restore, false)
end

local function rectOf(frame: Frame): (UDim2, UDim2)
	local position = frame.AbsolutePosition
	local size = frame.AbsoluteSize
	return UDim2.fromOffset(position.X + size.X / 2, position.Y + size.Y / 2), UDim2.fromOffset(size.X, size.Y)
end

local function playVideo(video: VideoFrame)
	if not video.Visible then return end
	if video.IsLoaded then
		pcall(function() video:Play() end)
		return
	end

	video.Loaded:Once(function()
		if video.Visible and video.Parent then
			pcall(function() video:Play() end)
		end
	end)
end

local function clearPaper(paper: Paper)
	paper.Image.Visible = false
	paper.Image.ImageContent = Content.none
	paper.Tape.Visible = false
	pcall(function() paper.Tape:Pause() end)
	paper.Tape.VideoContent = Content.none
	local overlay = paper.Window:FindFirstChild("Overlay")
	if overlay then overlay:Destroy() end
end

local function paint(paper: Paper, media: CaptureGalleryService.Media)
	clearPaper(paper)
	local content = CaptureGalleryService:Content(media)
	if content and media.Kind == "Video" then
		paper.Tape.VideoContent = content
		paper.Tape.Visible = true
		paper.Tape.Looped = true
		paper.Tape.Volume = 0
		playVideo(paper.Tape)
	elseif content then
		paper.Image.ImageContent = content
		paper.Image.Visible = true
	end
	CaptureOverlayService.Apply(paper.Window, media)
end

local function sweepSheen(paper: Paper)
	paper.Sweep.Offset = Vector2.new(-1.2, 0)
	paper.Sheen.BackgroundTransparency = 0.4
	TweenService:Create(paper.Sweep, TweenInfo.new(settings.SheenTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		Offset = Vector2.new(1.2, 0),
	}):Play()
	TweenService:Create(paper.Sheen, TweenInfo.new(settings.SheenTime, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	}):Play()
end

local function hideClose(button: TextButton)
	button.BackgroundTransparency = 1
	button.TextTransparency = 1
end

local function revealClose(button: TextButton, background: number, text: number)
	TweenService:Create(button, TweenInfo.new(settings.FadeTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		BackgroundTransparency = background,
		TextTransparency = text,
	}):Play()
end

local function settle()
	if not preview.Visible or not currentMedia then return end
	TweenService:Create(preview, TweenInfo.new(settings.Fullscreen.TravelTime, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut), {
		AnchorPoint = restAnchor,
		Position = restPosition,
		Size = restSize,
		Rotation = restRotation,
	}):Play()
	sweepSheen(previewPaper)

	task.delay(settings.Fullscreen.TravelTime * 0.7, function()
		if preview.Visible then
			revealClose(previewPaper.Close, previewCloseTransparency, previewCloseTextTransparency)
		end
	end)
end

function PhotoDevelopService:Collapse()
	if not backdrop.Visible then return end
	local position, size = rectOf(preview)
	TweenService:Create(backdrop, TweenInfo.new(settings.Expanded.TravelTime, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut), {
		BackgroundTransparency = 1,
	}):Play()

	local tween = TweenService:Create(expanded, TweenInfo.new(settings.Expanded.TravelTime, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut), {
		Position = position,
		Size = size,
		Rotation = preview.Rotation,
	})
	tween.Completed:Connect(function()
		if not backdrop.Visible then return end
		backdrop.Visible = false
		preview.Visible = true
		clearPaper(expandedPaper)
		playVideo(previewPaper.Tape)
	end)
	tween:Play()
end

function PhotoDevelopService:Expand()
	if backdrop.Visible or not currentMedia or not preview.Visible then return end
	backdrop.Visible = true
	backdrop.BackgroundTransparency = 1
	TweenService:Create(backdrop, TweenInfo.new(settings.Expanded.TravelTime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		BackgroundTransparency = backdropTransparency,
	}):Play()

	local position, size = rectOf(preview)
	expanded.AnchorPoint = Vector2.new(0.5, 0.5)
	expanded.Position = position
	expanded.Size = size
	expanded.Rotation = preview.Rotation
	paint(expandedPaper, currentMedia)
	pcall(function() previewPaper.Tape:Pause() end)
	preview.Visible = false
	hideClose(expandedPaper.Close)

	TweenService:Create(expanded, TweenInfo.new(settings.Expanded.TravelTime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = expandedPosition,
		Size = expandedSize,
		Rotation = expandedRotation,
	}):Play()
	task.delay(settings.Expanded.TravelTime * 0.5, function()
		if backdrop.Visible then
			revealClose(expandedPaper.Close, expandedCloseTransparency, expandedCloseTextTransparency)
		end
	end)
end

function PhotoDevelopService:Hide()
	setDecisionOpen(false)
	actions.Visible = false
	busy = false

	if backdrop.Visible then
		backdrop.Visible = false
		clearPaper(expandedPaper)
		preview.Visible = true
	end
	if not preview.Visible then
		currentMedia = nil
		return
	end

	currentMedia = nil
	local tween = TweenService:Create(preview, TweenInfo.new(settings.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = slidePose.Position,
		Rotation = slidePose.Rotation,
	})
	tween.Completed:Connect(function()
		if currentMedia then return end
		preview.Visible = false
		clearPaper(previewPaper)
	end)
	tween:Play()
end

function PhotoDevelopService:Show(media: CaptureGalleryService.Media, fullscreen: boolean?)
	if backdrop.Visible then
		backdrop.Visible = false
		clearPaper(expandedPaper)
	end

	currentMedia = media
	busy = false
	actions.Visible = false
	paint(previewPaper, media)
	preview.Visible = true

	if fullscreen then
		preview.AnchorPoint = fullscreenPose.AnchorPoint
		preview.Position = fullscreenPose.Position
		preview.Size = fullscreenPose.Size
		preview.Rotation = fullscreenPose.Rotation
		hideClose(previewPaper.Close)
	else
		preview.AnchorPoint = slidePose.AnchorPoint
		preview.Position = slidePose.Position
		preview.Size = slidePose.Size
		preview.Rotation = slidePose.Rotation
		previewPaper.Close.BackgroundTransparency = previewCloseTransparency
		previewPaper.Close.TextTransparency = previewCloseTextTransparency
		TweenService:Create(preview, TweenInfo.new(settings.SlideTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			AnchorPoint = restAnchor,
			Position = restPosition,
			Size = restSize,
			Rotation = restRotation,
		}):Play()
		sweepSheen(previewPaper)
		return
	end

	if media.Capture and not media.Saved then
		actions.Visible = true
		setDecisionOpen(true)
		return
	end

	task.delay(settings.Fullscreen.Hold, settle)
end

previewOpen.Activated:Connect(function()
	PhotoDevelopService:Expand()
end)

previewPaper.Close.Activated:Connect(function()
	PhotoDevelopService:Hide()
end)

dismiss.Activated:Connect(function()
	PhotoDevelopService:Collapse()
end)

expandedPaper.Close.Activated:Connect(function()
	PhotoDevelopService:Collapse()
end)

save.Activated:Connect(function()
	local media = currentMedia
	if busy or not media or not actions.Visible then return end
	busy = true
	task.spawn(function()
		local ok = CaptureGalleryService:Save(media)
		NotificationService:Show(if ok then CaptureConfig.Text.Saved else CaptureConfig.Text.SaveFailed)
		busy = false
		actions.Visible = false
		setDecisionOpen(false)
		if currentMedia ~= media then return end
		if ok then settle() else PhotoDevelopService:Hide() end
	end)
end)

discard.Activated:Connect(function()
	local media = currentMedia
	if busy or not media or not actions.Visible then return end
	busy = true
	CaptureGalleryService:Discard(media)
	NotificationService:Show(CaptureConfig.Text.Discarded)
	actions.Visible = false
	setDecisionOpen(false)
	PhotoDevelopService:Hide()
end)

return PhotoDevelopService
