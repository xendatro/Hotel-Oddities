local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CaptureOverlayService = {}

if not RunService:IsClient() then
	return CaptureOverlayService
end

local CaptureConfig = require(ReplicatedStorage.Configs.CaptureConfig)

local OVERLAY = CaptureConfig.Overlay
local blinkVersions: { [Frame]: number } = setmetatable({}, { __mode = "k" })

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

local function blink(overlay: Frame): () -> ()
	local mark = overlay:FindFirstChild("Mark")
	local dot = mark and mark:FindFirstChild("Dot")
	if not dot or not dot:IsA("TextLabel") then return function() end end

	local version = (blinkVersions[overlay] or 0) + 1
	blinkVersions[overlay] = version
	task.spawn(function()
		while blinkVersions[overlay] == version and dot.Parent do
			dot.TextTransparency = if dot.TextTransparency > 0.5 then OVERLAY.Transparency else 1
			task.wait(OVERLAY.BlinkTime)
		end
	end)

	return function()
		if blinkVersions[overlay] ~= version then return end
		blinkVersions[overlay] = version + 1
		dot.TextTransparency = OVERLAY.Transparency
	end
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
		local mark = Instance.new("Frame")
		mark.Name = "Mark"
		mark.Position = UDim2.fromScale(pad, pad)
		mark.Size = UDim2.fromScale(0.22, OVERLAY.TextScale)
		mark.BackgroundTransparency = 1
		mark.ZIndex = 6
		mark.Parent = overlay

		local dot = label(mark, "Dot", Vector2.new(0, 0), UDim2.fromScale(0, 0))
		dot.Size = UDim2.fromScale(0.24, 1)
		dot.Text = "\u{25CF}"
		dot.TextColor3 = OVERLAY.RecordColor
		dot.TextXAlignment = Enum.TextXAlignment.Left

		local text = label(mark, "Text", Vector2.new(0, 0), UDim2.fromScale(0.25, 0))
		text.Size = UDim2.fromScale(0.75, 1)
		text.Text = OVERLAY.RecordText
		text.TextColor3 = OVERLAY.RecordColor
		text.TextXAlignment = Enum.TextXAlignment.Left

		blink(overlay)
	end

	return overlay
end

function CaptureOverlayService.Blink(overlay: Frame): () -> ()
	return blink(overlay)
end

return CaptureOverlayService
