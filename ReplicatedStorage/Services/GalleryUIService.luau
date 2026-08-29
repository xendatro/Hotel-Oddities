local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GalleryUIService = {}

if not RunService:IsClient() then
	return GalleryUIService
end

local GalleryCard = require(ReplicatedStorage.Classes.GalleryCard)
local CaptureConfig = require(ReplicatedStorage.Configs.CaptureConfig)
local CaptureGalleryService = require(ReplicatedStorage.Services.CaptureGalleryService)
local CaptureOverlayService = require(ReplicatedStorage.Services.CaptureOverlayService)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
local InterfaceService = require(ReplicatedStorage.Services.InterfaceService)
local NotificationService = require(ReplicatedStorage.Services.NotificationService)

local GALLERY = CaptureConfig.Gallery
local STAGGER = 0.03

local playerGui = GuiBuilderService.GetPlayerGui()
local gui = playerGui:WaitForChild(GALLERY.GuiName, 20) :: ScreenGui?
if not gui then
	warn(`GalleryUIService: {GALLERY.GuiName} did not replicate`)
	return GalleryUIService
end

local design = gui:WaitForChild(GALLERY.Root, 10) :: Frame?
local canvas = design and design:WaitForChild("MediaCanvas", 10)
local mediaFrame = canvas and canvas:WaitForChild("Media", 10) :: ScrollingFrame?
local template = mediaFrame and mediaFrame:WaitForChild("Template", 10) :: ImageButton?
local info = design and design:WaitForChild("Info", 10) :: Frame?

if not (design and mediaFrame and template and info) then
	warn("GalleryUIService: GalleryGui is missing its expected children")
	return GalleryUIService
end

local preview = info:WaitForChild("Preview", 10) :: Frame
local still = preview:WaitForChild("Still", 10) :: ImageLabel
local tape = preview:WaitForChild("Tape", 10) :: VideoFrame
local empty = design:FindFirstChild("Empty") :: TextLabel?
local actions = info:FindFirstChild("Actions") :: Frame?
local stamp = info:FindFirstChild("Stamp") :: TextLabel?

template.Visible = false

local cards: { [string]: any } = {}
local selectedId: string? = nil
local refreshing = false

local function clearPreview()
	preview.Visible = false
	still.Visible = false
	still.ImageContent = Content.none
	tape.Visible = false
	pcall(function() tape:Pause() end)
	tape.VideoContent = Content.none

	local overlay = preview:FindFirstChild("Overlay")
	if overlay then overlay:Destroy() end
end

local function paintActions(media: any?)
	if not actions then return end

	actions.Visible = media ~= nil and media.Capture ~= nil and not media.Saved

	local save = actions:FindFirstChild("Save") :: TextButton?
	local discard = actions:FindFirstChild("Discard") :: TextButton?
	if save then save.Text = CaptureConfig.Prompt.SaveText end
	if discard then discard.Text = CaptureConfig.Prompt.DiscardText end
end

local function paintPreview()
	clearPreview()

	local media = nil
	for _, entry in CaptureGalleryService:List() do
		if entry.Id == selectedId then
			media = entry
			break
		end
	end

	paintActions(media)

	if not media then
		if stamp then stamp.Text = "" end
		return
	end

	if stamp then
		local ok, formatted = pcall(function()
			return media.Time:FormatLocalTime(
				`{CaptureConfig.Overlay.DateFormat}  {CaptureConfig.Overlay.TimeFormat}`,
				"en-us"
			)
		end)
		stamp.Text = if ok then formatted else ""
	end

	local content = CaptureGalleryService:Content(media)
	if not content then return end

	preview.Visible = true

	if media.Kind == "Video" then
		tape.VideoContent = content
		tape.Visible = true
		tape.Looped = true
		pcall(function() tape:Play() end)
	else
		still.ImageContent = content
		still.Visible = true
	end

	CaptureOverlayService.Apply(preview, media)
end

local function select(media: any)
	if media.Id == selectedId then return end

	local previous = cards[selectedId or ""]
	if previous then previous:SetSelected(false) end

	selectedId = media.Id

	local card = cards[media.Id]
	if card then card:SetSelected(true) end

	paintPreview()
end

local function rebuild()
	for _, card in cards do
		card:Destroy()
	end
	cards = {}

	local items = CaptureGalleryService:List()

	for order, media in items do
		cards[media.Id] = GalleryCard.new(template :: ImageButton, mediaFrame, media, order, select)
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

	if refreshing then return end
	refreshing = true

	task.spawn(function()
		local ok = CaptureGalleryService:Refresh(false)
		refreshing = false
		if not ok and not CaptureGalleryService:HasPermission() then
			NotificationService:Show(CaptureConfig.Text.Denied)
		end
		if not gui.Enabled then return end
		rebuild()
		deal()
	end)
end

if actions then
	local save = actions:FindFirstChild("Save") :: TextButton?
	local discard = actions:FindFirstChild("Discard") :: TextButton?

	if save then
		InterfaceService.WireMotion(save)
		save.Activated:Connect(function()
			local id = selectedId
			if not id then return end

			task.spawn(function()
				for _, media in CaptureGalleryService:List() do
					if media.Id ~= id then continue end
					local ok = CaptureGalleryService:Save(media)
					NotificationService:Show(
						if ok then CaptureConfig.Text.Saved else CaptureConfig.Text.SaveFailed
					)
					break
				end
			end)
		end)
	end

	if discard then
		InterfaceService.WireMotion(discard)
		discard.Activated:Connect(function()
			local id = selectedId
			if not id then return end

			for _, media in CaptureGalleryService:List() do
				if media.Id ~= id then continue end
				CaptureGalleryService:Discard(media)
				NotificationService:Show(CaptureConfig.Text.Discarded)
				break
			end
			selectedId = nil
		end)
	end
end

CaptureGalleryService.Changed.Event:Connect(function()
	if not gui.Enabled then return end
	rebuild()
end)

gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if gui.Enabled then
		refresh()
	else
		clearPreview()
	end
end)

rebuild()

return GalleryUIService
