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
local random = Random.new()

local function build()
	if screenGui and screenGui.Parent and container and container.Parent then return end

	screenGui = GuiBuilderService.CreateScreenGui("NotificationGui", Config.DisplayOrder)
	container = Instance.new("Frame")
	container.Name = "Container"
	container.BackgroundTransparency = 1
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.Position = UDim2.new(0.5, 0, 0, Config.TopMargin)
	container.Size = UDim2.fromOffset(Config.Width, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Config.Gap)
	layout.Parent = container
end

local function createPaper(name: string, parent: GuiObject, tint: Color3): ImageLabel
	local paper = Instance.new("ImageLabel")
	paper.Name = name
	paper.BackgroundTransparency = 1
	paper.Image = Config.Paper
	paper.ImageColor3 = tint
	paper.ImageTransparency = 1
	paper.ScaleType = Enum.ScaleType.Stretch
	paper.Size = UDim2.fromScale(1, 1)
	paper.Parent = parent
	return paper
end

local function show(message: any)
	if type(message) ~= "string" or message == "" then return end

	build()
	nextOrder += 1

	local slot = Instance.new("Frame")
	slot.Name = "Notification"
	slot.BackgroundTransparency = 1
	slot.Size = UDim2.fromOffset(Config.Width, Config.Height)
	slot.LayoutOrder = nextOrder
	slot.Rotation = if random:NextInteger(0, 1) == 0 then -Config.Tilt else Config.Tilt
	slot.Parent = container

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.BackgroundTransparency = 1
	card.Size = UDim2.fromScale(1, 1)
	card.Position = UDim2.fromOffset(0, -Config.EnterDrop)
	card.Rotation = if slot.Rotation < 0 then -Config.EnterTilt else Config.EnterTilt
	card.Parent = slot

	local scale = Instance.new("UIScale")
	scale.Scale = Config.EnterScale
	scale.Parent = card

	local shadow = createPaper("Shadow", card, Config.ShadowTint)
	shadow.Size = UDim2.new(1, Config.ShadowGrow, 1, Config.ShadowGrow)
	shadow.Position = UDim2.fromOffset(Config.ShadowOffset.X - Config.ShadowGrow / 2, Config.ShadowOffset.Y - Config.ShadowGrow / 2)

	local paper = createPaper("Paper", card, Config.PaperTint)

	local label = Instance.new("TextLabel")
	label.Name = "Message"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.new(1, -Config.SidePadding * 2, 1, -Config.TopPadding * 2)
	label.Font = Config.Font
	label.Text = message
	label.TextColor3 = Config.TextColor
	label.TextScaled = true
	label.TextTransparency = 1
	label.TextWrapped = true
	label.Parent = card

	local sizeLimit = Instance.new("UITextSizeConstraint")
	sizeLimit.MaxTextSize = Config.TextSize
	sizeLimit.MinTextSize = Config.MinTextSize
	sizeLimit.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Color = Config.StrokeColor
	stroke.Thickness = Config.StrokeThickness
	stroke.Transparency = 1
	stroke.Parent = label

	local settle = TweenInfo.new(Config.InTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local fade = TweenInfo.new(Config.InTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(card, settle, { Position = UDim2.fromOffset(0, 0), Rotation = 0 }):Play()
	TweenService:Create(scale, settle, { Scale = 1 }):Play()
	TweenService:Create(paper, fade, { ImageTransparency = 0 }):Play()
	TweenService:Create(shadow, fade, { ImageTransparency = Config.ShadowTransparency }):Play()
	TweenService:Create(label, fade, { TextTransparency = 0 }):Play()
	TweenService:Create(stroke, fade, { Transparency = 0 }):Play()

	task.delay(Config.Duration, function()
		if not card.Parent then return end

		local out = TweenInfo.new(Config.OutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(card, out, { Position = UDim2.fromOffset(0, -Config.ExitRise) }):Play()
		TweenService:Create(paper, out, { ImageTransparency = 1 }):Play()
		TweenService:Create(shadow, out, { ImageTransparency = 1 }):Play()
		TweenService:Create(label, out, { TextTransparency = 1 }):Play()

		local last = TweenService:Create(stroke, out, { Transparency = 1 })
		last.Completed:Once(function()
			if slot.Parent then slot:Destroy() end
		end)
		last:Play()
	end)
end

function NotificationService:Show(message: string)
	show(message)
end

ShowRemote.OnClientEvent:Connect(show)

return NotificationService
