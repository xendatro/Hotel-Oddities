local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local DangerField = require(ReplicatedStorage.Services.DangerFieldService)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
local LobbyService = require(ReplicatedStorage.Services.LobbyService)
local MathService = require(ReplicatedStorage.Services.MathService)
local TopHUDConfig = require(ReplicatedStorage.Configs.TopHUDConfig)

local TopHUDService = {}

if not RunService:IsClient() then
	return TopHUDService
end

local ROLL = TopHUDConfig.Roll
local DANGER = TopHUDConfig.Danger
local TIERS = DANGER.Tiers
local RENDER_JOB = "TopHud"
local WHITE = Color3.new(1, 1, 1)

local player = Players.LocalPlayer

local gui = GuiBuilderService.GetPlayerGui():WaitForChild(TopHUDConfig.Gui) :: ScreenGui
local design = gui:WaitForChild("Design") :: Frame
local scale = design:WaitForChild("Scale") :: UIScale
local dangerFrame = design:WaitForChild("Danger") :: Frame
local level = dangerFrame:WaitForChild("Level") :: TextLabel
local glowStroke = dangerFrame:WaitForChild("Glow"):WaitForChild("Stroke") :: UIStroke
local track = dangerFrame:WaitForChild("Track") :: Frame
local trackStroke = track:WaitForChild("Stroke") :: UIStroke
local fill = track:WaitForChild("Fill") :: Frame
local gradient = fill:WaitForChild("Gradient") :: UIGradient
local notches = track:WaitForChild("Notches") :: Frame

type Counter = {
	Attribute: string,
	Flash: Color3,
	Pop: UIScale,
	Current: TextLabel,
	Next: TextLabel,
	StrokeTransparency: number,
	Value: number?,
	Tweens: { Tween },
}

local function stroke(label: TextLabel): UIStroke
	return label:FindFirstChildOfClass("UIStroke") :: UIStroke
end

local function setAlpha(counter: Counter, label: TextLabel, transparency: number)
	label.TextTransparency = transparency
	stroke(label).Transparency = counter.StrokeTransparency + (1 - counter.StrokeTransparency) * transparency
end

local function play(counter: Counter, instance: Instance, info: TweenInfo, goal: { [string]: any })
	local tween = TweenService:Create(instance, info, goal)
	table.insert(counter.Tweens, tween)
	tween:Play()
end

local function settle(counter: Counter)
	for _, tween in counter.Tweens do
		tween:Cancel()
	end
	table.clear(counter.Tweens)

	counter.Current.Position = UDim2.fromScale(0, 0)
	counter.Current.TextColor3 = WHITE
	setAlpha(counter, counter.Current, 0)
	counter.Next.Position = UDim2.fromScale(0, 1)
	setAlpha(counter, counter.Next, 1)
	counter.Pop.Scale = 1
end

