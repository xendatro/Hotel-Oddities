local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Configs.NotificationConfig)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)

local NotificationService = {}

if not RunService:IsClient() then
	return NotificationService
end

local ShowRemote = CommunicationService.Get("Notifications", "Show")
local screenGui: ScreenGui? = nil
local container: Frame? = nil
local nextOrder = 0

local function build()
	if screenGui and screenGui.Parent and container and container.Parent then return end

	screenGui = GuiBuilderService.CreateScreenGui("NotificationGui", Config.DisplayOrder)
	container = Instance.new("Frame")
	container.Name = "Container"
	container.BackgroundTransparency = 1
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.Position = UDim2.fromOffset(0, Config.TopMargin)
	container.Size = UDim2.fromOffset(Config.Width, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Config.Gap)
	layout.Parent = container

	container.Position = UDim2.new(0.5, 0, 0, Config.TopMargin)
end

local function fadeIn(frame: Frame, label: TextLabel, accent: Frame, stroke: UIStroke)
	local info = TweenInfo.new(Config.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(frame, info, { BackgroundTransparency = Config.BackgroundTransparency }):Play()
	TweenService:Create(label, info, { TextTransparency = 0, TextStrokeTransparency = 0.5 }):Play()
	TweenService:Create(accent, info, { BackgroundTransparency = 0 }):Play()
	TweenService:Create(stroke, info, { Transparency = 0 }):Play()
end

local function fadeOut(frame: Frame, label: TextLabel, accent: Frame, stroke: UIStroke)
	local info = TweenInfo.new(Config.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(frame, info, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	TweenService:Create(accent, info, { BackgroundTransparency = 1 }):Play()
	local tween = TweenService:Create(stroke, info, { Transparency = 1 })
	tween.Completed:Once(function()
		if frame.Parent then frame:Destroy() end
	end)
	tween:Play()
end

local function show(message: any)
	if type(message) ~= "string" or message == "" then return end

	build()
	nextOrder += 1

	local frame = Instance.new("Frame")
	frame.Name = "Notification"
	frame.Size = UDim2.fromOffset(Config.Width, Config.Height)
	frame.BackgroundColor3 = Config.BackgroundColor
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = nextOrder
	frame.Parent = container

	local stroke = GuiBuilderService.Stroke(frame, Config.StrokeColor, 1)
	stroke.Transparency = 1
	GuiBuilderService.Corner(frame, UDim.new(0, 8))

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Size = UDim2.new(0, 4, 1, 0)
	accent.BackgroundColor3 = Config.AccentColor
	accent.BackgroundTransparency = 1
	accent.BorderSizePixel = 0
	accent.Parent = frame
	GuiBuilderService.Corner(accent, UDim.new(0, 8))

	local label = Instance.new("TextLabel")
	label.Name = "Message"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(20, 0)
	label.Size = UDim2.new(1, -36, 1, 0)
	label.Font = Enum.Font.GothamMedium
	label.Text = message
	label.TextColor3 = Config.TextColor
	label.TextSize = Config.TextSize
	label.TextStrokeColor3 = Config.TextStrokeColor
	label.TextStrokeTransparency = 1
	label.TextTransparency = 1
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = frame

	fadeIn(frame, label, accent, stroke)
	task.delay(Config.Duration, function()
		if frame.Parent then
			fadeOut(frame, label, accent, stroke)
		end
	end)
end

function NotificationService:Show(message: string)
	show(message)
end

ShowRemote.OnClientEvent:Connect(show)

return NotificationService
