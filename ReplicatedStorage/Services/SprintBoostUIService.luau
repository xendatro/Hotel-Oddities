local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SprintBoostConfig = require(ReplicatedStorage.Configs.SprintBoostConfig)
local SprintConfig = require(ReplicatedStorage.Configs.SprintConfig)
local SprintUIService = require(ReplicatedStorage.Services.SprintUIService)

local SprintBoostUIService = {}

if not RunService:IsClient() then
	return SprintBoostUIService
end

type Visual = SprintBoostConfig.BoostVisual

local UI = SprintConfig.UI
local RENDER_JOB = "SprintBoostBar"
local TAU = math.pi * 2
local MAX_RINGS = 3

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local bar = SprintUIService:GetBar()
local groupScale: UIScale
local overlayScale: UIScale

local boostFill: CanvasGroup
local boostBase: Frame
local boostGradient: UIGradient
local sheen: Frame
local sheenGradient: UIGradient
local streaks: Frame
local streakGradient: UIGradient
local edge: Frame
local flash: Frame

local overlay: Frame
local aura: Frame
local auraStroke: UIStroke
local rings: { Frame } = {}
local ringStrokes: { UIStroke } = {}
local ringTimes: { number } = {}
local timerTrack: Frame
local timerFill: Frame
local label: TextLabel
local labelShadows: { TextLabel } = {}

