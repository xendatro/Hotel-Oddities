--- The screen you get for dying: the world drains away behind a black plate, and what is left is the
--- name of the thing that killed you and the one thing you should have known about it. The server
--- sends nothing but a cause id; the name and the hint come out of `DeathConfig` on this side.
---
--- Everything visible is built here in code, so there is no StarterGui asset to keep in sync, and
--- every number it draws with lives in `DeathConfig.Screen`.
---
--- There is one render loop and no tweens. Every animation on the screen -- the fade, the entrance of
--- each line of text, the typing, the colour split, the glitch bursts -- is a pure function of how
--- long the screen has been up, which is what makes the whole thing cancellable by dropping a single
--- timestamp. A respawn part way through an entrance has nothing to cancel and nothing to clean up.

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
local ENTRANCE_TIME = 0.5 -- seconds each line of text takes to arrive once its delay has passed
local ENTRANCE_RISE = 10 -- pixels it travels while doing so
local JITTER_INTERVAL = 0.05 -- seconds between colour-split re-rolls; per-frame reads as a strobe
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

-- Smoothstep from 0 to 1 over `duration` seconds, starting `delay` seconds into the screen's life.
local function entrance(elapsed: number, delay: number): number
	local progress = math.clamp((elapsed - delay) / ENTRANCE_TIME, 0, 1)
	return progress * progress * (3 - 2 * progress)
end

--- Building the interface ------------------------------------------------------------------------

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

-- One edge of the vignette. The gradient runs from solid at the edge to clear `VignetteSize` of the
-- screen inward; how dark "solid" actually is comes off the frame's own transparency, which is what
-- lets the whole vignette breathe and fade without rebuilding four gradients every frame.
local function buildVignetteEdge(name: string, size: UDim2, anchor: Vector2, rotation: number)
	local edge = newFrame(name, ScreenGui)
	edge.BackgroundColor3 = COLORS.Backdrop
	edge.Size = size
	edge.AnchorPoint = anchor
	edge.Position = UDim2.fromScale(anchor.X, anchor.Y)
	edge.ZIndex = 2

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	-- Eased rather than linear. A straight ramp lands on clear with a corner in it, and the eye reads
	-- that corner as a horizontal seam across the screen where the vignette stops.
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
	Backdrop.Size = UDim2.fromScale(1, 1)
	Backdrop.ZIndex = 1

	buildVignetteEdge("VignetteTop", UDim2.fromScale(1, SCREEN.VignetteSize), Vector2.new(0, 0), 90)
	buildVignetteEdge("VignetteBottom", UDim2.fromScale(1, SCREEN.VignetteSize), Vector2.new(0, 1), 270)
	buildVignetteEdge("VignetteLeft", UDim2.fromScale(SCREEN.VignetteSize, 1), Vector2.new(0, 0), 0)
	buildVignetteEdge("VignetteRight", UDim2.fromScale(SCREEN.VignetteSize, 1), Vector2.new(1, 0), 180)

	-- CRT lines over everything, and the brighter band that crawls down through them. Static
	-- transparency: at 0.93 a line is too faint for fading it in to be worth a frame of work.
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

	-- Torn bars thrown across the screen during a glitch. Parked off screen the rest of the time.
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

	-- Every animated line gets a holder in the layout and moves inside it. A `UIListLayout` owns the
	-- position of its own children, so a label placed straight into one cannot be made to rise.
	local eyebrowHolder = newFrame("Eyebrow", Content)
	eyebrowHolder.Size = UDim2.new(1, 0, 0, SCREEN.EyebrowSize + 4)
	eyebrowHolder.LayoutOrder = 1
	eyebrowHolder.ZIndex = 4

	Eyebrow = newLabel("Label", eyebrowHolder, SCREEN.EyebrowFont, SCREEN.EyebrowSize, COLORS.Eyebrow)
	Eyebrow.Size = UDim2.fromScale(1, 1)
	Eyebrow.Text = SCREEN.EyebrowText
	Eyebrow.ZIndex = 4

	-- The three name labels sit on top of each other for the same reason, because the colour split is
	-- two copies of the same word thrown a few pixels either side of the one you read.
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

--- Drawing ----------------------------------------------------------------------------------------

-- Picks fresh positions for the torn bars and starts a burst. Called once per burst, not per frame.
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

	-- What is left of the world: nearly black, blurred and drained of colour, and let back through a
	-- shade further during a burst so the room behind flickers rather than the plate over it.
	local backdropTarget = if bursting then SCREEN.BackdropTransparency + 0.14 else SCREEN.BackdropTransparency
	Backdrop.BackgroundTransparency = 1 - (1 - backdropTarget) * fade

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

	-- The hint types itself. How much of it is on screen is a function of the clock rather than a
	-- counter, so a screen that fades out mid-word leaves nothing running behind it. Only written
	-- when it actually changes: wrapped text with an automatic height re-lays-out on every write.
	local typed = math.min(math.floor(math.max(0, elapsed - SCREEN.HintDelay) * SCREEN.TypeSpeed), #HintText)
	local blinking = typed < #HintText and (now / SCREEN.CursorBlinkTime) % 2 < 1
	if typed ~= TypedCount or blinking ~= CursorShown then
		TypedCount, CursorShown = typed, blinking
		Hint.Text = string.sub(HintText, 1, typed) .. (if blinking then CURSOR else "")
	end
	Hint.TextTransparency = 1 - fade
end

--- Showing and hiding -----------------------------------------------------------------------------

--- Puts the screen up for a death caused by `causeId`. An id with no entry in `DeathConfig.Causes`,
--- and a death nothing claimed at all, both land on the `Unknown` cause.
function DeathScreenService:Show(causeId: string?, token: number)
	if Visible then
		teardown() -- a second death before the first screen left; start the new one from scratch
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

--- Whether the screen is still on top of everything -- including the stretch where it is holding a
--- finished hint, and the fade out. False only once `teardown` has run and the world is plainly
--- visible again.
---
--- Exists so anything the game puts in front of the player after a death can wait its turn. The
--- index does: it opens itself to show what dying just taught you, and doing that under a death
--- screen that is still typing means both animations play at once and neither is readable.
function DeathScreenService:IsVisible(): boolean
	return Visible
end

--- Starts the screen fading out, holding it first until it has finished typing the hint and been sat
--- with for `ReadTime`. Respawning is what calls this, and a respawn is not a reason to stop saying
--- something the player has not finished reading.
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
