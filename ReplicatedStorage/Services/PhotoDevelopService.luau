local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local PhotoDevelopService = {}

if not RunService:IsClient() then
	return PhotoDevelopService
end

local PhotoConfig = require(ReplicatedStorage.Configs.PhotoConfig)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)

local screen: ScreenGui? = nil
local preview: Frame? = nil
local expanded: Frame? = nil
local currentImage: string? = nil

local function getScreen(): ScreenGui
	if screen and screen.Parent then return screen end

	screen = GuiBuilderService.CreateScreenGui("PhotoDevelop", 900, true)
	return screen :: ScreenGui
end

local function aspect(): number
	local camera = workspace.CurrentCamera
	if not camera or camera.ViewportSize.Y < 1 then return 16 / 9 end
	return camera.ViewportSize.X / camera.ViewportSize.Y
end

local function buildCloseButton(parent: Frame, shown: boolean): TextButton
	local settings = PhotoConfig.Develop.Close

	local button = Instance.new("TextButton")
	button.Name = "Close"
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -6, 0, 6)
	button.Size = settings.Size
	button.BackgroundColor3 = settings.Color
	button.BackgroundTransparency = if shown then settings.Transparency else 1
	button.AutoButtonColor = true
	button.Text = "\u{00D7}"
	button.TextColor3 = settings.TextColor
	button.TextTransparency = if shown then 0 else 1
	button.TextScaled = true
	button.Font = Enum.Font.GothamMedium
	button.ZIndex = 5
	button.Parent = parent

	GuiBuilderService.Corner(button, UDim.new(0, 4))

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 4)
	padding.Parent = button

	return button
end

local function revealCloseButton(button: TextButton)
	local settings = PhotoConfig.Develop.Close
	local info = TweenInfo.new(settings.FadeTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

	TweenService:Create(button, info, {
		BackgroundTransparency = settings.Transparency,
		TextTransparency = 0,
	}):Play()
end

local function rectOf(frame: Frame): (UDim2, UDim2)
	local position = frame.AbsolutePosition
	local size = frame.AbsoluteSize
	return UDim2.fromOffset(position.X + size.X / 2, position.Y + size.Y / 2), UDim2.fromOffset(size.X, size.Y)
end

local function buildPaper(parent: Instance, size: UDim2, position: UDim2, rotation: number): (Frame, ImageLabel, Frame, UIGradient)
	local settings = PhotoConfig.Develop

	local paper = Instance.new("Frame")
	paper.Name = "Photo"
	paper.AnchorPoint = Vector2.new(1, 1)
	paper.Position = position
	paper.Size = size
	paper.Rotation = rotation
	paper.BackgroundColor3 = settings.FrameColor
	paper.BorderSizePixel = 0
	paper.Parent = parent

	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = aspect()
	ratio.DominantAxis = Enum.DominantAxis.Width
	ratio.Parent = paper

	GuiBuilderService.Corner(paper, UDim.new(0, 4))
	GuiBuilderService.Stroke(paper, Color3.fromRGB(120, 110, 96), 1)

	local window = Instance.new("Frame")
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromScale(1 - settings.FramePadding * 2, 1 - settings.FrameThickness * 2)
	window.BackgroundColor3 = settings.BackdropColor
	window.BorderSizePixel = 0
	window.ClipsDescendants = true
	window.Parent = paper

	local image = Instance.new("ImageLabel")
	image.Name = "Capture"
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Crop
	image.ImageColor3 = settings.FinalColor
	image.ImageTransparency = 0
	image.Parent = window

	local sheen = Instance.new("Frame")
	sheen.Name = "Sheen"
	sheen.Size = UDim2.fromScale(1, 1)
	sheen.BackgroundColor3 = Color3.fromRGB(255, 244, 226)
	sheen.BackgroundTransparency = 1
	sheen.BorderSizePixel = 0
	sheen.Parent = window

	local sweep = Instance.new("UIGradient")
	sweep.Rotation = 18
	sweep.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.45, 1),
		NumberSequenceKeypoint.new(0.5, 0.55),
		NumberSequenceKeypoint.new(0.55, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	sweep.Offset = Vector2.new(-1.2, 0)
	sweep.Parent = sheen

	local vignette = Instance.new("Frame")
	vignette.Name = "Vignette"
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.BackgroundColor3 = Color3.fromRGB(12, 6, 4)
	vignette.BackgroundTransparency = settings.VignetteTransparency
	vignette.BorderSizePixel = 0
	vignette.Parent = window

	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(1, 0.25),
	})
	shade.Parent = vignette

	return paper, image, sheen, sweep
end

local function sweepSheen(sheen: Frame, sweep: UIGradient)
	local settings = PhotoConfig.Develop

	sheen.BackgroundTransparency = 0.4
	TweenService:Create(sweep, TweenInfo.new(settings.SheenTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		Offset = Vector2.new(1.2, 0),
	}):Play()
	TweenService:Create(sheen, TweenInfo.new(settings.SheenTime, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	}):Play()
end

