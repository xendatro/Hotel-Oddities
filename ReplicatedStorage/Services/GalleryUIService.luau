local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local GalleryUIService = {}

if not RunService:IsClient() then
	return GalleryUIService
end

local GalleryCard = require(ReplicatedStorage.Classes.GalleryCard)
local CaptureConfig = require(ReplicatedStorage.Configs.CaptureConfig)
local CaptureGalleryService = require(ReplicatedStorage.Services.CaptureGalleryService)
local CaptureOverlayService = require(ReplicatedStorage.Services.CaptureOverlayService)
local InterfaceService = require(ReplicatedStorage.Services.InterfaceService)
local NotificationService = require(ReplicatedStorage.Services.NotificationService)

local GALLERY = CaptureConfig.Gallery
local STAGGER = 0.03

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild(GALLERY.GuiName, 20) :: ScreenGui?
if not gui then
	warn(`GalleryUIService: {GALLERY.GuiName} did not replicate`)
	return GalleryUIService
end

local design = gui:WaitForChild(GALLERY.Root, 10) :: Frame?
local canvas = design and design:WaitForChild("MediaCanvas", 10)
local mediaFrame = canvas and canvas:WaitForChild("Media", 10) :: ScrollingFrame?
local template = mediaFrame and mediaFrame:WaitForChild("Template", 10) :: Frame?
local info = design and design:WaitForChild("Info", 10) :: Frame?
local fullscreen = gui:WaitForChild("Fullscreen", 10) :: Frame?

if not (design and mediaFrame and template and info and fullscreen) then
	warn("GalleryUIService: GalleryGui is missing its expected children")
	return GalleryUIService
end

local preview = info:WaitForChild("Preview", 10) :: Frame
local still = preview:WaitForChild("Still", 10) :: ImageLabel
local tape = preview:WaitForChild("Tape", 10) :: VideoFrame
local previewOpen = preview:WaitForChild("Open", 10) :: ImageButton
local empty = design:FindFirstChild("Empty") :: TextLabel?
local actions = info:WaitForChild("Actions", 10) :: Frame
local save = actions:WaitForChild("Save", 10) :: TextButton
local discard = actions:WaitForChild("Discard", 10) :: TextButton
local access = actions:WaitForChild("Access", 10) :: TextButton
local deleteButton = actions:WaitForChild("Delete", 10) :: TextButton
local fullWindow = fullscreen:WaitForChild("Window", 10) :: Frame
local fullStill = fullWindow:WaitForChild("Still", 10) :: ImageLabel
local fullTape = fullWindow:WaitForChild("Tape", 10) :: VideoFrame
local fullClose = fullWindow:WaitForChild("Close", 10) :: TextButton
local fullDismiss = fullscreen:WaitForChild("Dismiss", 10) :: TextButton

template.Visible = false
fullscreen.Visible = false

local cards: { [string]: any } = {}
local selectedId: string? = nil
local refreshing = false

local function selectedMedia(): any?
	for _, media in CaptureGalleryService:List() do
		if media.Id == selectedId then return media end
	end
	return nil
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

local function clearMedia(parent: GuiObject, image: ImageLabel, video: VideoFrame)
	image.Visible = false
	image.ImageContent = Content.none
	video.Visible = false
	pcall(function() video:Pause() end)
	video.VideoContent = Content.none

	local overlay = parent:FindFirstChild("Overlay")
	if overlay then overlay:Destroy() end
end

local function clearPreview()
	preview.Visible = false
	clearMedia(preview, still, tape)
end

local function closeFullscreen()
	fullscreen.Visible = false
	clearMedia(fullWindow, fullStill, fullTape)
end

local function paintActions(media: any?)
	local hasDecision = media ~= nil and media.Capture ~= nil and not media.Saved
	local needsAccess = not CaptureGalleryService:HasPermission() and not hasDecision
	local canDelete = media ~= nil and media.Saved
	actions.Visible = hasDecision or needsAccess or canDelete

	save.Text = CaptureConfig.Prompt.SaveText
	save.Visible = hasDecision
	discard.Text = CaptureConfig.Prompt.DiscardText
	discard.Visible = hasDecision
	access.Visible = needsAccess
	deleteButton.Visible = canDelete
end

