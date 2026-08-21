local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DeathConfig = require(ReplicatedStorage.Configs.DeathConfig)

local DeathScreenService = {}

if not RunService:IsClient() then
	return DeathScreenService
end

local Show = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Death")
	:WaitForChild("Show") :: RemoteEvent
local Complete = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Death")
	:WaitForChild("Complete") :: RemoteEvent

local SCREEN = DeathConfig.Screen
local COLORS = SCREEN.Colors

local RENDER_JOB = "DeathScreen"
local ENTRANCE_TIME = 0.5
local ENTRANCE_RISE = 10
local JITTER_INTERVAL = 0.05
local CURSOR = "_"

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local ScreenGui, Backdrop, Content, Eyebrow, NameHolder, Rule, Hint, Sweep, Scanlines, SliceHolder
local NameMain, NameRed, NameCyan
local VignetteEdges: { Frame } = {}
local Slices: { Frame } = {}
local Blur: BlurEffect?, Correction: ColorCorrectionEffect?

local HintText = ""
local Visible = false
local ShownAt = 0
local DeathToken = 0
local HidingAt = nil :: number?
local BurstUntil = 0
local NextBurstAt = 0
local NextJitterAt = 0
local SplitX, SplitY = 0, 0
local ContentShift = 0
local TypedCount = -1
local CursorShown = false

local function randomRange(minimum: number, maximum: number): number
	return minimum + math.random() * (maximum - minimum)
end

local function entrance(elapsed: number, delay: number): number
	local progress = math.clamp((elapsed - delay) / ENTRANCE_TIME, 0, 1)
	return progress * progress * (3 - 2 * progress)
end

local function newFrame(name: string, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

local function newLabel(name: string, parent: Instance, font: Enum.Font, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = size
	label.TextColor3 = color
	label.TextTransparency = 1
	label.Parent = parent
	return label
end

local function buildVignetteEdge(name: string, size: UDim2, anchor: Vector2, rotation: number)
	local edge = newFrame(name, ScreenGui)
	edge.BackgroundColor3 = COLORS.Backdrop
	edge.Size = size
	edge.AnchorPoint = anchor
	edge.Position = UDim2.fromScale(anchor.X, anchor.Y)
	edge.ZIndex = 2

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.35, 0.55),
		NumberSequenceKeypoint.new(0.7, 0.9),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = edge

	table.insert(VignetteEdges, edge)
end

local function build()
	ScreenGui = Instance.new("ScreenGui")
	ScreenGui.Name = "DeathGui"
	ScreenGui.ResetOnSpawn = false
	ScreenGui.IgnoreGuiInset = true
	ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	ScreenGui.DisplayOrder = SCREEN.DisplayOrder
	ScreenGui.Enabled = false
	ScreenGui.Parent = PlayerGui

	Backdrop = newFrame("Backdrop", ScreenGui)
	Backdrop.BackgroundColor3 = COLORS.Backdrop
	Backdrop.BackgroundTransparency = 0
	Backdrop.Size = UDim2.fromScale(1, 1)
	Backdrop.ZIndex = 1

	buildVignetteEdge("VignetteTop", UDim2.fromScale(1, SCREEN.VignetteSize), Vector2.new(0, 0), 90)
	buildVignetteEdge("VignetteBottom", UDim2.fromScale(1, SCREEN.VignetteSize), Vector2.new(0, 1), 270)
	buildVignetteEdge("VignetteLeft", UDim2.fromScale(SCREEN.VignetteSize, 1), Vector2.new(0, 0), 0)
	buildVignetteEdge("VignetteRight", UDim2.fromScale(SCREEN.VignetteSize, 1), Vector2.new(1, 0), 180)

	Scanlines = newFrame("Scanlines", ScreenGui)
	Scanlines.Size = UDim2.fromScale(1, 1)
	Scanlines.ClipsDescendants = true
	Scanlines.ZIndex = 3

	for index = 1, SCREEN.ScanlineCount do
		local line = newFrame("Line", Scanlines)
		line.BackgroundColor3 = COLORS.Scanline
		line.BackgroundTransparency = SCREEN.ScanlineTransparency
		line.Size = UDim2.new(1, 0, 0, 1)
		line.Position = UDim2.fromScale(0, (index - 1) / SCREEN.ScanlineCount)
	end

	Sweep = newFrame("Sweep", Scanlines)
	Sweep.BackgroundColor3 = COLORS.Sweep
	Sweep.Size = UDim2.fromScale(1, SCREEN.SweepHeight)

	local sweepGradient = Instance.new("UIGradient")
	sweepGradient.Rotation = 90
	sweepGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	sweepGradient.Parent = Sweep

	SliceHolder = newFrame("Slices", ScreenGui)
	SliceHolder.Size = UDim2.fromScale(1, 1)
	SliceHolder.ClipsDescendants = true
	SliceHolder.Visible = false
	SliceHolder.ZIndex = 5

	for _ = 1, SCREEN.GlitchSliceCount do
		local slice = newFrame("Slice", SliceHolder)
		slice.BackgroundColor3 = COLORS.Slice
		slice.BackgroundTransparency = SCREEN.GlitchSliceTransparency
		table.insert(Slices, slice)
	end

	Content = newFrame("Content", ScreenGui)
	Content.AnchorPoint = Vector2.new(0.5, 0.5)
	Content.Position = UDim2.fromScale(0.5, 0.46)
	Content.Size = UDim2.fromScale(SCREEN.ContentWidth, 0)
	Content.AutomaticSize = Enum.AutomaticSize.Y
	Content.ZIndex = 4

	local width = Instance.new("UISizeConstraint")
	width.MaxSize = Vector2.new(SCREEN.ContentMaxWidth, math.huge)
	width.Parent = Content

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, SCREEN.Spacing)
	layout.Parent = Content

	local eyebrowHolder = newFrame("Eyebrow", Content)
	eyebrowHolder.Size = UDim2.new(1, 0, 0, SCREEN.EyebrowSize + 4)
	eyebrowHolder.LayoutOrder = 1
	eyebrowHolder.ZIndex = 4

	Eyebrow = newLabel("Label", eyebrowHolder, SCREEN.EyebrowFont, SCREEN.EyebrowSize, COLORS.Eyebrow)
	Eyebrow.Size = UDim2.fromScale(1, 1)
	Eyebrow.Text = SCREEN.EyebrowText
	Eyebrow.ZIndex = 4

	NameHolder = newFrame("Name", Content)
	NameHolder.Size = UDim2.new(1, 0, 0, SCREEN.NameHeight)
	NameHolder.LayoutOrder = 2
	NameHolder.ZIndex = 4

	local function buildNameLabel(name: string, color: Color3, zIndex: number): TextLabel
		local label = newLabel(name, NameHolder, SCREEN.NameFont, SCREEN.NameHeight, color)
		label.Size = UDim2.fromScale(1, 1)
		label.TextScaled = true
		label.ZIndex = zIndex
		return label
	end

	NameRed = buildNameLabel("Red", COLORS.NameGhostRed, 4)
	NameCyan = buildNameLabel("Cyan", COLORS.NameGhostCyan, 5)
	NameMain = buildNameLabel("Main", COLORS.Name, 6)

	Rule = newFrame("Rule", Content)
	Rule.BackgroundColor3 = COLORS.Rule
	Rule.BackgroundTransparency = 1
	Rule.Size = UDim2.new(0, 0, 0, 1)
	Rule.LayoutOrder = 3
	Rule.ZIndex = 4

	Hint = newLabel("Hint", Content, SCREEN.HintFont, SCREEN.HintSize, COLORS.Hint)
	Hint.Size = UDim2.new(1, 0, 0, 0)
	Hint.AutomaticSize = Enum.AutomaticSize.Y
	Hint.TextWrapped = true
	Hint.LineHeight = 1.3
	Hint.Text = ""
	Hint.LayoutOrder = 4
	Hint.ZIndex = 4