function PhotoDevelopService:Collapse()
	local backdrop = expanded
	if not backdrop then return end

	expanded = nil
	local settings = PhotoConfig.Develop.Expanded
	local info = TweenInfo.new(settings.TravelTime, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
	local paper = backdrop:FindFirstChild("Photo") :: Frame?
	local source = preview

	TweenService:Create(backdrop, info, { BackgroundTransparency = 1 }):Play()

	if paper and source and source.Parent then
		local position, size = rectOf(source)
		local tween = TweenService:Create(paper, info, {
			Position = position,
			Size = size,
			Rotation = source.Rotation,
		})
		tween.Completed:Connect(function()
			if source.Parent then
				source.Visible = true
			end
			backdrop:Destroy()
		end)
		tween:Play()
		return
	end

	task.delay(settings.TravelTime, function()
		backdrop:Destroy()
	end)
end

function PhotoDevelopService:Expand()
	local source = preview
	if expanded or not currentImage or not source then return end

	local settings = PhotoConfig.Develop.Expanded

	local backdrop = Instance.new("Frame")
	backdrop.Name = "PhotoExpanded"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = settings.BackdropColor
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.ZIndex = 3
	backdrop.Parent = getScreen()
	expanded = backdrop

	local info = TweenInfo.new(settings.TravelTime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	TweenService:Create(backdrop, info, { BackgroundTransparency = settings.BackdropTransparency }):Play()

	local dismiss = Instance.new("TextButton")
	dismiss.Name = "Dismiss"
	dismiss.Size = UDim2.fromScale(1, 1)
	dismiss.BackgroundTransparency = 1
	dismiss.Text = ""
	dismiss.ZIndex = 3
	dismiss.Parent = backdrop
	dismiss.Activated:Connect(function()
		self:Collapse()
	end)

	local startPosition, startSize = rectOf(source)
	local paper, image = buildPaper(backdrop, startSize, startPosition, source.Rotation)
	paper.AnchorPoint = Vector2.new(0.5, 0.5)
	paper.ZIndex = 4
	image.Image = currentImage
	source.Visible = false

	TweenService:Create(paper, info, {
		Position = UDim2.fromScale(0.5, 0.5),
		Size = settings.Size,
		Rotation = settings.Rotation,
	}):Play()

	local close = buildCloseButton(paper, false)
	close.Activated:Connect(function()
		self:Collapse()
	end)
	task.delay(settings.TravelTime * 0.5, function()
		if expanded == backdrop then
			revealCloseButton(close)
		end
	end)
end

function PhotoDevelopService:Hide()
	self:Collapse()

	local paper = preview
	if not paper then return end

	preview = nil
	currentImage = nil

	local settings = PhotoConfig.Develop
	local tween = TweenService:Create(paper, TweenInfo.new(settings.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = settings.SlideFrom,
		Rotation = settings.Rotation * 3,
	})
	tween.Completed:Connect(function()
		paper:Destroy()
	end)
	tween:Play()
end

function PhotoDevelopService:Show(contentId: string, fullscreen: boolean?)
	local settings = PhotoConfig.Develop

	local previous = expanded
	expanded = nil
	if previous then
		previous:Destroy()
	end
	if preview then
		preview:Destroy()
		preview = nil
	end

	currentImage = contentId

	local big = settings.Fullscreen
	local startSize = if fullscreen then big.Size else settings.Size
	local startPosition = if fullscreen then UDim2.fromScale(0.5, 0.5) else settings.SlideFrom
	local startRotation = if fullscreen then 0 else settings.Rotation

	local paper, image, sheen, sweep = buildPaper(getScreen(), startSize, startPosition, startRotation)
	if fullscreen then
		paper.AnchorPoint = Vector2.new(0.5, 0.5)
	end
	image.Image = contentId
	preview = paper

	local open = Instance.new("TextButton")
	open.Name = "Open"
	open.Size = UDim2.fromScale(1, 1)
	open.BackgroundTransparency = 1
	open.Text = ""
	open.ZIndex = 2
	open.Parent = paper
	open.Activated:Connect(function()
		if preview == paper then
			self:Expand()
		end
	end)

	local close = buildCloseButton(paper, not fullscreen)
	close.Activated:Connect(function()
		if preview == paper then
			self:Hide()
		end
	end)

	if not fullscreen then
		TweenService:Create(paper, TweenInfo.new(settings.SlideTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = settings.Position,
		}):Play()
		sweepSheen(sheen, sweep)
		return
	end

	task.delay(big.Hold, function()
		if preview ~= paper then return end

		TweenService:Create(paper, TweenInfo.new(big.TravelTime, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut), {
			AnchorPoint = Vector2.new(1, 1),
			Position = settings.Position,
			Size = settings.Size,
			Rotation = settings.Rotation,
		}):Play()
		sweepSheen(sheen, sweep)

		task.delay(big.TravelTime * 0.7, function()
			if preview == paper then
				revealCloseButton(close)
			end
		end)
	end)
end

return PhotoDevelopService