local function roll(counter: Counter, value: number)
	local previous = counter.Value
	counter.Value = value
	settle(counter)

	if previous == nil or previous == value then
		counter.Current.Text = MathService.Comma(value)
		return
	end

	local rising = value > previous
	local direction = if rising then 1 else -1
	local outgoing, incoming = counter.Current, counter.Next
	counter.Current, counter.Next = incoming, outgoing

	incoming.Text = MathService.Comma(value)
	incoming.Position = UDim2.fromScale(0, direction)
	incoming.TextColor3 = if rising then counter.Flash else WHITE

	local slide = TweenInfo.new(ROLL.Time, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	play(counter, outgoing, slide, { Position = UDim2.fromScale(0, -direction), TextTransparency = 1 })
	play(counter, stroke(outgoing), slide, { Transparency = 1 })
	play(counter, incoming, slide, { Position = UDim2.fromScale(0, 0), TextTransparency = 0 })
	play(counter, stroke(incoming), slide, { Transparency = counter.StrokeTransparency })

	if not rising then return end

	local fade = TweenInfo.new(ROLL.FlashFade, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, ROLL.FlashHold)
	play(counter, incoming, fade, { TextColor3 = WHITE })

	counter.Pop.Scale = ROLL.PopScale
	play(counter, counter.Pop, TweenInfo.new(ROLL.PopTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
end

local function bindCounter(name: string, settings: { Attribute: string, Flash: Color3 })
	local frame = design:WaitForChild(name)
	local amount = frame:WaitForChild("Amount")
	local current = amount:WaitForChild("Current") :: TextLabel

	local counter: Counter = {
		Attribute = settings.Attribute,
		Flash = settings.Flash,
		Pop = frame:WaitForChild("Icon"):WaitForChild("Pop") :: UIScale,
		Current = current,
		Next = amount:WaitForChild("Next") :: TextLabel,
		StrokeTransparency = stroke(current).Transparency,
		Value = nil,
		Tweens = {},
	}

	local function refresh()
		local value = player:GetAttribute(counter.Attribute)
		if type(value) ~= "number" then return end
		roll(counter, math.max(0, math.floor(value)))
	end

	player:GetAttributeChangedSignal(counter.Attribute):Connect(refresh)
	refresh()
end

for name, settings in TopHUDConfig.Currencies do
	bindCounter(name, settings)
end

local template = notches:WaitForChild("Notch") :: Frame
for index = 2, #TIERS do
	local notch = template:Clone()
	notch.Name = TIERS[index].Name
	notch.Position = UDim2.fromScale(TIERS[index].Threshold, 0.5)
	notch.Parent = notches
end
template:Destroy()

local function tierAt(value: number): number
	local index = 1
	for candidate, tier in TIERS do
		if value >= tier.Threshold then index = candidate end
	end
	return index
end

local target = 0
local known = false
local inLobby = false
local shown = 0
local glow = 0
local phase = 0
local tierIndex = 0
local fillFrom = TIERS[1].Fill
local fillTo = TIERS[1].FillEdge
local accumulator = DANGER.Interval

local function sample()
	local root = CharacterService.GetAliveRoot(player)
	local humanoid = CharacterService.GetHumanoid(player.Character)
	if humanoid and humanoid.FloorMaterial ~= Enum.Material.Air then
		inLobby = LobbyService:IsPlayerOnLobbyFloor()
	end

	local settings = DangerField.GetReplicatedSettings()
	known = settings ~= nil
	target = if settings and root and not inLobby then DangerField.Sample(root.Position, settings) else 0
end

local function render(deltaTime: number)
	local camera = workspace.CurrentCamera
	if camera then
		local viewport = camera.ViewportSize
		local widthScale = viewport.X / TopHUDConfig.ReferenceWidth
		local heightScale = viewport.Y / TopHUDConfig.ReferenceHeight
		scale.Scale = math.clamp(math.min(widthScale, heightScale), TopHUDConfig.MinScale, TopHUDConfig.MaxScale)
	end

	accumulator += deltaTime
	if accumulator >= DANGER.Interval then
		accumulator = 0
		sample()
	end

	shown += (target - shown) * MathService.ExpAlpha(DANGER.FollowSpeed, deltaTime)
	fill.Size = UDim2.fromScale(shown, 1)
	fill.Visible = shown > 0.005

	local index = tierAt(shown)
	local tier = TIERS[index]
	local shownIndex = if known then index else 0
	if shownIndex ~= tierIndex then
		tierIndex = shownIndex
		level.Text = if known then tier.Name else DANGER.Unknown
	end

	local colorAlpha = MathService.ExpAlpha(DANGER.ColorFollowSpeed, deltaTime)
	fillFrom = fillFrom:Lerp(tier.Fill, colorAlpha)
	fillTo = fillTo:Lerp(tier.FillEdge, colorAlpha)
	gradient.Color = ColorSequence.new(fillFrom, fillTo)
	level.TextColor3 = fillFrom

	glow += (tier.Glow - glow) * MathService.ExpAlpha(DANGER.GlowFollowSpeed, deltaTime)
	phase = (phase + deltaTime / math.max(tier.PulsePeriod, 1e-3)) % 1
	local pulse = MathService.SinePulse(phase, 1) * glow

	glowStroke.Transparency = 1 - (1 - DANGER.GlowMinTransparency) * pulse
	trackStroke.Color = DANGER.Stroke:Lerp(DANGER.GlowColor, DANGER.StrokeTint * glow)
	track.BackgroundColor3 = DANGER.Track:Lerp(DANGER.GlowColor, DANGER.TrackTint * pulse)
end

RunService:BindToRenderStep(RENDER_JOB, Enum.RenderPriority.Last.Value, render)

return TopHUDService