local function rounded(instance: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function buildFill()
	boostFill = Instance.new("CanvasGroup")
	boostFill.Name = "Boost"
	boostFill.Size = UDim2.fromScale(1, 1)
	boostFill.BackgroundTransparency = 1
	boostFill.GroupTransparency = 1
	boostFill.ClipsDescendants = true
	boostFill.Visible = false
	boostFill.Parent = bar.Fill
	rounded(boostFill, UI.CornerRadius)

	boostBase = Instance.new("Frame")
	boostBase.Name = "Base"
	boostBase.Size = UDim2.fromScale(1, 1)
	boostBase.BackgroundColor3 = Color3.new(1, 1, 1)
	boostBase.BorderSizePixel = 0
	boostBase.Parent = boostFill

	boostGradient = Instance.new("UIGradient")
	boostGradient.Parent = boostBase

	streaks = Instance.new("Frame")
	streaks.Name = "Streaks"
	streaks.Size = UDim2.fromScale(2, 1)
	streaks.BackgroundColor3 = Color3.new(1, 1, 1)
	streaks.BorderSizePixel = 0
	streaks.Parent = boostFill

	streakGradient = Instance.new("UIGradient")
	streakGradient.Parent = streaks

	sheen = Instance.new("Frame")
	sheen.Name = "Sheen"
	sheen.Size = UDim2.fromScale(1, 1)
	sheen.BackgroundColor3 = Color3.new(1, 1, 1)
	sheen.BorderSizePixel = 0
	sheen.Parent = boostFill

	sheenGradient = Instance.new("UIGradient")
	sheenGradient.Parent = sheen

	edge = Instance.new("Frame")
	edge.Name = "Edge"
	edge.AnchorPoint = Vector2.new(1, 0.5)
	edge.Position = UDim2.fromScale(1, 0.5)
	edge.Size = UDim2.new(0, 0, 1, 0)
	edge.BackgroundColor3 = Color3.new(1, 1, 1)
	edge.BorderSizePixel = 0
	edge.Parent = boostFill
end

local function buildOverlay()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SprintBoostGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 8
	screenGui.Parent = playerGui

	overlay = Instance.new("Frame")
	overlay.Name = "Boost"
	overlay.AnchorPoint = Vector2.new(0.5, 1)
	overlay.Position = UDim2.new(0.5, 0, 1, -UI.BottomMargin)
	overlay.Size = UDim2.fromOffset(UI.Width, UI.Height)
	overlay.BackgroundTransparency = 1
	overlay.Visible = false
	overlay.Parent = screenGui

	overlayScale = Instance.new("UIScale")
	overlayScale.Parent = overlay

	aura = Instance.new("Frame")
	aura.Name = "Aura"
	aura.AnchorPoint = Vector2.new(0.5, 0.5)
	aura.Position = UDim2.fromScale(0.5, 0.5)
	aura.Size = UDim2.new(1, SprintBoostConfig.AuraInset * 2, 1, SprintBoostConfig.AuraInset * 2)
	aura.BackgroundTransparency = 1
	aura.Parent = overlay
	rounded(aura, SprintBoostConfig.AuraCorner)

	auraStroke = Instance.new("UIStroke")
	auraStroke.Transparency = 1
	auraStroke.Parent = aura

	for index = 1, MAX_RINGS do
		local ring = Instance.new("Frame")
		ring.Name = `Ring{index}`
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromScale(1, 1)
		ring.BackgroundTransparency = 1
		ring.Visible = false
		ring.Parent = overlay
		rounded(ring, SprintBoostConfig.AuraCorner)

		local ringStroke = Instance.new("UIStroke")
		ringStroke.Transparency = 1
		ringStroke.Parent = ring

		rings[index] = ring
		ringStrokes[index] = ringStroke
		ringTimes[index] = math.huge
	end

	flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 4
	flash.Parent = overlay
	rounded(flash, UI.CornerRadius)

	timerTrack = Instance.new("Frame")
	timerTrack.Name = "Timer"
	timerTrack.AnchorPoint = Vector2.new(0.5, 0)
	timerTrack.Position = UDim2.new(0.5, 0, 1, SprintBoostConfig.TimerGap)
	timerTrack.Size = UDim2.new(1, 0, 0, 2)
	timerTrack.BackgroundColor3 = UI.Colors.Track
	timerTrack.BackgroundTransparency = 1
	timerTrack.BorderSizePixel = 0
	timerTrack.Parent = overlay
	rounded(timerTrack, 2)

	timerFill = Instance.new("Frame")
	timerFill.Name = "Fill"
	timerFill.AnchorPoint = Vector2.new(0.5, 0)
	timerFill.Position = UDim2.fromScale(0.5, 0)
	timerFill.Size = UDim2.fromScale(1, 1)
	timerFill.BackgroundColor3 = Color3.new(1, 1, 1)
	timerFill.BorderSizePixel = 0
	timerFill.Parent = timerTrack
	rounded(timerFill, 2)

	for index = 1, 3 do
		local text = Instance.new("TextLabel")
		text.Name = if index == 3 then "Label" else `Shadow{index}`
		text.AnchorPoint = Vector2.new(0.5, 1)
		text.Position = UDim2.new(0.5, 0, 0, 0)
		text.Size = UDim2.new(1, 0, 0, 20)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBlack
		text.Text = ""
		text.TextTransparency = 1
		text.ZIndex = index + 4
		text.Parent = overlay

		if index == 3 then
			label = text
		else
			labelShadows[index] = text
		end
	end
end

local function streakSequence(bands: number, strength: number): NumberSequence
	if bands <= 0 then
		return NumberSequence.new(1)
	end

	local points = { NumberSequenceKeypoint.new(0, 1) }
	local steps = bands * 4
	for step = 1, steps - 1 do
		local time = step / steps
		local dark = step % 2 == 1
		table.insert(points, NumberSequenceKeypoint.new(time, if dark then 1 - strength else 1))
	end
	table.insert(points, NumberSequenceKeypoint.new(1, 1))
	return NumberSequence.new(points)
end

local function sheenSequence(width: number, strength: number): NumberSequence
	local half = math.clamp(width, 0.02, 0.24)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(math.max(0.5 - half, 0.01), 1),
		NumberSequenceKeypoint.new(0.5, 1 - strength),
		NumberSequenceKeypoint.new(math.min(0.5 + half, 0.99), 1),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local function tracked(text: string, spaces: number): string
	if spaces <= 0 then return text end

	local gap = string.rep(" ", spaces)
	local out = {}
	for character in string.gmatch(text, ".") do
		table.insert(out, character)
	end
	return table.concat(out, gap)
end

local active: Visual? = nil
local activeName: string? = nil
local shape: Visual = SprintBoostConfig.Boosts.Soda
local weight = 0
local popTime = math.huge
local flashTime = math.huge
local boostStart = 0
local boostEnd = 0

local function applyVisual(visual: Visual)
	streakGradient.Transparency = streakSequence(visual.StreakBands, visual.StreakStrength)
	streakGradient.Rotation = visual.StreakRotation
	sheenGradient.Transparency = sheenSequence(visual.SheenWidth, visual.SheenStrength)
	boostGradient.Rotation = visual.GradientRotation
	timerTrack.Size = UDim2.new(1, 0, 0, visual.TimerHeight)

	local text = tracked(visual.Label, visual.LabelTracking)
	label.Text = text
	label.TextSize = visual.LabelSize
	label.Position = UDim2.new(0.5, 0, 0, -visual.LabelGap)

	for index, shadow in labelShadows do
		shadow.Text = if visual.Chromatic then text else ""
		shadow.TextSize = visual.LabelSize
		shadow.TextColor3 = if index == 1 then visual.Fill else visual.FillAlt
		shadow.Position = UDim2.new(0.5, if index == 1 then -2 else 2, 0, -visual.LabelGap)
	end
end

local function burst(visual: Visual)
	popTime = 0
	flashTime = 0
	for index = 1, math.min(visual.Rings, MAX_RINGS) do
		ringTimes[index] = -(index - 1) * visual.RingDelay
	end
end

local function refresh()
	local name = player:GetAttribute("SpeedBoostName")
	local visual = if type(name) == "string" then SprintBoostConfig.Boosts[name] else nil
	local endsAt = player:GetAttribute("SpeedBoostEndsAt")

	if not visual then
		active = nil
		activeName = nil
		return
	end

	local restarted = activeName ~= name
	active = visual
	shape = visual
	activeName = name

	if type(endsAt) == "number" and endsAt ~= boostEnd then
		boostStart = workspace:GetServerTimeNow()
		boostEnd = endsAt
		restarted = true
	end

	if restarted then
		applyVisual(visual)
		burst(visual)
	end
end

local function renderRings(visual: Visual, deltaTime: number)
	for index, ring in rings do
		local elapsed = ringTimes[index]
		if elapsed == math.huge then continue end

		elapsed += deltaTime
		ringTimes[index] = elapsed
		if elapsed < 0 then continue end

		local progress = elapsed / visual.RingTime
		if progress >= 1 then
			ringTimes[index] = math.huge
			ring.Visible = false
			continue
		end

		local eased = 1 - (1 - progress) ^ 3
		local grow = visual.RingGrowth * eased
		ring.Visible = true
		ring.Size = UDim2.new(1, grow, 1, grow)
		ringStrokes[index].Color = visual.Glow
		ringStrokes[index].Thickness = math.max(visual.RingThickness * (1 - eased), 0.1)
		ringStrokes[index].Transparency = eased
	end
end

local function renderIdle()
	if popTime ~= math.huge then
		popTime = math.huge
		groupScale.Scale = 1
		overlayScale.Scale = 1
	end
	if overlay.Visible then
		overlay.Visible = false
		boostFill.Visible = false
	end
	SprintUIService:SetForcedVisible(false)
end

local function render(deltaTime: number)
	local visual = active
	if not visual and weight <= 0 then
		renderIdle()
		return
	end

	if visual then
		weight = math.min(weight + deltaTime / shape.BlendInTime, 1)
	else
		weight = math.max(weight - deltaTime / shape.BlendOutTime, 0)
	end

	local now = os.clock()
	local ease = weight * weight * (3 - 2 * weight)

	overlay.Visible = true
	boostFill.Visible = true
	SprintUIService:SetForcedVisible(active ~= nil)

	local shift = (math.sin(now * TAU / shape.ShiftPeriod) + 1) / 2
	local main = shape.Fill:Lerp(shape.FillAlt, shift)
	boostGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, main),
		ColorSequenceKeypoint.new(0.25, shape.FillEdge),
		ColorSequenceKeypoint.new(0.5, shape.Accent:Lerp(main, 0.4)),
		ColorSequenceKeypoint.new(0.75, shape.FillEdge),
		ColorSequenceKeypoint.new(1, main),
	})
	boostGradient.Offset = Vector2.new((now * shape.GradientScroll) % 1 - 0.5, 0)
	boostFill.GroupTransparency = 1 - ease

	sheenGradient.Offset = Vector2.new(((now / shape.SheenPeriod) % 1) * 2 - 1, 0)
	streaks.Position = UDim2.fromScale(-((now / shape.StreakPeriod) % 1), 0)
	streaks.Visible = shape.StreakBands > 0

	if shape.EdgeWidth > 0 then
		local flicker = (math.sin(now * TAU / (shape.GlowPulsePeriod * 0.5)) + 1) / 2
		edge.Visible = true
		edge.Size = UDim2.new(0, shape.EdgeWidth, 1, 0)
		edge.BackgroundColor3 = shape.Accent
		edge.BackgroundTransparency = shape.EdgePulse * flicker
	else
		edge.Visible = false
	end

	if flashTime ~= math.huge then
		flashTime += deltaTime
		local progress = flashTime / shape.FlashTime
		if progress >= 1 then
			flashTime = math.huge
			flash.BackgroundTransparency = 1
		else
			flash.BackgroundTransparency = 1 - shape.FlashStrength * (1 - progress)
		end
	end

	local pulse = (math.sin(now * TAU / shape.GlowPulsePeriod) + 1) / 2
	auraStroke.Color = shape.Glow
	auraStroke.Thickness = shape.GlowThickness * (1 + shape.GlowPulse * pulse) * ease
	auraStroke.Transparency = 1 - (1 - shape.GlowTransparency) * ease

	local remaining = 0
	if boostEnd > boostStart then
		remaining = math.clamp((boostEnd - workspace:GetServerTimeNow()) / (boostEnd - boostStart), 0, 1)
	end
	timerTrack.BackgroundTransparency = 1 - 0.55 * ease
	timerFill.Size = UDim2.fromScale(remaining, 1)
	timerFill.BackgroundColor3 = shape.Accent
	timerFill.BackgroundTransparency = 1 - ease

	local flicker = 0
	if shape.LabelFlicker > 0 then
		flicker = shape.LabelFlicker * (math.sin(now * 37) * 0.5 + math.sin(now * 61) * 0.5) ^ 2
	end
	local fade = math.clamp(1 - ease + flicker, 0, 1)
	label.TextColor3 = shape.Accent
	label.TextTransparency = fade
	for _, shadow in labelShadows do
		shadow.TextTransparency = math.clamp(fade + 0.45, 0, 1)
	end

	if popTime ~= math.huge then
		popTime += deltaTime
		local progress = popTime / shape.PopTime
		if progress >= 1 then
			popTime = math.huge
			groupScale.Scale = 1
			overlayScale.Scale = 1
		else
			local pop = math.exp(-6 * progress) * math.sin(progress * TAU * 1.8) * 2.2
			local scale = 1 + shape.PopScale * pop
			groupScale.Scale = scale
			overlayScale.Scale = scale
		end
	end

	renderRings(shape, deltaTime)
end

buildFill()
buildOverlay()

groupScale = Instance.new("UIScale")
groupScale.Parent = bar.Group

applyVisual(SprintBoostConfig.Boosts.Soda)
player:GetAttributeChangedSignal("SpeedBoostName"):Connect(refresh)
player:GetAttributeChangedSignal("SpeedBoostEndsAt"):Connect(refresh)
refresh()

RunService:BindToRenderStep(RENDER_JOB, Enum.RenderPriority.Last.Value + 1, render)

return SprintBoostUIService
