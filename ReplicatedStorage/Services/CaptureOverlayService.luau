local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CaptureOverlayService = {}

if not RunService:IsClient() then
	return CaptureOverlayService
end

local CaptureConfig = require(ReplicatedStorage.Configs.CaptureConfig)

local OVERLAY = CaptureConfig.Overlay

local function label(parent: GuiObject, name: string, anchor: Vector2, position: UDim2): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.AnchorPoint = anchor
	text.Position = position
	text.Size = UDim2.fromScale(1 - OVERLAY.Padding * 2, OVERLAY.TextScale)
	text.BackgroundTransparency = 1
	text.Font = OVERLAY.Font
	text.TextColor3 = OVERLAY.Color
	text.TextTransparency = OVERLAY.Transparency
	text.TextScaled = true
	text.Text = ""
	text.ZIndex = 6
	text.Parent = parent

	if anchor.X < 0.5 then
		text.TextXAlignment = Enum.TextXAlignment.Left
	elseif anchor.X > 0.5 then
		text.TextXAlignment = Enum.TextXAlignment.Right
	end

	local stroke = Instance.new("UIStroke")
	stroke.Color = OVERLAY.StrokeColor
	stroke.Thickness = OVERLAY.StrokeThickness
	stroke.Transparency = 0.25
	stroke.Parent = text

	return text
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

function CaptureOverlayService.Apply(parent: GuiObject, media: any): Frame
	local existing = parent:FindFirstChild("Overlay")
	if existing then
		existing:Destroy()
	end

	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundTransparency = 1
	overlay.ZIndex = 6
	overlay.Parent = parent

	local pad = OVERLAY.Padding
	local date, clock = formatStamp(media.Time)

	local stamp = label(overlay, "Stamp", Vector2.new(1, 1), UDim2.fromScale(1 - pad, 1 - pad))
	stamp.Text = `{date}  {clock}`

	if media.Kind == "Video" then
		local mark = label(overlay, "Mark", Vector2.new(0, 0), UDim2.fromScale(pad, pad))
		mark.Text = `\u{25CF} {OVERLAY.RecordText}`
		mark.TextColor3 = OVERLAY.RecordColor
	end

	return overlay
end

function CaptureOverlayService.Blink(overlay: Frame): () -> ()
	local mark = overlay:FindFirstChild("Mark")
	if not mark or not mark:IsA("TextLabel") then return function() end end

	local running = true
	task.spawn(function()
		while running and mark.Parent do
			mark.TextTransparency = if mark.TextTransparency > 0.5 then OVERLAY.Transparency else 1
			task.wait(OVERLAY.BlinkTime)
		end
	end)

	return function()
		running = false
	end
end

return CaptureOverlayService