end

local function beginBurst(now: number)
	BurstUntil = now + SCREEN.GlitchBurstTime
	NextBurstAt = now + randomRange(SCREEN.GlitchIntervalMin, SCREEN.GlitchIntervalMax)
	ContentShift = randomRange(-SCREEN.GlitchShift, SCREEN.GlitchShift)

	for _, slice in Slices do
		slice.Size = UDim2.new(1.4, 0, 0, math.random(2, SCREEN.GlitchSliceHeight))
		slice.Position = UDim2.new(randomRange(-0.2, 0.2), 0, math.random(), 0)
	end
end

local function teardown()
	Visible = false
	HidingAt = nil
	RunService:UnbindFromRenderStep(RENDER_JOB)
	ScreenGui.Enabled = false

	if Blur then
		Blur:Destroy()
		Blur = nil
	end
	if Correction then
		Correction:Destroy()
		Correction = nil
	end
end

local function render()
	local now = os.clock()
	local fade = if HidingAt
		then 1 - math.clamp((now - HidingAt) / SCREEN.FadeOutTime, 0, 1)
		else math.clamp((now - ShownAt) / SCREEN.FadeInTime, 0, 1)

	if fade <= 0 and HidingAt then
		Complete:FireServer(DeathToken)
		teardown()
		return
	end

	local elapsed = now - ShownAt

	if now >= NextBurstAt then
		beginBurst(now)
	end
	local bursting = now < BurstUntil
	SliceHolder.Visible = bursting

	if now >= NextJitterAt then
		NextJitterAt = now + JITTER_INTERVAL
		local split = if bursting then SCREEN.SplitBurst else SCREEN.SplitIdle
		SplitX = randomRange(-split, split)
		SplitY = randomRange(-split, split) * 0.35
	end

	Backdrop.BackgroundTransparency = 0

	if Blur then
		Blur.Size = SCREEN.BlurSize * fade
	end
	if Correction then
		Correction.Saturation = SCREEN.Saturation * fade
		Correction.Brightness = SCREEN.Brightness * fade
		Correction.Contrast = SCREEN.Contrast * fade
	end

	local breathe = math.sin(now * math.pi * 2 / SCREEN.VignetteBreatheTime) * SCREEN.VignetteBreathe
	local vignette = math.clamp(SCREEN.VignetteStrength + breathe, 0, 1)
	for _, edge in VignetteEdges do
		edge.BackgroundTransparency = 1 - (1 - vignette) * fade
	end

	Scanlines.Visible = fade > 0.15
	Sweep.Position = UDim2.fromScale(0, (elapsed / SCREEN.SweepTime % 1) * (1 + SCREEN.SweepHeight) - SCREEN.SweepHeight)
	Sweep.BackgroundTransparency = 1 - (1 - SCREEN.SweepTransparency) * fade

	for _, slice in Slices do
		slice.BackgroundTransparency = 1 - (1 - SCREEN.GlitchSliceTransparency) * fade
	end

	Content.Position = UDim2.new(0.5, if bursting then ContentShift else 0, 0.46, 0)

	local eyebrowIn = entrance(elapsed, SCREEN.EyebrowDelay)
	Eyebrow.TextTransparency = 1 - eyebrowIn * fade
	Eyebrow.Position = UDim2.fromOffset(0, (1 - eyebrowIn) * ENTRANCE_RISE)

	local nameIn = entrance(elapsed, SCREEN.NameDelay)
	local rise = (1 - nameIn) * ENTRANCE_RISE
	NameMain.TextTransparency = 1 - nameIn * fade
	NameMain.Position = UDim2.fromOffset(0, rise)
	NameRed.TextTransparency = 1 - nameIn * fade
	NameRed.Position = UDim2.fromOffset(-SplitX, rise - SplitY)
	NameCyan.TextTransparency = 1 - nameIn * fade
	NameCyan.Position = UDim2.fromOffset(SplitX, rise + SplitY)

	local ruleIn = entrance(elapsed, SCREEN.RuleDelay)
	Rule.Size = UDim2.new(ruleIn, 0, 0, 1)
	Rule.BackgroundTransparency = 1 - ruleIn * fade

	local typed = math.min(math.floor(math.max(0, elapsed - SCREEN.HintDelay) * SCREEN.TypeSpeed), #HintText)
	local blinking = typed < #HintText and (now / SCREEN.CursorBlinkTime) % 2 < 1
	if typed ~= TypedCount or blinking ~= CursorShown then
		TypedCount, CursorShown = typed, blinking
		Hint.Text = string.sub(HintText, 1, typed) .. (if blinking then CURSOR else "")
	end
	Hint.TextTransparency = 1 - fade
end

function DeathScreenService:Show(causeId: string?, token: number)
	if Visible then
		teardown()
	end

	local cause = (causeId and DeathConfig.Causes[causeId]) or DeathConfig.Unknown

	local name = string.upper(cause.Name)
	NameMain.Text = name
	NameRed.Text = name
	NameCyan.Text = name
	HintText = cause.Hint
	Hint.Text = ""
	TypedCount, CursorShown = -1, false

	ShownAt = os.clock()
	DeathToken = token
	HidingAt = nil
	NextBurstAt = ShownAt + SCREEN.FadeInTime
	NextJitterAt = 0
	Visible = true

	Blur = Instance.new("BlurEffect")
	Blur.Name = "DeathBlur"
	Blur.Size = 0
	Blur.Parent = Lighting

	Correction = Instance.new("ColorCorrectionEffect")
	Correction.Name = "DeathCorrection"
	Correction.Parent = Lighting

	ScreenGui.Enabled = true
	RunService:BindToRenderStep(RENDER_JOB, Enum.RenderPriority.Last.Value, render)
end

function DeathScreenService:IsVisible(): boolean
	return Visible
end

function DeathScreenService:Hide()
	if not Visible or HidingAt then return end

	local hold = math.max(
		SCREEN.MinimumTime,
		SCREEN.HintDelay + #HintText / SCREEN.TypeSpeed + SCREEN.ReadTime
	)

	local token = ShownAt
	task.delay(math.max(0, hold - (os.clock() - ShownAt)), function()
		if Visible and not HidingAt and ShownAt == token then
			HidingAt = os.clock()
		end
	end)
end

build()

Show.OnClientEvent:Connect(function(causeId: string?, token: number)
	DeathScreenService:Show(causeId, token)
end)

LocalPlayer.CharacterAdded:Connect(function()
	DeathScreenService:Hide()
end)

return DeathScreenService
