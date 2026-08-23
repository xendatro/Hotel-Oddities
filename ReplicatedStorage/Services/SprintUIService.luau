local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SprintConfig = require(ReplicatedStorage.Configs.SprintConfig)
local SprintService = require(ReplicatedStorage.Services.SprintService)

local SprintUIService = {}

if not RunService:IsClient() then
	return SprintUIService
end

local UI = SprintConfig.UI
local COLORS = UI.Colors
local TRANSPARENCY = UI.Transparency
local RENDER_JOB = "SprintBar"
local TAU = math.pi * 2

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local group: CanvasGroup
local track: Frame
local stroke: UIStroke
local fill: Frame
local gradient: UIGradient

local function build()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SprintGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 9
	screenGui.Parent = playerGui

	group = Instance.new("CanvasGroup")
	group.Name = "Stamina"
	group.AnchorPoint = Vector2.new(0.5, 1)
	group.Position = UDim2.new(0.5, 0, 1, -(UI.BottomMargin - UI.Padding))
	group.Size = UDim2.fromOffset(UI.Width + UI.Padding * 2, UI.Height + UI.Padding * 2)
	group.BackgroundTransparency = 1
	group.GroupTransparency = 1
	group.Parent = screenGui

	track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.fromOffset(UI.Padding, UI.Padding)
	track.Size = UDim2.fromOffset(UI.Width, UI.Height)
	track.BackgroundColor3 = COLORS.Track
	track.BackgroundTransparency = TRANSPARENCY.Track
	track.BorderSizePixel = 0
	track.Parent = group

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, UI.CornerRadius)
	trackCorner.Parent = track

	stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.Stroke
	stroke.Transparency = TRANSPARENCY.Stroke
	stroke.Thickness = 1
	stroke.Parent = track

	fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, UI.CornerRadius)
	fillCorner.Parent = fill

	gradient = Instance.new("UIGradient")
	gradient.Parent = fill
end

local fillFrom = COLORS.Fill
local fillTo = COLORS.FillEdge
local exhaustWeight = 0

local function settled(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < 1 / 255
		and math.abs(a.G - b.G) < 1 / 255
		and math.abs(a.B - b.B) < 1 / 255
end

local function easeFillColors(from: Color3, to: Color3, alpha: number)
	if settled(fillFrom, from) and settled(fillTo, to) then
		if fillFrom == from and fillTo == to then return end
		fillFrom, fillTo = from, to
	else
		fillFrom = fillFrom:Lerp(from, alpha)
		fillTo = fillTo:Lerp(to, alpha)
	end
	gradient.Color = ColorSequence.new(fillFrom, fillTo)
end

local shown = 1
local alpha = 0
local fullTime = 0
local forced = false

function SprintUIService:SetForcedVisible(value: boolean)
	forced = value
end

function SprintUIService:GetBar()
	return {
		Group = group,
		Track = track,
		Fill = fill,
		Stroke = stroke,
	}
end

local function render(deltaTime: number)
	local fraction = SprintService:GetStaminaFraction()
	local exhausted = SprintService:IsExhausted()

	shown += (fraction - shown) * (1 - math.exp(-UI.FollowSpeed * deltaTime))
	if math.abs(fraction - shown) < 1e-3 then shown = fraction end

	local full = fraction >= 1 and shown >= 0.999 and not exhausted
	fullTime = if full then fullTime + deltaTime else 0

	local target = if forced or not full or fullTime < UI.FullHoldTime then 1 else 0
	if alpha < target then
		alpha = math.min(alpha + deltaTime / UI.FadeInTime, target)
	elseif alpha > target then
		alpha = math.max(alpha - deltaTime / UI.FadeOutTime, target)
	end
	group.GroupTransparency = 1 - alpha
	group.Visible = alpha > 0
	if alpha <= 0 then return end

	fill.Size = UDim2.fromScale(shown, 1)

	local fillTarget, edgeTarget
	if exhausted or shown <= UI.EmptyThreshold then
		fillTarget, edgeTarget = COLORS.Empty, COLORS.Empty
	elseif shown <= UI.LowThreshold then
		fillTarget, edgeTarget = COLORS.Low, COLORS.Low
	else
		fillTarget, edgeTarget = COLORS.Fill, COLORS.FillEdge
	end
	easeFillColors(fillTarget, edgeTarget, 1 - math.exp(-UI.ColorFollowSpeed * deltaTime))

	local exhaustTarget = if exhausted then 1 else 0
	exhaustWeight += (exhaustTarget - exhaustWeight) * (1 - math.exp(-UI.ExhaustBlendSpeed * deltaTime))
	if math.abs(exhaustTarget - exhaustWeight) < 1e-3 then exhaustWeight = exhaustTarget end

	local pulse = (math.sin(os.clock() * TAU / UI.EmptyPulsePeriod) + 1) / 2 * exhaustWeight
	track.BackgroundColor3 = COLORS.Track:Lerp(COLORS.Empty, UI.EmptyTrackTint * pulse)
	stroke.Color = COLORS.Stroke:Lerp(COLORS.Empty, exhaustWeight)
	stroke.Transparency = TRANSPARENCY.Stroke * (1 - pulse * 0.8)
end

build()
RunService:BindToRenderStep(RENDER_JOB, Enum.RenderPriority.Last.Value, render)

return SprintUIService