local function paintMedia(parent: GuiObject, image: ImageLabel, video: VideoFrame, media: any): boolean
	clearMedia(parent, image, video)
	local content = CaptureGalleryService:Content(media)
	if not content then return false end

	if media.Kind == "Video" then
		video.VideoContent = content
		video.Visible = true
		video.Looped = true
		video.Volume = 0
		playVideo(video)
	else
		image.ImageContent = content
		image.Visible = true
	end

	CaptureOverlayService.Apply(parent, media)
	return true
end

local function paintPreview()
	clearPreview()
	local media = selectedMedia()
	paintActions(media)
	if not media then return end
	if paintMedia(preview, still, tape, media) then
		preview.Visible = true
	end
end

local function openFullscreen()
	local media = selectedMedia()
	if not media then return end
	if not paintMedia(fullWindow, fullStill, fullTape, media) then return end
	fullscreen.Visible = true
end

local function select(media: any)
	if media.Id == selectedId then return end

	local previous = cards[selectedId or ""]
	if previous then previous:SetSelected(false) end

	selectedId = media.Id
	local card = cards[media.Id]
	if card then card:SetSelected(true) end
	closeFullscreen()
	paintPreview()
end

local function rebuild()
	for _, card in cards do
		card:Destroy()
	end
	cards = {}

	local items = CaptureGalleryService:List()
	for order, media in items do
		cards[media.Id] = GalleryCard.new(template :: Frame, mediaFrame, media, order, select)
	end

	if not selectedId or not cards[selectedId] then
		selectedId = items[1] and items[1].Id
	end

	local selected = cards[selectedId or ""]
	if selected then selected:SetSelected(true) end

	if empty then
		empty.Visible = #items == 0
		empty.Text = if CaptureGalleryService:HasPermission()
			then GALLERY.EmptyText or CaptureConfig.Text.NoCaptures
			else CaptureConfig.Text.NeedPermission
	end

	paintPreview()
end

local function deal()
	local order = 0
	for _, card in cards do
		order += 1
		card:Deal((order - 1) * STAGGER)
	end
end

local function refresh()
	rebuild()
	deal()
	if refreshing or not CaptureGalleryService:HasPermission() then return end
	refreshing = true

	task.spawn(function()
		CaptureGalleryService:Refresh(false)
		refreshing = false
		if not gui.Enabled then return end
		rebuild()
		deal()
	end)
end

InterfaceService.WireMotion(access)
access.Activated:Connect(function()
	if refreshing then return end
	refreshing = true
	access.Interactable = false
	access.Text = CaptureConfig.Text.Accessing

	task.spawn(function()
		local granted = CaptureGalleryService:RequestPermission()
		if granted then
			CaptureGalleryService:Refresh(true)
		else
			NotificationService:Show(CaptureConfig.Text.Denied)
		end

		refreshing = false
		access.Interactable = true
		access.Text = CaptureConfig.Text.Access
		if not gui.Enabled then return end
		rebuild()
		deal()
	end)
end)

InterfaceService.WireMotion(save)
save.Activated:Connect(function()
	local media = selectedMedia()
	if not media then return end

	task.spawn(function()
		local ok = CaptureGalleryService:Save(media)
		NotificationService:Show(if ok then CaptureConfig.Text.Saved else CaptureConfig.Text.SaveFailed)
	end)
end)

InterfaceService.WireMotion(discard)
discard.Activated:Connect(function()
	local media = selectedMedia()
	if not media then return end
	selectedId = nil
	CaptureGalleryService:Discard(media)
	NotificationService:Show(CaptureConfig.Text.Discarded)
end)

InterfaceService.WireMotion(deleteButton)
deleteButton.Activated:Connect(function()
	local media = selectedMedia()
	if not media then return end
	selectedId = nil
	closeFullscreen()
	CaptureGalleryService:Delete(media)
	NotificationService:Show(CaptureConfig.Text.Deleted)
end)

previewOpen.Activated:Connect(openFullscreen)
fullClose.Activated:Connect(closeFullscreen)
fullDismiss.Activated:Connect(closeFullscreen)

CaptureGalleryService.Changed.Event:Connect(function()
	if not gui.Enabled then return end
	rebuild()
end)

gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if gui.Enabled then
		refresh()
	else
		closeFullscreen()
		clearPreview()
	end
end)

rebuild()

return GalleryUIService
