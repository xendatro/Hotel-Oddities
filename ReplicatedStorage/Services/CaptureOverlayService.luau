local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CaptureOverlayService = {}

if not RunService:IsClient() then
	return CaptureOverlayService
end

local CaptureConfig = require(ReplicatedStorage.Configs.CaptureConfig)

local OVERLAY = CaptureConfig.Overlay
local blinkVersions: { [Frame]: number } = setmetatable({}, { __mode = "k" })
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local templates = playerGui:WaitForChild("CaptureTemplates", 20)
local overlayTemplate = templates and templates:WaitForChild("Overlay", 10) :: Frame?

if not overlayTemplate then
	warn("CaptureOverlayService: CaptureTemplates.Overlay did not replicate")
	return CaptureOverlayService
end

local function formatStamp(time: DateTime): (string, string)
	local okDate, date = pcall(function()
		return time:FormatLocalTime(OVERLAY.DateFormat, "en-us")
	end)
	local okClock, clock = pcall(function()
		return time:FormatLocalTime(OVERLAY.TimeFormat, "en-us")
	end)

	return (okDate and date or ""), (okClock and clock or "")
end

local function blink(overlay: Frame): () -> ()
	local mark = overlay:FindFirstChild("Mark")
	local dot = mark and mark:FindFirstChild("Dot")
	if not dot or not dot:IsA("TextLabel") then return function() end end
	local visibleTransparency = dot:GetAttribute("VisibleTransparency")
	if type(visibleTransparency) ~= "number" then
		visibleTransparency = dot.TextTransparency
	end

	local version = (blinkVersions[overlay] or 0) + 1
	blinkVersions[overlay] = version
	task.spawn(function()
		while blinkVersions[overlay] == version and dot.Parent do
			dot.TextTransparency = if dot.TextTransparency > 0.5 then visibleTransparency else 1
			task.wait(OVERLAY.BlinkTime)
		end
	end)

	return function()
		if blinkVersions[overlay] ~= version then return end
		blinkVersions[overlay] = version + 1
		dot.TextTransparency = visibleTransparency
	end
end

function CaptureOverlayService.Apply(parent: GuiObject, media: any): Frame
	local existing = parent:FindFirstChild("Overlay")
	if existing then
		existing:Destroy()
	end

	local overlay = overlayTemplate:Clone()
	overlay.Visible = true
	overlay.Parent = parent

	local date, clock = formatStamp(media.Time)
	local stamp = overlay:FindFirstChild("Stamp") :: TextLabel
	stamp.Text = `{date}  {clock}`
	local mark = overlay:FindFirstChild("Mark") :: Frame
	mark.Visible = media.Kind == "Video"
	if mark.Visible then
		blink(overlay)
	end

	return overlay
end

function CaptureOverlayService.Blink(overlay: Frame): () -> ()
	return blink(overlay)
end

return CaptureOverlayService
